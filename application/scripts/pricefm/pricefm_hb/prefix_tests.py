"""Metadata/scientific-DAG and mocked arithmetic-boundary tests; no NumPy."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from . import prefix as p, registry as r

PLAN = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_hb_scientific_preparation_20261027/benchmark_plans/FI_COST_PANEL_NOT_ADMITTED.json')


def fixture():
    cost=r.read(PLAN);prep,config=p.metadata(cost);tasks={t['name']:t for t in prep['tasks']}
    rows=[]
    for call in cost['schedule']:
        if call['kind']!='timed_prediction':continue
        t=tasks[call['task']]
        rows.append(dict(mode=call['mode'],package_id=call['package_id'],repetition=call['repetition'],p=call['p'],
            spec=t['spec'],origin_count=8,split=3,clock_offset_steps=0,cold_context_cpu_seconds=.02,
            arithmetic_cpu_seconds=.05,serialization_cpu_seconds=.01))
    timing=dict(status='COMPLETE_COST_ONLY_18_CALL_PANEL_NO_SELECTION_NO_ADMISSION',arithmetic_calls=18,rows=rows,
        no_new_candidate_AQL_computed=True,no_scientific_selection=True,new_model_fits=0,official_origins=0,
        aggregate_CPU_seconds=20.,elapsed_seconds=21.,startup_cpu_seconds=.1,numerical_preflight={'parents':60})
    return cost,prep,config,timing


class PricingAndSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.cost,cls.prep,cls.config,cls.timing=fixture()
    def test_import_does_not_load_numerical_packages(self):
        self.assertNotIn('numpy',sys.modules);self.assertNotIn('scipy',sys.modules)
    def test_original_function_globals_and_AST_are_loaded_without_editing(self):
        fn=p.original('chunks');task=self.prep['tasks'][0];chunks=fn(task)
        self.assertEqual({x['clock_offset_steps'] for x in chunks},{0,24,48,72})
        self.assertEqual(sum(len(x['origin_positions']) for x in chunks),4*len(task['daily_origin_positions']))
        self.assertEqual(chunks[0]['stable_rng_origin_keys'],[n*96 for n in chunks[0]['origin_positions']])
    def test_whole_price_all_tasks_and_prospective_cases_exist_before_losses(self):
        v=p.price_prefix(self.cost,self.timing)
        self.assertEqual(len(v['task_estimates']),240)
        self.assertEqual(v['initial_component_count'],69);self.assertEqual(v['maximum_component_count'],87)
        self.assertTrue(v['prefix_admitted']);self.assertTrue(v['no_losses_used'])
        self.assertEqual(v['maximum_replacements'],1);self.assertEqual(v['assessment_CPU_ceiling_separate'],1800)
        self.assertEqual(v['numerical_CPU_ceiling'],32400)
        self.assertEqual(v['contingency_factor'],1.5)
        self.assertTrue(all(len(x['extra_components']) in (12,18) for x in v['prospective_extra_scenarios']))
    def test_missing_exact_startup_cost_cannot_create_a_price(self):
        t=copy.deepcopy(self.timing);del t['startup_cpu_seconds']
        with self.assertRaisesRegex(p.PrefixError,'startup'):p.price_prefix(self.cost,t)
    def test_partial_cost_panel_rejects_before_any_selection(self):
        t=copy.deepcopy(self.timing);t['rows'].pop()
        with self.assertRaises(p.PrefixError):p.price_prefix(self.cost,t)
    def test_wrong_region_parent_preflight_is_not_substituted(self):
        t=copy.deepcopy(self.timing);t['numerical_preflight']['parents']=63
        with self.assertRaisesRegex(p.PrefixError,'coverage'):p.price_prefix(self.cost,t)
    def test_expensive_full_prefix_is_deferred_instead_of_a_fast_subset(self):
        t=copy.deepcopy(self.timing)
        for row in t['rows']:row['arithmetic_cpu_seconds']=500.
        v=p.price_prefix(self.cost,t)
        self.assertFalse(v['prefix_admitted']);self.assertFalse(v['full_prefix_admitted'])
        self.assertEqual(len(v['task_estimates']),240)
    def test_headroom_is_applied_once_in_original_task_estimates(self):
        v=p.price_prefix(self.cost,self.timing)
        t=self.prep['tasks'][0];n=v['task_estimates'][t['name']]
        windows=4*len(t['daily_origin_positions'])
        self.assertAlmostEqual(n['estimated_cpu_seconds'],1.5*(.1+.02+windows*(.05+.01)/8))
        self.assertAlmostEqual(n['estimated_wall_seconds'],n['estimated_cpu_seconds']/v['conservative_share'])
    def test_no_nomination_until_entire_deterministic_surface_complete(self):
        price=p.price_prefix(self.cost,self.timing)
        names=p.names_for(self.prep,[v['package_id'] for v in self.prep['packages']],'D',[0])
        results={n:{'metrics':{'AQL':10.}} for n in names[:-1]}
        self.assertEqual(p.manifest_state(self.prep,price,results,{})['phase'],'DETERMINISTIC_POOL')
        with self.assertRaisesRegex(p.PrefixError,'transition'):
            p.advance_decision(self.prep,self.config,price,results,{},30000,{})
    def nominations(self):
        price=p.price_prefix(self.cost,self.timing)
        names=p.names_for(self.prep,[v['package_id'] for v in self.prep['packages']],'D',[0])
        results={n:{'metrics':{'AQL':10.}} for n in names}
        key,value=p.advance_decision(self.prep,self.config,price,results,{},30000,{})
        return price,results,{key:value}
    def test_original_stable_tie_and_geometry_audit_are_preserved(self):
        _,_,d=self.nominations();rule=d['nominees']['rule'];ids={x['package_id']:x for x in self.prep['packages']}
        expected=min(k for k in ids if k!='C0')
        self.assertEqual(rule['A'],expected)
        self.assertNotIn(ids[rule['B']]['candidate_id'],{ids['C0']['candidate_id'],ids[rule['A']]['candidate_id']})
        self.assertEqual(rule['audit_order'],self.prep['frozen_audit_permutation'])
    def test_s0_requires_all_nine_matched_components(self):
        price,results,d=self.nominations()
        state=p.manifest_state(self.prep,price,results,d)
        self.assertEqual(state['phase'],'NOMINEE_SEED0');self.assertEqual(len(state['pending']),9)
        results.update({n:{'metrics':{'AQL':9.9}} for n in state['pending'][:-1]})
        self.assertEqual(p.manifest_state(self.prep,price,results,d)['phase'],'NOMINEE_SEED0')
    def extras(self,remaining):
        price,results,d=self.nominations();a,b=d['nominees']['nominees']
        for package,value in [('C0',10.),(a,9.8),(b,9.85)]:
            results.update({n:{'metrics':{'AQL':value}} for n in p.names_for(self.prep,[package],'S',[0])})
        charges={n:{'charged_CPU_seconds':1.} for n in results}
        key,value=p.advance_decision(self.prep,self.config,price,results,d,remaining,charges)
        d[key]=value;return price,results,d
    def test_two_qualifiers_have_atomic_eighteen_extras(self):
        price,results,d=self.extras(30000)
        extra=d['extra_seeds'];self.assertEqual(len(extra['required_extra_components']),18)
        self.assertEqual(extra['required_extra_components'],extra['admitted_extra_components'])
        self.assertEqual(p.manifest_state(self.prep,price,results,d)['phase'],'MATCHED_FULL_MC')
    def test_insufficient_remaining_funds_defer_the_entire_set(self):
        price,results,d=self.extras(.1);e=d['extra_seeds']
        self.assertEqual(e['admitted_extra_components'],[]);self.assertEqual(len(e['unfunded_pending']),18)
        v=p.assessment(self.prep,price,results,d)
        self.assertFalse(v['scientific_complete']);self.assertFalse(v['independent_confirmation'])
        self.assertIsNone(v['conditional_AL_proposal'])
    def test_half_margin_exploration_is_not_final_practical_gain(self):
        c=p.load_contract();v=c.confirm_gains([10.,10.,10.],[9.94,9.94,9.94])
        self.assertFalse(v['eligible_for_AL_proposal'])
    def test_equal_seed_deviation_and_mean_is_unresolved(self):
        v=p.load_contract().confirm_gains([8.,8.,8.],[7.5,8.,7.5])
        self.assertEqual(v['max_absolute_deviation'],v['mean_gain'])
        self.assertFalse(v['eligible_for_AL_proposal'])
    def test_true_matched_practical_lead_is_only_a_later_proposal(self):
        price,results,d=self.extras(30000)
        a,b=d['nominees']['nominees']
        for package,value in [('C0',10.),(a,9.7),(b,9.8)]:
            results.update({n:{'metrics':{'AQL':value}} for n in p.names_for(self.prep,[package],'S',[1,2])})
        v=p.assessment(self.prep,price,results,d)
        self.assertTrue(v['scientific_complete']);self.assertFalse(v['promotion_authorized'])
        self.assertEqual(v['disposition'],'ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED')
        self.assertEqual(v['conditional_AL_proposal']['forecast_components'],18)
        self.assertFalse(v['conditional_AL_proposal']['launched'])
    def test_incomplete_extra_set_cannot_be_assessed(self):
        price,results,d=self.extras(30000)
        with self.assertRaisesRegex(p.PrefixError,'incomplete'):p.assessment(self.prep,price,results,d)
    def test_local_worker_rejects_before_opening_scientific_files(self):
        with patch.object(p,'require_compute',side_effect=RuntimeError('not Slurm')):
            with self.assertRaisesRegex(RuntimeError,'not Slurm'):p.run_component('/absent','/absent','/absent','/absent','/absent')


class ComponentBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):_,cls.prep,_,_=fixture();cls.task=cls.prep['tasks'][0]
    def adapter(self):
        self.calls=[];self.cleanup=[]
        def predict(context,task,descriptor,beat):
            self.calls.append(descriptor);beat({'origin':descriptor['origin_positions'][0]});return descriptor,None,{'mode':task['mode']}
        return SimpleNamespace(context=lambda task:{'scaler':{'price_scale':1.,'price_mean':0}},predict=predict,
            retained_arrays=lambda context,task,desc,pred,truth,compute_loss:{'descriptor':desc,'compute_loss':compute_loss},
            pools=lambda:[{'num_threads':1}],cleanup=lambda context:self.cleanup.append(context))
    def run_loop(self,output,**overrides):
        adapter=self.adapter();budget=SimpleNamespace(check=lambda:None)
        def serialize(path,value):Path(path).write_text(json.dumps(value,sort_keys=True))
        args=dict(serializer=serialize,concatenate=lambda parts:{'parts':parts},validator=lambda *args:None,
            metric=lambda arrays:{'AQL':1.},chunks=p.original('chunks'),context_identity=p.original('context_identity'))
        args.update(overrides)
        return p.component_loop(self.prep,self.task,adapter,budget,output,**args)
    def test_complete_four_clocks_and_every_origin_are_run_in_original_order(self):
        with tempfile.TemporaryDirectory() as d:
            result=self.run_loop(d)
            expected=p.original('chunks')(self.task)
            self.assertEqual(self.calls,expected)
            self.assertEqual(result['origin_clock_windows'],4*len(self.task['daily_origin_positions']))
            self.assertTrue(all(json.loads(q.read_text())['compute_loss'] for q in Path(d).glob('checkpoints/*/predictions.npz')))
            self.assertEqual(len(self.cleanup),1)
    def test_omitted_clock_is_not_a_complete_component(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(p.PrefixError,'four-clock'):
                self.run_loop(d,chunks=lambda task:[v for v in p.original('chunks')(task) if v['clock_offset_steps']!=72])
            self.assertEqual(self.calls,[]);self.assertFalse((Path(d)/'result.json').exists())
    def test_serializer_failure_retains_prior_chunks_and_no_completion(self):
        count=0
        def fail(path,value):
            nonlocal count
            count+=1
            if count==3:raise OSError('injected disk failure')
            Path(path).write_text('retained')
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(OSError,'disk'):self.run_loop(d,serializer=fail)
            self.assertEqual(len(list(Path(d).glob('checkpoints/*/completed_evidence.json'))),2)
            self.assertFalse((Path(d)/'result.json').exists());self.assertEqual(len(self.cleanup),1)
    def test_existing_partial_chunk_is_not_an_automatic_resume(self):
        with tempfile.TemporaryDirectory() as d:
            name=p.original('chunks')(self.task)[0]['name'];(Path(d)/'checkpoints'/name).mkdir(parents=True)
            with self.assertRaises(FileExistsError):self.run_loop(d)
            self.assertFalse((Path(d)/'result.json').exists())
    def test_progress_history_is_bounded_without_losing_chunk_seals(self):
        with tempfile.TemporaryDirectory() as d:
            v=self.run_loop(d)
            self.assertLessEqual(len(v['last_events']),32)
            self.assertGreater(v['event_count'],len(v['last_events']))
            self.assertEqual(len(list(Path(d).glob('checkpoints/*/completed_evidence.json'))),v['chunk_count'])


if __name__=='__main__':unittest.main()
