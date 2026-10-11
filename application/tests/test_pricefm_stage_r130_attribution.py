from pathlib import Path
import os
import sys

import numpy as np
import pandas as pd
import pytest

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'application/scripts/pricefm'
sys.path.insert(0,str(HERE))
from pricefm_r130_attribution import (validate_protocol,validation_grid,check_support,
    task_schedule,complete_cell,summarize_cell,plot_report,FORBIDDEN,CONTROLS)
import json


@pytest.fixture
def protocol():
    return json.loads((ROOT/'application/config/pricefm_stage_r130_forecast_error_attribution_20261010.json').read_text())


@pytest.mark.parametrize('key',FORBIDDEN)
def test_forbidden_scope_fails_closed(protocol,key):
    protocol[key]=True
    with pytest.raises(ValueError):validate_protocol(protocol)


@pytest.mark.parametrize('key,value',[('paths',100),('maximum_workers',16),('origin_offsets_steps',[0]),
    ('controls',['oracle']),('oracle_diagnostic_only',False),('horizon_steps',95)])
def test_geometry_and_oracle_scope_are_fixed(protocol,key,value):
    protocol[key]=value
    with pytest.raises(ValueError):validate_protocol(protocol)


def test_valid_protocol_and_schedule(protocol):
    validate_protocol(protocol)
    cells=[dict(region=r,fold=f,grid=validation_grid('2024-09-01','2025-01-01',protocol))
        for r in protocol['regions'] for f in protocol['folds']]
    tasks=task_schedule(cells,protocol)
    assert len(tasks)==120 and sum(t['smoke'] for t in tasks)==24
    assert sum(len(t['positions']) for t in tasks)==288
    assert len({t['name'] for t in tasks})==120
    for c in cells:
        same=[t for t in tasks if (t['region'],t['fold'])==(c['region'],c['fold'])]
        assert sorted(i for t in same for i in t['bank_indices'])==list(range(48))


@pytest.mark.parametrize('start,end',[('2024-09-01','2025-01-01'),('2025-01-01','2025-05-01'),('2025-05-01','2025-09-01')])
def test_shifted_response_never_enters_test(protocol,start,end):
    grid=validation_grid(start,end,protocol)
    anchors=pd.to_datetime([r['anchor'] for r in grid],utc=True)
    assert len(anchors)==48 and len(set(anchors))==48
    assert np.all(anchors>=pd.Timestamp(start,tz='UTC'))
    assert np.all(anchors+pd.Timedelta(days=1)<pd.Timestamp(end,tz='UTC'))
    assert {t.hour for t in anchors}=={0,6,12,18}


@pytest.mark.parametrize('anchors',[['2024-08-31'],['2024-12-31T06:00:00Z'],['2024-09-01','2024-09-01']])
def test_training_overlap_future_test_and_duplicates_rejected(anchors):
    with pytest.raises(ValueError):check_support(anchors,'2024-09-01','2025-01-01')


def test_inadequate_validation_span_rejected(protocol):
    with pytest.raises(ValueError):validation_grid('2024-09-01','2024-09-05',protocol)


def test_bank_identity_and_missing_cohort(protocol):
    grid=validation_grid('2024-09-01','2025-01-01',protocol)
    packet=dict(bank_indices=np.arange(48),positions=np.array([r['position'] for r in grid]),
        anchors_ns=pd.DatetimeIndex(pd.to_datetime([r['anchor'] for r in grid],utc=True)).as_unit('ns').asi8,
        truth=np.ones((48,96)))
    complete_cell([packet],grid)
    packet['positions'][0]+=1
    with pytest.raises(ValueError):complete_cell([packet],grid)


def test_repeated_packet_rejected(protocol):
    grid=validation_grid('2024-09-01','2025-01-01',protocol)
    packet=dict(bank_indices=np.arange(48),positions=np.array([r['position'] for r in grid]),
        anchors_ns=pd.DatetimeIndex(pd.to_datetime([r['anchor'] for r in grid],utc=True)).as_unit('ns').asi8,
        truth=np.ones((48,96)))
    with pytest.raises(ValueError):complete_cell([packet,packet],grid)


def test_metrics_and_multiclock_leads(protocol):
    from importlib import import_module
    dependency=Path(os.environ['PRICEFM_R130_DEPENDENCY'])
    sys.path.insert(0,str(dependency/'application/scripts/pricefm'))
    from pricefm_r127_contract import common_metrics
    cell=dict(region='HR',fold=1,grid=validation_grid('2024-09-01','2025-01-01',protocol))
    values=dict(truth=np.ones((48,96)),**{k:np.zeros((48,96,7)) for k in CONTROLS})
    rows,leads=summarize_cell(values,cell,common_metrics)
    assert len(rows)==16 and len(leads)==4*4*96
    assert all(r['AQL']==pytest.approx(.5) for r in rows)
    assert {r['target_clock_step'] for r in leads}==set(range(96))


def test_documented_linear_receiver_mean_identity():
    rng=np.random.default_rng(3);z=rng.normal(size=(500,8));beta=rng.normal(size=(500,8))
    paired=np.mean(np.einsum('sp,sp->s',z,beta))
    mean_feature=beta.mean(axis=0)@z.mean(axis=0)
    covariance=np.sum(np.mean((beta-beta.mean(axis=0))*(z-z.mean(axis=0)),axis=0))
    assert paired-mean_feature==pytest.approx(covariance,abs=1e-14)


