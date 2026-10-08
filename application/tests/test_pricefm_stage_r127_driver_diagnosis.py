from dataclasses import replace
import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'application/scripts/pricefm'
sys.path.insert(0, str(HERE))
import pricefm_r123_runtime as RT
from pricefm_r126_contract import read, market_ns
from pricefm_r126_replay import forecast
from pricefm_r125_cdf import forecast_diagnostic
from pricefm_r124_covariance import GaussianSampler
from pricefm_r127_contract import shifted_windows, window_identity, variance_terms, common_metrics
from pricefm_r127_forecast import replay


@pytest.fixture(scope='module')
def toy():
    rng = np.random.default_rng(89); n = 4; lag = 3120
    price = rng.normal(size=lag + n * 96); x = rng.normal(size=(lag + n * 96, 3))
    arrays = RT.BASE.ExplicitArrays(np.array([price[i*96:i*96+lag] for i in range(n)]),
        np.array([x[i*96:i*96+lag] for i in range(n)]),
        np.array([x[i*96+lag:i*96+lag+96] for i in range(n)]),
        np.array([price[i*96+lag:i*96+lag+96] for i in range(n)]),
        np.array([str(t) for t in pd.date_range('2024-01-01', periods=n, freq='D', tz='UTC')]),
        ('load', 'solar', 'wind'), ())
    spec = RT.normalize_spec(dict(region='BG', feature_policy='target_only', calendar='none',
        readout='pure_all_layers', m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    mean = np.arange(8) * .01; cov = np.eye(8) * .001
    normal = dict(beta_mean=mean, beta_cov=cov, omega_shape=5., omega_rate=.5)
    qs = {float(q): dict(beta_mean=mean + q / 10, beta_cov=cov) for q in (.1,.25,.45,.5,.55,.75,.9)}
    one = RT.subset_arrays(arrays, [1])
    values, audit = replay(RT, one, spec, qs, [12], 4, normal)
    return arrays, spec, normal, qs, values, audit


@pytest.mark.parametrize('offset', [0,24,48,72])
def test_shifted_window_matches_single_timeline(toy, offset):
    a = toy[0]; shifted = shifted_windows(a, [1], offset, [1,2,3]); d=offset
    np.testing.assert_array_equal(shifted.price_history[0], np.r_[a.price_history[1], a.response[1]][d:d+3120])
    np.testing.assert_array_equal(shifted.response[0], np.r_[a.response[1], a.response[2]][d:d+96])
    np.testing.assert_array_equal(shifted.exog_future[0], np.r_[a.exog_future[1], a.exog_future[2]][d:d+96])
    assert market_ns(shifted.anchors)[0] == market_ns(a.anchors)[1] + d*15*60*10**9


@pytest.mark.parametrize('indices,offset', [([3],24),([0],24),([1,1],0),([1],1)])
def test_shift_adapter_fails_closed(toy, indices, offset):
    with pytest.raises(ValueError): shifted_windows(toy[0], indices, offset, [1,2,3])


def test_nonadjacent_window_is_rejected(toy):
    a=toy[0]; changed=a.anchors.copy(); changed[2]='2024-02-01T00:00:00+00:00'
    with pytest.raises(ValueError): shifted_windows(replace(a, anchors=changed), [1],24,[1,2,3])


def test_response_is_held_out_and_cutoff_contained(toy):
    a=shifted_windows(toy[0],[1],72,[1,2,3])
    window_identity(a,pd.Timestamp('2024-01-02',tz='UTC'),pd.Timestamp('2024-01-05',tz='UTC'))
    with pytest.raises(ValueError): window_identity(a,pd.Timestamp('2024-01-03',tz='UTC'),pd.Timestamp('2024-01-05',tz='UTC'))
    with pytest.raises(ValueError): window_identity(a,pd.Timestamp('2024-01-02',tz='UTC'),pd.Timestamp('2024-01-03',tz='UTC'))


def test_exact_causal_and_oracle_control_identity(toy):
    a,s,n,q,v,_=toy; one=RT.subset_arrays(a,[1])
    old,_=forecast(RT,one,s,n,q,[12],4)
    np.testing.assert_array_equal(v['stochastic'],old['cdf_pool_clipped'])
    old,_=forecast_diagnostic(RT,one,s,n,q,[12],4,GaussianSampler())
    np.testing.assert_array_equal(v['oracle'],old['oracle_cdf_clipped'])


def test_oracle_does_not_require_normal_and_chunk_seed_stable(toy):
    a,s,n,q,v,_=toy
    result,_=replay(RT,RT.subset_arrays(a,[1]),s,q,[12],4,oracle_only=True)
    np.testing.assert_array_equal(result['oracle'],v['oracle'])
    assert set(result)=={'truth','oracle'}


def test_causal_future_poison_and_oracle_prefix_isolation(toy):
    a,s,n,q,v,_=toy; one=RT.subset_arrays(a,[1]); y=one.response.copy(); y[:,40:]+=1e5
    out,_=replay(RT,replace(one,response=y),s,q,[12],4,n)
    for mode in ('stochastic','parameter_only','mean_driver'):
        np.testing.assert_array_equal(out[mode],v[mode])
    np.testing.assert_array_equal(out['oracle'][:,:41],v['oracle'][:,:41])
    assert not np.array_equal(out['oracle'][:,41:],v['oracle'][:,41:])


def test_first_step_common_features_and_independent_banks(toy):
    v=toy[4]
    for mode in ('stochastic','parameter_only','mean_driver'):
        np.testing.assert_allclose(v[mode][:,0],v['oracle'][:,0],atol=1e-12,rtol=1e-12)
    assert np.any(v['state_variance'][:,:,0]>0)
    assert not np.any(v['state_variance'][:,:,2])


def test_current_exog_not_one_step_lagged(toy):
    a,s,*_=toy
    u=RT.BASE.explicit_input(a,s,[1],0,np.empty((1,0)))
    np.testing.assert_array_equal(u[0,s['m_y']:s['m_y']+3],a.exog_future[1,0])


def test_mean_driver_is_not_mean_stochastic_forecast(toy):
    v=toy[4]
    assert np.all(v['driver_sd'][:,:,2]==0)
    assert np.any(abs(v['driver_mean'][:,:,2]-v['driver_mean'][:,:,0])>1e-6)
    assert np.any(abs(v['parameter_only']-v['stochastic'])>1e-6)


def test_cached_reuse_matches_without_overwriting_parent(toy):
    a,s,n,q,v,_=toy; cache={k:v[k].copy() for k in ('oracle','stochastic')}
    out,_=replay(RT,RT.subset_arrays(a,[1]),s,q,[12],4,n,cached=cache)
    for k in cache: np.testing.assert_array_equal(out[k],cache[k])
    cache['oracle'][:,0]+=1
    with pytest.raises(RuntimeError): replay(RT,RT.subset_arrays(a,[1]),s,q,[12],4,n,cached=cache)


def test_variance_decomposition_matches_density_identity():
    z=np.array([[1.,2.],[2.,4.],[3.,1.]]); mu=np.array([.3,.5]); cov=np.array([[2.,.4],[.4,1.]])
    a,b,total=variance_terms(z,mu,cov)
    second=np.mean([r@cov@r+(mu@r)**2 for r in z])-np.mean(z@mu)**2
    assert total==pytest.approx(second)
    assert total==pytest.approx(a+b)


def test_affine_two_stage_cancellation():
    x=np.arange(90.,dtype=float); first=(x-72)/15
    np.testing.assert_allclose((first-first[:40].mean())/first[:40].std(),
        (x-x[:40].mean())/x[:40].std(),rtol=1e-13,atol=1e-13)
    assert np.max(abs(first.astype('float32').astype(float)-first))<3e-7


def test_teacher_forcing_between_origins_is_not_continuation(toy):
    a,s,n,q,_,_=toy
    both,_=replay(RT,RT.subset_arrays(a,[1,2]),s,q,[12,99],4,n)
    single,_=replay(RT,RT.subset_arrays(a,[2]),s,q,[99],4,n)
    for key in ('stochastic','parameter_only','mean_driver','oracle'):
        np.testing.assert_array_equal(both[key][1:],single[key])


def test_protocol_and_combined_schedule_no_refits_or_promotion():
    p=read(ROOT/'application/config/pricefm_stage_r127_driver_diagnosis_protocol_20261008.json')
    for k in ('new_fitting_authorized','new_screening_authorized','selection_uses_test',
              'promotion_authorized','registry_mutation_authorized','article_mutation_authorized'):
        assert p[k] is False
    assert p['workers']==15 and p['posterior_paths']==500
    sp=importlib.util.spec_from_file_location('r127',HERE/'450_run_pricefm_stage_r127_driver_diagnosis.py')
    mod=importlib.util.module_from_spec(sp); sp.loader.exec_module(mod)
    op=read(ROOT/'application/config/pricefm_stage_r126_matched_comparison_protocol_20261007.json')
    jobs=[dict(split=i,origin_positions=list(map(int,np.linspace(0,n-1,12))),complete_origin_count=n,seed=i)
          for i,n in enumerate((125,135,174),1)]
    tasks=mod.task_schedule(jobs,p,op)
    assert len(tasks)==82 and sum(t['smoke'] for t in tasks)==15
    assert len(set(t['name'] for t in tasks))==len(tasks)
    for fold,count in enumerate((120,123,122),1):
        positions=[v for t in tasks if t['kind']=='official' and t['fold']==fold for v in t['positions']]
        assert sorted(positions)==list(range(count))
    assert sum(len(t['positions']) for t in tasks if t['kind']=='internal')==144
    with pytest.raises(ValueError): mod.cpu_pool(16)


def test_metrics_units_and_seven_levels(toy):
    v=toy[4]; m=common_metrics(v['truth'],v['stochastic'])
    assert len(m['exceedance'])==7 and 0<=m['coverage_80']<=1
    assert m['width_80']>=0


@pytest.mark.parametrize('actual', [[0,0,1],[0,2],[0,1,3]])
def test_closeout_rejects_incomplete_cohort(actual):
    from pricefm_r127_report import complete_positions
    with pytest.raises(ValueError): complete_positions([{'positions':np.array(actual)}],[0,1,2])


def test_full_diagnostic_closeout_and_pdf(tmp_path):
    from pricefm_r126_contract import write, seal, verified
    from pricefm_r127_report import closeout
    out=tmp_path/'new'; parent=tmp_path/'old'; protocol=read(ROOT/'application/config/pricefm_stage_r127_driver_diagnosis_protocol_20261008.json')
    jobs=[dict(split=s, origin_positions=list(map(int,np.linspace(0,n-1,12))),complete_origin_count=n,seed=s)
          for s,n in enumerate((125,135,174),1)]
    seals=[]; refs=[]
    def block(positions):
        n=len(positions); truth=np.ones((n,96)); pred=np.zeros((n,96,7))
        return dict(positions=np.array(positions),anchors_ns=np.arange(n),truth=truth+2e-5,oracle=pred+.5,
            stochastic=pred,parameter_only=pred+.1,mean_driver=pred+.2,
            driver_mean=np.zeros((n,96,3)),driver_sd=np.ones((n,96,3)),
            state_variance=np.zeros((n,96,3,2)),state_oracle_rmse=np.zeros((n,96,3,2)),
            saturated_fraction=np.zeros((n,96,3,2)),near_linear_fraction=np.ones((n,96,3,2)),
            median_variance_terms=np.ones((n,96,3,3)),variance_lead_mask=np.arange(96)%24==0)
    def task(name,values,**task):
        folder=out/'tasks_done'/name; folder.mkdir(parents=True)
        np.savez_compressed(folder/'predictions.npz',**values); seal(folder,{})
        write(out/'tasks'/f'{name}.json',dict(name=name,**task))
    for fold,count in enumerate((120,123,122),1):
        value=block(range(count)); task(f'official{fold}',value,kind='official',fold=fold)
        p=parent/f'official/fold={fold}'; p.mkdir(parents=True)
        np.savez_compressed(p/'predictions.npz',truth=value['truth'],anchors_ns=value['anchors_ns'],cdf_pool_clipped=value['stochastic'])
        seal(p,{})
        refs.append(dict(fold=fold,method='new_recursive_QDESN',AQL=common_metrics(np.ones_like(value['truth']),value['stochastic'])['AQL']))
    for job in jobs:
        for offset in (0,24,48,72):
            pos=job['origin_positions'] if not offset else list(map(int,np.linspace(0,job['complete_origin_count']-2,12)))
            task(f'internal{job["split"]}_{offset}',block(pos),kind='internal',split=job['split'],offset=offset,seed=job['seed'])
    for seed in protocol['mc_repeat_seeds']:
        task(f'mc{seed}',block(protocol['mc_repeat_positions']),kind='mc',split=3,offset=0,seed=seed)
    ref=tmp_path/'reference.csv'; pd.DataFrame(refs).to_csv(ref,index=False)
    prep=dict(protocol=protocol,official_protocol=dict(test_origin_counts=[120,123,122]),jobs=jobs,
        parent=str(parent),reference=str(ref),source={'head':'test','branch':'work/pricefm-r127-test'})
    exact_truth=lambda fold,anchors,prep:np.ones((len(anchors),96))
    corrected=tmp_path/'report_only';corrected.mkdir()
    decision=closeout(out,prep,report=corrected/'report',terminal=corrected/'terminal.json',truth_reader=exact_truth)
    assert decision['new_fits']==0 and decision['authority_unchanged']
    assert verified(corrected/'report')['official_origins']==365
    assert (corrected/'report/pricefm_r127_driver_diagnosis.pdf').read_bytes().startswith(b'%PDF')
    assert decision['score_matches_frozen_reference']
    assert decision['stored_truth_roundtrip_error_by_fold']['1']==pytest.approx(2e-5)
    assert not (out/'terminal.json').exists()
    assert closeout(out,prep,report=corrected/'report',terminal=corrected/'terminal.json',truth_reader=exact_truth)==decision


def test_exact_raw_truth_clock_and_hash(tmp_path,monkeypatch):
    from pricefm_r127_report import official_raw_truth
    from pricefm_r126_contract import digest
    import pricefm_r126_fullfold as full
    data=tmp_path/'data';(data/'raw').mkdir(parents=True)
    source=data/'raw/FINAL.csv';source.write_text('test-only source\n')
    frame=pd.DataFrame({'BG-price':np.arange(192,dtype=float)+.123456789},
        index=pd.date_range('2024-01-01',periods=192,freq='15min',tz='UTC'))
    monkeypatch.setattr(full,'raw_frame',lambda path:frame)
    prep=dict(parent=str(data/'campaigns/parent'),protocol={'parent_final_sha256':digest(source)})
    anchors=market_ns(frame.index[[0,96]])
    actual=official_raw_truth(1,anchors,prep)
    np.testing.assert_array_equal(actual[0],frame['BG-price'].iloc[:96])
    with pytest.raises(ValueError): official_raw_truth(1,anchors+1,prep)
    prep['protocol']['parent_final_sha256']='wrong'
    with pytest.raises(RuntimeError): official_raw_truth(1,anchors,prep)
