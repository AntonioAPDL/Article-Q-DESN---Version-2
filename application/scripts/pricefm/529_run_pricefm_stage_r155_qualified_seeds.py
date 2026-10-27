#!/usr/bin/env python3
"""One independently admitted full matched EE seed1/2 set; no auto continuation."""
from __future__ import annotations
import argparse
import json
import math
import os
from pathlib import Path
import socket
import sys
import time
import uuid
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_seed_contract as c


def numerical_pools():
    from threadpoolctl import threadpool_info
    pools=threadpool_info();c.require(pools and all(p['num_threads']==1 for p in pools),'actual one-thread pools required')
    return pools


def seal_new(folder,arrays,result,science,execution):
    import numpy as np
    folder=Path(folder);c.require(not folder.exists(),'old seed output cannot be overwritten')
    attempt=folder.parent/(folder.name+'.attempt.'+uuid.uuid4().hex);attempt.mkdir(parents=True)
    np.savez_compressed(attempt/'predictions.npz',**arrays)
    c.immutable(attempt/'result.json',result)
    c.immutable(attempt/'completed_evidence.json',dict(schema='r155_qualified_seed_packet_v1',certified=True,
        scientific_context=science,execution=execution,artifacts={n:c.digest(attempt/n) for n in ('predictions.npz','result.json')}))
    os.rename(attempt,folder);return c.sealed_packet(folder)


def run_exact_set(names,component):
    """All-or-none dispatch order; an exception stops without retry/subsetting."""
    result={}
    for name in names:result[name]=component(name)
    return result


def revalidate_saved_component(public,task,arrays,scaler,recorded):
    """The frozen public API accepts light(shape,flat-values), not ndarrays."""
    light=public.light(arrays)
    public.validate_arrays(task,light,scaler);values=public.metrics(light)
    c.require(set(values)==set(recorded) and all(math.isclose(values[k],recorded[k],rel_tol=1e-11,abs_tol=1e-10) for k in values),
        'independent final saved-array seed metrics differ')
    return values