def test_pdf_can_render_all_pages(tmp_path,protocol):
    official=pd.DataFrame([dict(region=r,operator='cdf_pool_clipped',fold=f,AQL=8.,
        qdesn_AQL=9.,pricefm_AQL=7.,operational_pricefm_AQL=6.) for r in ('HR','DK_1') for f in (1,2,3)])
    validation=pd.DataFrame([dict(region=r,fold=f,offset_steps=o,operator=m,AQL=8.,coverage_80=.75)
        for r in ('HR','DK_1') for f in (1,2,3) for o in (0,24,48,72) for m in CONTROLS])
    leads=pd.DataFrame([dict(region=r,offset_steps=o,operator=m,lead_step=h,AQL=1+h/96)
        for r in ('HR','DK_1') for o in (0,24,48,72) for m in CONTROLS for h in range(1,97)])
    traces={(r,f):[(.5,pd.DataFrame(dict(iteration=np.arange(10),elbo=np.arange(10),sigma=np.ones(10))))]
        for r in ('HR','DK_1') for f in (1,2,3)}
    controls={(r,f):dict(truth=np.ones((1,96)),stochastic=np.zeros((1,96,7)),oracle=np.zeros((1,96,7)),
        driver_mean=np.zeros((1,96,3))) for r in ('HR','DK_1') for f in (1,2,3)}
    pdf=tmp_path/'diagnosis.pdf';plot_report(pdf,official,validation,leads,controls,traces)
    assert pdf.stat().st_size>20000 and pdf.read_bytes().startswith(b'%PDF-')


def test_declared_sources_and_zero_fits(protocol):
    assert protocol['parent_head']=='04792b20e42349514f918f05917cdbc70bed5a77'
    script=(HERE/'460_run_pricefm_stage_r130_attribution.py').read_text()
    assert 'new_fits=0' in script and 'test_opened=False' in script
    assert 'exalStaticLDVB(' not in script and 'run_r(' not in script
    assert 'git push' not in script and 'git merge' not in script


def test_automatic_closeout_and_sealed_repeat(tmp_path,protocol):
    sys.path.insert(0,str(Path(os.environ['PRICEFM_R130_DEPENDENCY'])/'application/scripts/pricefm'))
    from pricefm_r126_contract import read,write,seal,verified
    from pricefm_r127_contract import common_metrics
    from pricefm_r130_attribution import closeout
    out=tmp_path/'new';parent=tmp_path/'parent';cells=[];tasks=[];parent_tasks=[];official=[]
    for region in ('HR','DK_1'):
        for fold in (1,2,3):
            grid=validation_grid('2024-09-01','2025-01-01',protocol)
            folder=tmp_path/f'fit_{region}_{fold}';folder.mkdir()
            pd.DataFrame(dict(iter=[1,2],elbo=[-3.,-2.],sigma=[1.,1.])).to_csv(folder/'vb_trace.csv',index=False)
            cell=dict(region=region,fold=fold,grid=grid,quantile_dirs={'0.5':str(folder)},original_median=str(folder))
            cells.append(cell);name=f'{region}_{fold}';tasks.append(dict(name=name,region=region,fold=fold))
            packet=dict(bank_indices=np.arange(48),positions=np.array([r['position'] for r in grid]),
                anchors_ns=pd.DatetimeIndex(pd.to_datetime([r['anchor'] for r in grid],utc=True)).as_unit('ns').asi8,
                truth=np.ones((48,96)),**{k:np.zeros((48,96,7)) for k in CONTROLS},
                driver_mean=np.zeros((48,96,3)),driver_sd=np.zeros((48,96,3)),
                state_oracle_rmse=np.zeros((48,96,3,2)),saturated_fraction=np.zeros((48,96,3,2)),
                near_linear_fraction=np.ones((48,96,3,2)))
            packet['oracle'][:]=.5
            target=out/'tasks_done'/name;target.mkdir(parents=True)
            np.savez_compressed(target/'predictions.npz',**packet);seal(target,{})
            target=parent/'tasks_done'/name;target.mkdir(parents=True)
            v=dict(truth=np.ones((1,96)),positions=np.array([0]),
                anchors_ns=pd.date_range('2025-01-01',periods=1,tz='UTC').as_unit('ns').asi8,
                **{k:np.zeros((1,96,7)) for k in ('cdf_pool_clipped','normal_driver','mean_feature','path_specific')})
            np.savez_compressed(target/'predictions.npz',**v);seal(target,{})
            parent_tasks.append(dict(name=name,kind='forecast',region=region,fold=fold))
            official.extend(dict(region=region,fold=fold,operator=k,AQL=.5,qdesn_AQL=.6,
                pricefm_AQL=.4,operational_pricefm_AQL=.3) for k in ('cdf_pool_clipped','normal_driver','mean_feature','path_specific'))
    (parent/'closeout').mkdir();pd.DataFrame(official).to_csv(parent/'closeout/fold_comparison.csv',index=False)
    prep=dict(cells=cells,tasks=tasks,parent_tasks=parent_tasks,parent_out=str(parent),source={'head':'test'},
        official_protocol=dict(test_origin_counts=[1,1,1],test_intervals_market=[['2025-01-01','2025-01-02']]*3))
    result=closeout(out,prep,verified,read,write,seal,common_metrics)
    assert result['new_fits']==0 and result['diagnostic_origins']==288
    assert all(f['oracle_reduction_pct']==pytest.approx(50) for f in result['findings'])
    verified(out/'closeout')
    assert closeout(out,prep,verified,read,write,seal,common_metrics)==result
    (out/'closeout/validation_metrics.csv').write_text('modified')
    with pytest.raises(RuntimeError):closeout(out,prep,verified,read,write,seal,common_metrics)
