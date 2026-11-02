#!/usr/bin/python3.11
"""Pure generated metadata/mathematics tests; no production or fit reads."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('mq_typed_v2',ROOT/'scripts/forecast_transition_typed_v2.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def fixture():
    identity=dict(source_commit='a'*40,source_tree='b'*40,source_manifest_sha256='c'*64,
        posterior_target_sha256='d'*64,input_manifest_sha256='e'*64,task_manifest_sha256='f'*64,
        task_id='generated',rng_namespace='generated-stream',outer_conditioning='parameters_and_observed_origin_reservoir_state')
    q=[dict(horizon=1,probability=p,quantile=v) for p,v in zip((.1,.5,.9),(-1.,0.,1.))]
    split=[dict(horizon=1,probability=p,split_stream_absolute_difference=0.,split_stream_relative_difference=0.) for p in (.1,.5,.9)]
    contract=dict(schema_version='mq_streaming_cdf_certificate_contract_v1',
        method='heldout_conditional_CDF_empirical_Bernstein_alpha_spending',
        conditioning='one_fixed_original_parameter_draw_and_observed_origin',
        validation_values='iid_future_path_conditional_CDF_not_particle_filter',candidates_from_training_paths_only=True,
        rng_namespace='generated-stream',draw_id='d1',origin_id='o1',training_path_range=[1,65536],
        validation_path_range=[65537,327680],look_sizes=[65536,131072,262144],total_alpha=.05,
        alpha_per_look=[.05/3]*3,absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,training_split_diagnostic=split)
    receipt=dict(schema_version='integrated_quantile_compact_receipt_v2',method='mq_heldout_conditional_cdf_streaming_v1',
        identity=identity,stream_contract=contract,draw_id='d1',origin_id='o1',rng_namespace='generated-stream',
        look_index=1,validation_count=65536,validation_first_path_id=65537,validation_last_path_id=131072,
        validation_chain_sha256='0'*64,cdf_mean=[0.,.104,.496,.504,.896,1.],cdf_M2=[0.]*6)
    request=dict(schema_version='mq_generated_workflow_request_v2',execution_scope='generated_fixture_only',
        production_authorized=False,identity=identity,expected_member_keys=['generated-key'],
        model_id='generated',probabilities=[.1,.5,.9],horizons=[1])
    wire=dict(schema_version='mq_typed_numerical_wire_v2',execution_scope='generated_fixture_only',production_authorized=False,
        identity=identity,expected_member_keys=['generated-key'],block_file_sha256='1'*64,
        members=[dict(member_key='generated-key',model_id='generated',draw_id='d1',origin_id='o1',quantiles=q,receipt=receipt)])
    return wire,request

class TypedTests(unittest.TestCase):
    def test_exact_radius_and_scope(self):
        wire,request=fixture();result=m.validate_wire(wire,request)[0]
        import math
        self.assertAlmostEqual(result['maximum_radius'],7*math.log(24/(.05/3))/(3*65535),places=16)
        self.assertEqual(result['endpoint_count'],6)

    def test_mutations_rejected(self):
        def field(path,value):
            def mutate(w,r):
                x=w
                for key in path[:-1]:x=x[key]
                x[path[-1]]=value
            return mutate
        mutations=[
            field(['production_authorized'],True),field(['execution_scope'],'production'),
            field(['members',0,'model_id'],'unplanned-model'),
            field(['identity','source_commit'],'bad'),field(['expected_member_keys'],['other']),
            field(['members',0,'draw_id'],'other'),field(['members',0,'receipt','method'],'dkw'),
            field(['members',0,'receipt','look_index'],4),field(['members',0,'receipt','look_index'],True),
            field(['members',0,'receipt','validation_count'],65535),
            field(['members',0,'receipt','validation_first_path_id'],65536),
            field(['members',0,'receipt','validation_chain_sha256'],'bad'),
            field(['members',0,'receipt','cdf_mean'],[.5]*6),
            field(['members',0,'receipt','cdf_M2'],[-1.]*6),
            field(['members',0,'receipt','cdf_M2'],[65536.]*6),
            field(['members',0,'receipt','stream_contract','look_sizes'],[65535,131072,262144]),
            field(['members',0,'receipt','stream_contract','absolute_quantile_tolerance'],.02),
            field(['members',0,'receipt','stream_contract','total_alpha'],.1),
            field(['members',0,'receipt','stream_contract','alpha_per_look'],[.05]*3),
            field(['members',0,'receipt','stream_contract','source_identity_authenticated'],True),
            field(['members',0,'receipt','stream_contract','validation_values'],'particle_filter'),
            field(['members',0,'receipt','stream_contract','training_split_diagnostic',0,'split_stream_absolute_difference'],.006),
            field(['members',0,'quantiles',0,'probability'],.2),
            field(['members',0,'quantiles',0,'quantile'],2.),
            field(['members',0,'receipt','cdf_mean'],[float('nan')]*6)]
        # The split OR gate requires both components to fail.
        def split(w,r):
            w['members'][0]['receipt']['stream_contract']['training_split_diagnostic'][0].update(
                split_stream_absolute_difference=.006,split_stream_relative_difference=.006)
        mutations[-4]=split
        for mutate in mutations:
            w,r=copy.deepcopy(fixture());mutate(w,r)
            with self.subTest(mutation=repr(mutate)):
                with self.assertRaises((m.GateError,KeyError,TypeError,ValueError)):m.validate_wire(w,r)

    def test_or_gate_and_no_status_bypass(self):
        w,r=fixture();w['members'][0]['receipt']['stream_contract']['training_split_diagnostic'][0].update(
            split_stream_absolute_difference=.006,split_stream_relative_difference=.004)
        m.validate_wire(w,r)
        w['members'][0]['receipt']['status']='PASS';w['members'][0]['receipt']['cdf_mean']=[.5]*6
        with self.assertRaises(m.GateError):m.validate_wire(w,r)

    def test_all_420_endpoints(self):
        w,r=fixture();member=w['members'][0];receipt=member['receipt']
        p=[.05,.10,.25,.50,.75,.90,.95];q=[-3.,-2.,-1.,0.,1.,2.,3.]
        r.update(probabilities=p,horizons=list(range(1,31)))
        member['quantiles']=[dict(horizon=h,probability=a,quantile=v) for h in range(1,31) for a,v in zip(p,q)]
        receipt['stream_contract']['training_split_diagnostic']=[dict(horizon=h,probability=a,
            split_stream_absolute_difference=0.,split_stream_relative_difference=0.) for h in range(1,31) for a in p]
        def cdf(y):
            k=sum(v<=y for v in q)
            if k==0:return 0.
            if k==7:return 1.
            return p[k-1]+(p[k]-p[k-1])*(y-q[k-1])/(q[k]-q[k-1])
        means=[]
        for row in member['quantiles']:
            v=row['quantile'];delta=max(.01,.01*abs(v));means.extend((cdf(v-delta),cdf(v+delta)))
        receipt['cdf_mean']=means;receipt['cdf_M2']=[0.]*420
        proof=m.validate_wire(w,r)[0]
        import math
        self.assertEqual(proof['endpoint_count'],420)
        self.assertAlmostEqual(proof['maximum_radius'],7*math.log(1680/(.05/3))/(3*65535),places=16)
        receipt['cdf_mean'][-1]=.94
        with self.assertRaises(m.GateError):m.validate_wire(w,r)

    def test_json_guards(self):
        with tempfile.TemporaryDirectory(prefix='mqv2_metadata_') as directory:
            p=Path(directory)/'new.json'
            for content in ('{"a":1,"a":2}','{"a":NaN}','{"a":Infinity}'):
                p.write_text(content)
                with self.assertRaises(m.GateError):m.read_json(p)
            p.write_text('{}')
            with self.assertRaises(m.GateError):m.read_json(p,cap=1)

if __name__=='__main__':unittest.main()