def run(prep,lease,gate):
    import numpy as np
    old=c.verify_pin(prep['original_preparation']);public=c.load_module('r155_qualified_seed_frozen_public',prep['public_helper']['path'],prep['public_helper']['sha256'])
    tasks={t['name']:t for t in prep['tasks']};names=lease.a['required_task_names'];qualified=gate['decision']['qualified']
    c.require(names==c.names_for(qualified),'full qualified matched set changed after claim')
    price=c.verify_pin(prep['pricing'])['scenarios']['+'.join(qualified)]
    execution=dict(source=prep['source'],authority=c.pin(lease.out/'authority.json'),scope_id=lease.a['scope_id'],
        permit_id=lease.a['permit_id'],initial_complete_assessment=gate['assessment'],
        independent_initial_analysis=gate['independent_analysis_seal'],original_scientific_source=old['source'],
        original_composite_execution=gate['source_preserving_composite_execution'],
        allowed_seed_indices=[1,2],new_seed0_components=0,new_fits=0,official_origins=0)
    c.immutable(lease.out/'initial_complete_gate.json',{k:v for k,v in gate.items() if k!='analysis'})
    c.immutable(lease.out/'full_matched_set.json',dict(required_task_names=names,qualified=qualified,execution=execution,
        components=len(names),new_seed0_components=0,no_re_nomination=True,automatic_retry=False))
    lease.note_written(lease.out/'initial_complete_gate.json');lease.note_written(lease.out/'full_matched_set.json')
    public_calls=0
    def component(name):
        nonlocal public_calls
        task=tasks[name];estimate=price['task_estimates'][name]
        c.require(task['reuse'] is None and task['mode']=='S' and task['seed_index'] in (1,2),'unadmitted seed0/reuse/fit task')
        lease.check(estimate['estimated_cpu_seconds'],estimate['estimated_wall_seconds'],refresh_output=True)
        lease.reserve(name,estimate['estimated_cpu_seconds']);started=time.monotonic();cpu0=c.cpu_seconds()
        lease.observe(dict(status='context_loading',task=name))
        context=public.numerical_context(old,task);pools=numerical_pools();parts=[]
        for descriptor in c.chunks(task):
            lease.check(estimate['estimated_max_chunk_cpu_seconds'],max(estimate['estimated_max_chunk_wall_seconds'],lease.a['maximum_atomic_wall_seconds']))
            prediction,truth,audit=public.predict(context,task,descriptor,lease.observe);public_calls+=1
            arrays=public.retained_arrays(context,task,descriptor,prediction,truth)
            public.validate_arrays(task,public.light(arrays),context['scaler'],descriptor)
            folder=lease.out/'checkpoints'/name/descriptor['name']
            seal_new(folder,arrays,dict(status='COMPLETE_MATCHED_SEED_CHUNK',task=name,descriptor=descriptor,
                sampler_audit=audit,new_fits=0,official_origins=0,numerical_threadpools=pools),
                dict(context=c.science(task,old),descriptor=descriptor),execution)
            lease.note_written(folder);parts.append(arrays)
            lease.observe(dict(status='chunk_sealed',task=name,chunk=descriptor['name']))
        arrays={k:np.ascontiguousarray(np.concatenate([part[k] for part in parts]),dtype='<i8' if k in public.INT_KEYS else '<f8')
                for k in public.array_shapes(1)}
        public.validate_arrays(task,public.light(arrays),context['scaler']);c.verify_hashes(task['parent_input_sha256'])
        metrics=public.metrics(public.light(arrays));folder=lease.out/'tasks_done'/name
        seal_new(folder,arrays,dict(status='COMPLETE_MATCHED_SEED_COMPONENT_DEVELOPMENT_ONLY',name=name,source=prep['source'],
            scientific_producer=old['source'],mode='S',seed_index=task['seed_index'],forecast_seed=task['forecast_seed'],
            scientific_identity_sha256=task['scientific_identity_sha256'],metrics=metrics,units='EUR/MWh',
            elapsed_seconds=time.monotonic()-started,measured_CPU_seconds=c.cpu_seconds()-cpu0,
            full_undiscounted_component=True,no_retained_chunks_or_old_credits=True,
            new_fits=0,posterior_updated=False,test_opened=False,official_origins=0,promotion_authorized=False,
            numerical_threadpools=numerical_pools()),c.science(task,old),execution)
        lease.note_written(folder)
        c.require(c.cpu_seconds()-cpu0<=estimate['estimated_cpu_seconds'],'component exceeded frozen full-set price; stop incomplete without retry')
        return metrics
    completed=run_exact_set(names,component)
    c.require(len(completed)==lease.a['max_new_tasks'] in (12,18)
        and public_calls==sum(len(c.chunks(tasks[n])) for n in names),'full exact matched set/component/public-call accounting differs')
    # Re-read every new component and repeat full-array/source/units metrics;
    # this is analysis of saved arrays, never another prediction or extra seed.
    for name in names:
        lease.check();folder=lease.out/'tasks_done'/name;seal=c.sealed_packet(folder)
        c.require(seal['schema']=='r155_qualified_seed_packet_v1' and seal['scientific_context']==c.science(tasks[name],old)
            and seal['execution']==execution,'new seed component lineage differs')
        with np.load(folder/'predictions.npz',allow_pickle=False) as stream:arrays={k:stream[k] for k in stream.files}
        revalidate_saved_component(public,tasks[name],arrays,c.read(tasks[name]['scaler_path']),completed[name])
    S0=gate['analysis']['matched_macro']['S'];control=[S0['C0']['AQL']]
    for seed in (1,2):control.append(sum(completed[f'EE_C0_s{s}_S_seed{seed}']['AQL'] for s in (1,2,3))/3)
    matched={}
    for p in qualified:
        values=[S0[p]['AQL']]+[sum(completed[f'EE_{p}_s{s}_S_seed{seed}']['AQL'] for s in (1,2,3))/3 for seed in (1,2)]
        matched[p]=dict(public.confirm_gains(control,values),control_AQL_by_seed=control,candidate_AQL_by_seed=values)
    c.verify_pin(gate['assessment']);c.verify_pin(prep['nominees'])
    result=dict(status='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED',execution=execution,
        required_task_names=names,new_components=len(names),new_seed0_components=0,public_chunk_calls=public_calls,
        qualified_from_unchanged_initial_S0=qualified,matched_three_seed_results=matched,
        equal_three_split_macro=True,all_new_components_independently_revalidated=True,
        AL_proposal_eligibility_only={p:v['eligible_for_AL_proposal'] for p,v in matched.items()},
        no_AL_proposal_selected_or_admitted=True,automatic_followon=False,new_fits=0,official_origins=0,
        inferential_confidence_interval=False,independent_confirmation=False,promotion_authorized=False,
        prior_R149_R150_R154_R155_source_lineage_preserved=True,old_unused_budget_credited=False)
    c.immutable(lease.out/'assessment.json',result)
    c.immutable(lease.out/'assessment_seal.json',dict(assessment=c.pin(lease.out/'assessment.json'),execution=execution))
    return result


def execute(preparation,authority,expected):
    c.require(os.sched_getaffinity(0)=={31},'seed administrative startup must enter CPU31')
    c.require(c.digest(authority)==expected,'exact independently admitted root seed authority pin required')
    prep=c.read(preparation);a=c.read(authority)
    gate=c.validate_authority(a,prep,preparation,c.source_identity(),time.time(),socket.gethostname().split('.')[0])
    for name in c.THREAD_ENV:os.environ[name]='1'
    lease=c.SeedLease(a,prep,authority)
    c.immutable(lease.out/'authority.json',a);c.immutable(lease.out/'preparation_pin.json',c.pin(preparation))
    try:result=run(prep,lease,gate)
    except BaseException as exc:
        lease.close('INCOMPLETE',dict(type=type(exc).__name__,message=str(exc),all_failed_charges_retained=True,automatic_retry=False));raise
    lease.close('COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT');return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preparation',required=True)
    parser.add_argument('--authority',required=True);parser.add_argument('--authority-sha256',required=True)
    args=parser.parse_args();print(json.dumps(execute(args.preparation,args.authority,args.authority_sha256),sort_keys=True,indent=2))
