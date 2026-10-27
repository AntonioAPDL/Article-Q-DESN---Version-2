#!/usr/bin/env python3
"""Truthful R154 prediction entry: finite EE prefix or 12-call LV diagnostic.

This entry never executes an old worker role, rebinds an old guard, fits a
posterior, changes a cached descriptor, or admits itself. All numerical imports
and calls occur after exact fresh source/resource/whole-prefix admission.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import socket
import sys
import time
import uuid

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pricefm_r154_prediction_contract import (Lease,THREAD_ENV,aliases_path,cpu_seconds,
    digest,fingerprint,immutable,load_module,pin,read,require,resolve_pin,sealed_packet,
    source_identity,validate_authority,verify_hashes,verify_pin)

ROOT=Path(__file__).resolve().parents[3]
OPS=('mean_feature','path_specific','normal_driver','rearranged_path_mean',
     'cdf_pool_clipped','cdf_pool_linear')
LEVELS=(.1,.25,.45,.5,.55,.75,.9)


def numerical_pools():
    from threadpoolctl import threadpool_info
    pools=threadpool_info()
    require(bool(pools) and all(p['num_threads']==1 for p in pools), 'actual numerical thread pool differs')
    return pools


def npz(path):
    import numpy as np
    with np.load(path,allow_pickle=False) as p:
        return {k:p[k] for k in p.files}


def seal_new(folder,arrays,result,science,execution):
    import numpy as np
    folder=Path(folder)
    require(not folder.exists(),'existing packet cannot be overwritten')
    attempt=folder.parent/(folder.name+'.attempt.'+uuid.uuid4().hex)
    attempt.mkdir(parents=True)
    np.savez_compressed(attempt/'predictions.npz',**arrays)
    immutable(attempt/'result.json',result)
    immutable(attempt/'completed_evidence.json',dict(schema='r154_prediction_packet_v1',
        certified=True,scientific_context=science,execution=execution,
        artifacts={n:digest(attempt/n) for n in ('predictions.npz','result.json')}))
    os.rename(attempt,folder)
    return read(folder/'completed_evidence.json')


def original_ee_context(task,old):
    return dict(source=old['source'],task_sha256=fingerprint(task),
        scientific_identity_sha256=task['scientific_identity_sha256'],mode=task['mode'],
        seed=task['forecast_seed'],parent_seal_sha256=task['parent_seal_sha256'],
        scaler_sha256=task['scaler_sha256'],bank=task['bank'],paths=100)


def new_packet(folder,science,execution):
    seal=sealed_packet(folder)
    require(seal.get('schema')=='r154_prediction_packet_v1'
            and seal.get('scientific_context')==science
            and seal.get('execution')==execution,'new packet lineage differs')
    return seal


def ee_chunks(task):
    chunks=[]
    for offset in task['clock_offsets_steps']:
        for start in range(0,len(task['daily_origin_positions']),8):
            positions=task['daily_origin_positions'][start:start+8]
            chunks.append(dict(name=f'clock{offset:02d}_part{start//8:03d}',clock_offset_steps=offset,
                origin_positions=positions,origin_timestamps=task['origin_timestamps'][str(offset)][start:start+8],
                stable_rng_origin_keys=[p*96+offset for p in positions]))
    return chunks


def included_equivalence(arrays,reference,rtol,atol):
    import numpy as np
    require(set(arrays)==set(reference),'paired cache array set differs')
    errors={}
    for key in arrays:
        a,b=np.asarray(arrays[key]),np.asarray(reference[key])
        require(a.shape==b.shape,'paired cache shape differs')
        if a.dtype.kind in 'iu':require(np.array_equal(a,b),'paired cache origin/clock/RNG differs')
        else:
            require(np.allclose(a,b,rtol=rtol,atol=atol,equal_nan=False),'public-helper cache equivalence failed: '+key)
            errors[key]=float(np.max(np.abs(a-b)))
    return errors


def run_ee(prep,lease):
    import numpy as np
    old=verify_pin(prep['original_preparation'])
    verify_hashes(old['source_sha256'])
    verify_hashes(old['input_sha256'])
    helper=prep['public_helper']
    public=load_module('r154_frozen_ee_public',helper['path'],helper['sha256'])
    from pricefm_r150_contract import choose_nominees,practical_margin
    tasks={t['name']:t for t in prep['tasks']}
    old_out=Path(prep['original_campaign'])
    old_completed={t['name']:t for t in prep['old_produced_D']}
    allowed_chunks={(p['task'],p['chunk']):p for p in prep['retained_checkpoint_packets']}
    execution=dict(source=prep['source'],scope_id=lease.a['scope_id'],permit_id=lease.a['permit_id'],
        authority=pin(lease.out/'authority.json'),new_fits=0,official_origins=0)
    completed={}
    calls=[]
    proof=prep['paired_cache_equivalence']
    proof_done=False
    # Revalidate the ENTIRE carried inventory before any public prediction,
    # not only the chunk/component that happens to be needed first.
    for row in prep['retained_checkpoint_packets']:
        folder=Path(row['path']).parent
        require(digest(folder/'completed_evidence.json')==row['seal_sha256'],'carried checkpoint seal changed')
        seal=sealed_packet(folder)
        task=tasks[row['task']]
        descriptor=next(d for d in ee_chunks(task) if d['name']==row['chunk'])
        require(seal['identity']==dict(context=original_ee_context(task,old),descriptor=descriptor),
                'carried checkpoint mathematical identity differs')
    for row in prep['old_produced_D']:
        folder=old_out/'tasks_done'/row['name']
        require(digest(folder/'completed_evidence.json')==row['seal_sha256'],'carried full D seal changed')
        sealed_packet(folder,original_ee_context(tasks[row['name']],old))
    for row in prep['old_reused_D']:public.validate_reuse(tasks[row['name']])
    immutable(lease.out/'carried_inventory_preflight.json',dict(status='PASS',strict_full_D=20,
        produced_D=14,exact_control_reuses=6,partial_checkpoint_payloads=225,
        before_first_prediction=True,old_ledgers_untouched=True,source=prep['source']))
    lease.note_written(lease.out/'carried_inventory_preflight.json')

    def component(task):
        nonlocal proof_done
        name=task['name']
        science=original_ee_context(task,old)
        if name in completed:return completed[name]
        if task['reuse']:
            # Public mathematical reuse validator; it does not execute a worker.
            value=public.validate_reuse(task)
            completed[name]=value
            return value
        if name in old_completed:
            folder=old_out/'tasks_done'/name
            require(digest(folder/'completed_evidence.json')==old_completed[name]['seal_sha256'],'original full D seal differs')
            sealed_packet(folder,science)
            arrays=public.read_npz(folder/'predictions.npz')
            public.validate_arrays(task,arrays,read(task['scaler_path']))
            value=public.metrics(arrays)
            recorded=read(folder/'result.json')['metrics']
            require(all(np.isclose(value[k],recorded[k],rtol=1e-11,atol=1e-10) for k in value),'original full D metrics differ')
            completed[name]=value
            return value
        require(task['seed_index']==0 and task['mode'] in ('D','S'),'extra seed or invalid kind forbidden')
        require(len(calls)<64,'new component count exceeded')
        if task['mode']=='D':require(name in prep['remaining_D_names'],'unexpected new D task')
        estimate=prep['task_estimates'][name]
        lease.check(estimate['estimated_cpu_seconds'],estimate['estimated_wall_seconds'],refresh_output=True)
        lease.reserve(name,estimate['estimated_cpu_seconds'])
        started,cpu0=time.monotonic(),cpu_seconds()
        lease.observe(dict(status='context_loading',task=name))
        context=public.numerical_context(old,task)
        pools=numerical_pools()
        parts=[]
        for descriptor in ee_chunks(task):
            lease.check(estimate['estimated_max_chunk_cpu_seconds'],
                max(estimate['estimated_max_chunk_wall_seconds'],lease.a['maximum_atomic_wall_seconds']))
            key=(name,descriptor['name'])
            identity=dict(context=science,descriptor=descriptor)
            old_chunk=allowed_chunks.get(key)
            must_prove=name==proof['task'] and descriptor['name']==proof['chunk']
            if old_chunk is not None:
                folder=Path(old_chunk['path']).parent
                require(digest(folder/'completed_evidence.json')==old_chunk['seal_sha256'],'retained chunk seal changed')
                seal=sealed_packet(folder)
                require(seal.get('identity')==identity,'retained exact chunk context differs')
                arrays=npz(folder/'predictions.npz')
                public.validate_arrays(task,public.light(arrays),context['scaler'],descriptor)
                if not must_prove:
                    parts.append(arrays)
                    continue
                reference=arrays
            else:reference=None
            prediction,truth,audit=public.predict(context,task,descriptor,lease.observe)
            arrays=public.retained_arrays(context,task,descriptor,prediction,truth)
            public.validate_arrays(task,public.light(arrays),context['scaler'],descriptor)
            if must_prove:
                require(reference is not None and not proof_done,'included cache proof lost exact identity')
                errors=included_equivalence(arrays,reference,proof['deterministic_rtol'],proof['deterministic_atol'])
                immutable(lease.out/'paired_cache_equivalence.json',dict(status='PASS',task=name,
                    descriptor=descriptor,original_seal=proof['original_seal'],maximum_absolute_errors=errors,
                    included_component_budget=True,extra_component=False,new_fits=0,execution=execution))
                proof_done=True
            folder=lease.out/'checkpoints'/name/descriptor['name']
            result=dict(status='COMPLETE_CHUNK',task=name,descriptor=descriptor,sampler_audit=audit,
                new_fits=0,official_origins=0,numerical_threadpools=pools)
            seal_new(folder,arrays,result,identity,execution)
            lease.note_written(folder)
            new_packet(folder,identity,execution)
            parts.append(arrays)
            lease.observe(dict(status='chunk_sealed',task=name,chunk=descriptor['name']))
        arrays={k:np.ascontiguousarray(np.concatenate([p[k] for p in parts]),
            dtype='<i8' if k in public.INT_KEYS else '<f8') for k in public.array_shapes(1)}
        public.validate_arrays(task,public.light(arrays),context['scaler'])
        verify_hashes(task['parent_input_sha256'])
        value=public.metrics(public.light(arrays))
        result=dict(status='COMPLETE_COMPONENT_DEVELOPMENT_ONLY',name=name,source=prep['source'],
            scientific_producer=old['source'],scientific_identity_sha256=task['scientific_identity_sha256'],
            mode=task['mode'],seed_index=0,metrics=value,units='EUR/MWh',
            origin_clock_windows=len(arrays['origin_positions']),new_fits=0,posterior_updated=False,
            official_origins=0,test_opened=False,promotion_authorized=False,
            elapsed_seconds=time.monotonic()-started,measured_CPU_seconds=cpu_seconds()-cpu0,
            numerical_threadpools=numerical_pools())
        folder=lease.out/'tasks_done'/name
        seal_new(folder,arrays,result,science,execution)
        lease.note_written(folder)
        new_packet(folder,science,execution)
        calls.append(name)
        completed[name]=value
        return value

    # Loss-blind paired public-helper proof runs on its included canonical D
    # component first; this changes no seed, cohort, descriptor or component cap.
    component(tasks[proof['task']])
    # Exact full deterministic barrier, no ranking from the first completed subset.
    for task in prep['tasks']:
        if task['mode']=='D':component(task)
    require(proof_done,'included cached public-helper equivalence proof incomplete')
    losses={p['package_id']:sum(component(tasks[f"EE_{p['package_id']}_s{s}_D_seed0"])['AQL']
             for s in (1,2,3))/3 for p in prep['packages']}
    nominees=choose_nominees(prep['packages'],losses,'C0','C5',prep['audit_key'])
    immutable(lease.out/'nominees.json',dict(nominees,full_D_complete=78,full_D_mean_AQL=losses,
        execution=execution,selected_from_official=False))
    wanted=['C0',nominees['A'],nominees['B']]
    s0={p:sum(component(tasks[f'EE_{p}_s{s}_S_seed0'])['AQL'] for s in (1,2,3))/3 for p in wanted}
    gain={p:s0['C0']-s0[p] for p in wanted if p!='C0'}
    margin=practical_margin(s0['C0'])
    qualified=[p for p in wanted if p!='C0' and gain[p]>=.5*margin]
    result=dict(status='COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED' if qualified else 'COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER',
        full_D_components=78,old_complete_D=20,new_D=58,new_S0=sum('_S_' in n for n in calls),
        new_component_names=calls,nominees=nominees,matched_S0_AQL=s0,matched_S0_gains=gain,
        practical_margin=margin,extra_seed_qualified=qualified,extra_seed_admitted=False,
        conditional_extra_components=0 if not qualified else 6*(1+len(qualified)),
        new_fits=0,official_origins=0,promotion_authorized=False,confirmatory_claim=False,
        algorithmic_three_seed_stability_established=False,execution=execution)
    immutable(lease.out/'assessment.json',result)
    immutable(lease.out/'assessment_seal.json',dict(assessment=pin(lease.out/'assessment.json'),execution=execution))
    return result


def lv_aliases(prep,authority):
    if authority.get('read_aliases') is None:return {}
    receipt=verify_pin(authority['read_aliases'])
    require(receipt['preparation']==authority['preparation'],'read alias preparation differs')
    aliases=receipt['read_aliases']
    require(set(aliases)==set(prep['input_files_sha256']),'read alias member set differs')
    return aliases


def lv_metric(truth,prediction,common_metrics):
    import numpy as np
    truth,prediction=np.asarray(truth),np.asarray(prediction)
    if truth.ndim==1:
        truth,prediction=truth[None,:],prediction[None,:,:]
    require(truth.ndim==2 and prediction.shape==truth.shape+(7,)
            and np.isfinite(truth).all() and np.isfinite(prediction).all(), 'diagnostic subset shapes/finite values differ')
    # Frozen r126.loss deliberately requires H96. Subset diagnostics use the
    # same equations directly and never pad/reweight a short subset to H96.
    error=truth[...,None]-prediction
    value=dict(AQL=float(np.mean(error*(np.asarray(LEVELS)-(error<0)))),
        median_MAE=float(np.mean(np.abs(truth-prediction[...,3]))),
        coverage_80=float(np.mean((truth>=prediction[...,0])&(truth<=prediction[...,-1]))),
        width_80=float(np.mean(prediction[...,-1]-prediction[...,0])),
        exceedance=[float(np.mean(truth>prediction[...,i])) for i in range(7)])
    if truth.shape[1]==96:
        frozen=common_metrics(truth,prediction)
        require(all(np.allclose(value[k],frozen[k],rtol=1e-12,atol=1e-10) for k in frozen),
                'independent full H96 metrics differ from frozen public helper')
    value.update(lower_miss_q10=float(np.mean(truth<prediction[...,0])),
        upper_miss_q90=float(np.mean(truth>prediction[...,-1])),
        empirical_CDF_q10=float(np.mean(truth<=prediction[...,0])),
        empirical_CDF_q50=float(np.mean(truth<=prediction[...,3])),
        empirical_CDF_q90=float(np.mean(truth<=prediction[...,-1])),
        crossing_rate=float(np.mean(np.diff(prediction,axis=-1)<0)))
    return value


def metric_mean(values):
    import numpy as np
    value=np.mean(np.asarray(values,dtype=float),axis=0)
    return float(value) if value.ndim==0 else value.tolist()


def lv_time_diagnostics(truth,prediction,anchors,common_metrics):
    """Physical UTC = fixed-market anchor -1 hour + h*15min; no DST."""
    import numpy as np
    physical=np.asarray([round(dt.datetime.fromisoformat(str(s)).timestamp())-3600 for s in anchors])
    hour=((physical[:,None]+np.arange(96)[None,:]*900)//3600)%24
    result=dict(clock='physical_UTC_from_fixed_market_anchor_minus_one_hour_no_DST',
        by_horizon_quarter={str(i+1):lv_metric(truth[:,i*24:(i+1)*24],prediction[:,i*24:(i+1)*24],common_metrics)
            for i in range(4)},by_physical_hour={},by_origin_chronological_block={})
    for h in range(24):
        mask=hour==h
        result['by_physical_hour'][str(h)]=dict(observations=int(mask.sum()),
            **lv_metric(truth[mask],prediction[mask],common_metrics))
    for i,idx in enumerate(np.array_split(np.arange(len(anchors)),3)):
        result['by_origin_chronological_block'][str(i+1)]=dict(origins=len(idx),
            first_market_anchor=str(anchors[idx[0]]),last_market_anchor=str(anchors[idx[-1]]),
            **lv_metric(truth[idx],prediction[idx],common_metrics))
    return result


def run_lv(prep,lease):
    import numpy as np
    aliases=lv_aliases(prep,lease.a)
    for filename,expected in prep['input_files_sha256'].items():resolve_pin(filename,expected,aliases)
    core_path=resolve_pin(prep['public_core']['path'],prep['public_core']['sha256'],aliases)
    dependency=Path(prep['dependency'])
    if aliases:
        # The byte mirror retains complete absolute-relative directory layout.
        sample=next(p for p in aliases if p.startswith(str(dependency)+'/application/scripts/pricefm/'))
        suffix=str(Path(sample).relative_to(dependency))
        dependency=Path(aliases[sample])
        for _ in Path(suffix).parts:dependency=dependency.parent
    core=load_module('r154_frozen_lv_core',core_path,prep['public_core']['sha256'])
    runtime=core.dependencies(dependency)
    from pricefm_r126_replay import forecast
    from pricefm_r127_contract import shifted_windows,window_identity,common_metrics
    numerical_pools()
    raw=core.load_arrays(runtime,resolve_pin(prep['bank']['path'],prep['bank']['sha256'],aliases))
    require(len(raw.response)==940,'LV training-only bank differs')
    groups={g['task']['split']:g for g in prep['training_groups']}
    execution=dict(source=prep['source'],scope_id=lease.a['scope_id'],permit_id=lease.a['permit_id'],
                   authority=pin(lease.out/'authority.json'),read_aliases=lease.a.get('read_aliases'))
    call_CPU=lease.a.get('LV_call_CPU')
    require(isinstance(call_CPU,(int,float)) and call_CPU>0
            and 12*call_CPU<=lease.a['full_prefix_CPU'],'all12 LV calls need a current CPU price')
    records=[]
    for call in prep['call_manifest']:
        lease.check(call_CPU,lease.a['maximum_atomic_wall_seconds'],refresh_output=True)
        lease.reserve(call['id'],call_CPU)
        start,cpu0=time.monotonic(),cpu_seconds()
        group=groups[call['split']]
        task=group['task']
        spec=prep['candidate']['spec']
        require(task['candidate_id']==prep['candidate']['candidate_id'] and task['tau0']==prep['candidate']['tau0'],
                'training candidate/scale differs')
        cell=runtime.internal_splits(len(raw.response))[call['split']-1]
        scaled,scaler=runtime.standardize_from_training_origins(raw,cell['train'])
        require(fingerprint(scaler)==fingerprint(group['scaler']),'training scaler differs')
        idx=np.asarray(call['origin_indices'],dtype=int)
        stable=np.asarray(call['original_origin_clock_positions'],dtype=int)
        require(np.array_equal(stable,idx*96+call['clock_offset_steps']),'LV origin/clock RNG keys differ')
        require(len(idx)==12 and set(idx).issubset(set(cell['validation'])),'exact training validation support differs')
        shifted=shifted_windows(scaled,idx,call['clock_offset_steps'],cell['validation'])
        raw_shifted=shifted_windows(raw,idx,call['clock_offset_steps'],cell['validation'])
        window_identity(shifted,dt.datetime.fromisoformat(str(raw.anchors[cell['validation'][0]])),
            dt.datetime.fromisoformat(str(raw.anchors[cell['validation'][-1]]))+dt.timedelta(days=1))
        def fit_dir(name):
            filename=str(Path(prep['original_campaign'])/'tasks_done'/name/'fit/beta_mean.bin')
            return aliases_path(filename,aliases).parent
        normal=runtime.load_normal_fit(fit_dir(task['rhs_name']))
        quantiles={float(q):runtime.load_quantile_fit(fit_dir(name)) for q,name in task['al_names'].items()}
        require(sorted(quantiles)==list(LEVELS),'seven original AL parents required')
        for name,parent in group['parents'].items():
            old_result=str(Path(prep['original_campaign'])/'tasks_done'/name/'result.json')
            require(read(aliases_path(old_result,aliases)).get('certified') is True,'cached parent computational certification failed')
        # Exactly one original public forecast call per frozen descriptor. The
        # first call's price observation is included; no separate replay call.
        values,audit=forecast(runtime,shifted,spec,normal,quantiles,stable,call['call_seed'],observe=lease.observe)
        require(set(values)==set(OPS)|{'truth'} and audit['paths']==500,'six same-call operators/500 paths differ')
        require(np.allclose(raw_shifted.response,values['truth']*scaler['price_scale']+scaler['price_mean'],
            rtol=1e-12,atol=1e-10),'raw EUR truth reconstruction differs')
        values={k:np.ascontiguousarray(v*scaler['price_scale']+scaler['price_mean'],dtype='<f8') for k,v in values.items()}
        values['truth']=np.ascontiguousarray(raw_shifted.response,dtype='<f8')
        require(values['truth'].shape==(12,96),'truth shape differs')
        for name in OPS:
            require(values[name].shape==(12,96,7) and np.isfinite(values[name]).all(),'nonfinite/operator shape defect')
            if name not in ('mean_feature','path_specific'):
                require(np.all(np.diff(values[name],axis=-1)>=-1e-10),'ordered operator quantiles differ')
        metrics={name:lv_metric(values['truth'],values[name],common_metrics) for name in OPS}
        temporal={name:lv_time_diagnostics(values['truth'],values[name],shifted.anchors,common_metrics) for name in OPS}
        # A second independent arithmetic reconstruction uses the exact returned
        # primary arrays, not another forecast or another seed/call.
        error=values['truth'][...,None]-values['cdf_pool_clipped']
        direct_AQL=float(np.mean(error*(np.asarray(LEVELS)-(error<0))))
        require(np.isclose(direct_AQL,metrics['cdf_pool_clipped']['AQL'],rtol=1e-11,atol=1e-10),'primary metric reconstruction differs')
        result=dict(status='COMPLETE_TRAINING_DIAGNOSTIC_CALL',id=call['id'],split=call['split'],
            clock_offset_steps=call['clock_offset_steps'],origin_clock_pairs=12,metrics=metrics,
            temporal_diagnostics=temporal,
            sampler_audit=audit,elapsed_seconds=time.monotonic()-start,measured_CPU_seconds=cpu_seconds()-cpu0,
            numerical_threadpools=numerical_pools(),source=prep['source'],new_fits=0,official_origins=0,
            paired_primary_metric_reconstruction=True,no_extra_forecast_call=True)
        arrays=dict(values,origin_positions=idx,stable_rng_origin_keys=stable,
            anchors=np.asarray(shifted.anchors,dtype='U40'))
        folder=lease.out/'tasks_done'/call['id']
        seal_new(folder,arrays,result,call,execution)
        lease.note_written(folder)
        new_packet(folder,call,execution)
        records.append(result)
        lease.observe(dict(status='LV_call_complete',id=call['id'],completed_calls=len(records)))
        require(result['measured_CPU_seconds']<=call_CPU,
                'included LV call exceeded its frozen whole-prefix price; stop incomplete without another forecast')
    require(len(records)==12 and sum(r['origin_clock_pairs'] for r in records)==144,'incomplete LV full diagnostic')
    folded={}
    for operator in OPS:
        folded[operator]={str(split):{key:metric_mean([r['metrics'][operator][key] for r in records if r['split']==split])
            for key in records[0]['metrics'][operator]} for split in (1,2,3)}
    means={operator:{key:metric_mean([folded[operator][str(s)][key] for s in (1,2,3)])
           for key in records[0]['metrics'][operator]} for operator in OPS}
    flags={operator:{str(s):dict(coverage80_error_gt5pp=abs(folded[operator][str(s)]['coverage_80']-.8)>.05,
        q10_CDF_error_gt5pp=abs(folded[operator][str(s)]['empirical_CDF_q10']-.1)>.05,
        q90_CDF_error_gt5pp=abs(folded[operator][str(s)]['empirical_CDF_q90']-.9)>.05,
        median_CDF_error_gt5pp=abs(folded[operator][str(s)]['empirical_CDF_q50']-.5)>.05)
        for s in (1,2,3)} for operator in OPS}
    result=dict(status='COMPLETE_TRAINING_DIAGNOSTIC_EXPOSED_NOT_PROMOTED',calls=12,
        origin_clock_pairs=144,paths=500,folds=folded,equal_three_split_macro=means,
        primary_operator='cdf_pool_clipped',new_fits=0,official_origins=0,
        candidate_nomination_authorized=False,promotion_authorized=False,confirmatory_claim=False,
        execution=execution,diagnostic_thresholds=prep['frozen_manifest']['diagnostic_flags'],
        diagnostic_flags_by_fold=flags,flags_are_not_statistical_significance=True)
    immutable(lease.out/'assessment.json',result)
    immutable(lease.out/'assessment_seal.json',dict(assessment=pin(lease.out/'assessment.json'),execution=execution))
    return result


def execute(preparation,authority,authority_sha):
    require(digest(authority)==authority_sha,'authority pin differs')
    prep=read(preparation)
    require(prep['schema']=='r154_prediction_preparation_v1','unknown preparation')
    verify_hashes(prep['execution_source_sha256'])
    identity=source_identity(ROOT)
    a=validate_authority(read(authority),prep,preparation,identity,time.time(),socket.gethostname().split('.')[0])
    for name in THREAD_ENV:os.environ[name]='1'
    lease=Lease(a,prep,authority)
    immutable(lease.out/'authority.json',read(authority))
    immutable(lease.out/'preparation_pin.json',pin(preparation))
    try:
        value=run_ee(prep,lease) if prep['study']=='EE' else run_lv(prep,lease)
    except BaseException as exc:
        lease.close('INCOMPLETE',dict(type=type(exc).__name__,message=str(exc),
            failed_charges_retained=True,retry_authorized=False))
        raise
    lease.close('COMPLETE_INITIAL_PREFIX' if prep['study']=='EE' else 'COMPLETE_DIAGNOSTIC')
    return value


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preparation')
    parser.add_argument('--authority')
    parser.add_argument('--authority-sha256')
    parser.add_argument('--check-peers',action='store_true',help='Read-only actual process/thread classifier proof; no claim or numerical imports')
    parser.add_argument('--peer-census')
    parser.add_argument('--admin-rules')
    parser.add_argument('--cpu',type=int)
    args=parser.parse_args()
    if args.check_peers:
        from pricefm_r154_prediction_contract import all_processes,peer_conflicts,physical_siblings
        require(args.peer_census and args.admin_rules and args.cpu in range(32),'explicit census/rules/physical CPU required')
        identity=source_identity(ROOT)
        processes=all_processes()
        conflicts=peer_conflicts(args.cpu,read(args.peer_census),{os.getpid()},processes,read(args.admin_rules))
        value=dict(status='PASS' if not conflicts else 'RESOURCE_DEFERRED',source=identity,
            entry=pin(__file__),contract=pin(Path(__file__).with_name('pricefm_r154_prediction_contract.py')),
            peer_census=pin(args.peer_census),admin_rules=pin(args.admin_rules),cpu=args.cpu,
            physical_sibling_cpus=sorted(physical_siblings(args.cpu)),
            processes_read=len(processes),threads_read=sum(len(p.get('threads',[])) for p in processes),
            unreadable_processes_ignored=0,unknown_numerical_conflicts=conflicts,
            unrelated_raw_arguments_retained=False,claims_created=0,new_fits=0,new_forecasts=0)
        print(json.dumps(value,sort_keys=True,indent=2))
        if conflicts:sys.exit(2)
        return
    require(args.preparation and args.authority and args.authority_sha256,'exact preparation/authority pin required')
    print(json.dumps(execute(args.preparation,args.authority,args.authority_sha256),sort_keys=True,indent=2))


if __name__=='__main__':main()
