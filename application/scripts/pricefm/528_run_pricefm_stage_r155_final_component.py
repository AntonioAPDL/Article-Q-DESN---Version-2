#!/usr/bin/env python3
"""Fresh final completion: reconstruct full barrier; predict only remaining B3."""
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
from pricefm_r155_final_contract import (Lease,THREAD_ENV,cpu_seconds,digest,immutable,
    load_module,pin,read,require,sealed_packet,source_identity,validate_authority,verify_hashes,verify_pin)
from pricefm_r155_final_inventory import A,B,MISSING,chunks,science,validate_row
ROOT=Path(__file__).resolve().parents[3]


def numerical_pools():
    from threadpoolctl import threadpool_info
    pools=threadpool_info()
    require(bool(pools) and all(p['num_threads']==1 for p in pools),'actual numerical thread pool differs')
    return pools


def npz(path):
    import numpy as np
    with np.load(path,allow_pickle=False) as p:return {k:p[k] for k in p.files}


def seal_new(folder,arrays,result,context,execution):
    import numpy as np
    folder=Path(folder)
    require(not folder.exists(),'existing packet cannot be overwritten')
    attempt=folder.parent/(folder.name+'.attempt.'+uuid.uuid4().hex)
    attempt.mkdir(parents=True)
    np.savez_compressed(attempt/'predictions.npz',**arrays)
    immutable(attempt/'result.json',result)
    immutable(attempt/'completed_evidence.json',dict(schema='r155_final_component_packet_v1',
        certified=True,scientific_context=context,execution=execution,
        artifacts={n:digest(attempt/n) for n in ('predictions.npz','result.json')}))
    os.rename(attempt,folder)
    return sealed_packet(folder)


def compare_metrics(calculated,recorded,name):
    require(set(calculated)==set(recorded) and all(math.isclose(calculated[k],recorded[k],
        rel_tol=1e-11,abs_tol=1e-10) for k in calculated),'saved metric reconstruction differs: '+name)


def included_equivalence(arrays,reference,rtol,atol):
    import numpy as np
    require(set(arrays)==set(reference),'paired cache array set differs')
    errors={}
    for key in arrays:
        a,b=np.asarray(arrays[key]),np.asarray(reference[key])
        require(a.shape==b.shape,'paired cache shape differs')
        if a.dtype.kind in 'iu':require(np.array_equal(a,b),'paired cache origin/clock/RNG differs')
        else:
            require(np.allclose(a,b,rtol=rtol,atol=atol,equal_nan=False),'public-helper equivalence failed: '+key)
            errors[key]=float(np.max(np.abs(a-b)))
    return errors


def run(prep,lease):
    import numpy as np
    old=verify_pin(prep['original_preparation'])
    r154=verify_pin(prep['R154_preparation'])
    r155=verify_pin(prep['R155_preparation'])
    inventory=verify_pin(prep['composite_inventory'])
    require(inventory['previous_paid_scope']==prep['previous_paid_scope'],'paid lineage differs')
    verify_hashes(old['source_sha256']);verify_hashes(old['input_sha256'])
    helper=prep['public_helper']
    public=load_module('r155_exact_frozen_public',helper['path'],helper['sha256'])
    tasks={t['name']:t for t in prep['tasks']}
    require(tasks=={t['name']:t for t in r154['tasks']},'frozen task universe differs')
    require(tasks=={t['name']:t for t in r155['tasks']},'spent R155 task universe differs')
    require(prep['remaining_component_names']==MISSING,'exact remaining one-component boundary differs')
    for row in inventory['rows']:
        validate_row(row,tasks,old,inventory)
    for reuse in inventory['reuses']:
        require(pin(Path(reuse['packet'])/'completed_evidence.json')==reuse['seal'],'exact reuse seal differs')
        public.validate_reuse(tasks[reuse['task']])
    completed={}
    reconstruction=[]
    components={r['task']:r for r in inventory['rows'] if r['kind'].endswith('component')}

    def carry(task):
        name=task['name']
        if name in completed:return completed[name]
        if task['reuse']:
            arrays=public.imported_arrays(task)
            recorded=public.validate_reuse(task)
            lineage='R149_exact_source_preserving_reuse'
        else:
            row=components[name]
            arrays=public.read_npz(Path(row['folder'])/'predictions.npz')
            recorded=read(Path(row['folder'])/'result.json')['metrics']
            lineage=row['kind']
        public.validate_arrays(task,arrays,read(task['scaler_path']))
        value=public.metrics(arrays)
        compare_metrics(value,recorded,name)
        completed[name]=value
        reconstruction.append(dict(task=name,lineage=lineage,metrics=value,
            scientific_identity_sha256=task['scientific_identity_sha256']))
        lease.check()
        return value

    for task in prep['tasks']:
        if task['mode']=='D':carry(task)
    require(sum('_D_' in n for n in completed)==78,'complete 78D reconstruction barrier absent')
    losses={p['package_id']:sum(completed[f"EE_{p['package_id']}_s{s}_D_seed0"]['AQL']
        for s in (1,2,3))/3 for p in prep['packages']}
    nominees=public.choose_nominees(prep['packages'],losses,'C0','C5',prep['audit_key'])
    fixed=verify_pin(inventory['nominees'])
    require(all(nominees[k]==fixed[k] for k in nominees) and (nominees['A'],nominees['B'])==(A,B),
            'full D nominee replay differs from frozen A/B')
    require(all(math.isclose(v,fixed['full_D_mean_AQL'][k],rel_tol=1e-11,abs_tol=1e-10)
            for k,v in losses.items()),'frozen full D loss surface differs')
    wanted=['C0',A,B]
    for p in wanted:
        for s in (1,2,3):
            name=f'EE_{p}_s{s}_S_seed0'
            if name not in MISSING:carry(tasks[name])
    execution=dict(source=prep['source'],scope_id=lease.a['scope_id'],permit_id=lease.a['permit_id'],
        authority=pin(lease.out/'authority.json'),composite_inventory=prep['composite_inventory'],
        original_scientific_source=old['source'],R154_execution=inventory['R154_execution'],R155_execution=inventory['R155_execution'],
        new_fits=0,official_origins=0)
    immutable(lease.out/'carried_reconstruction.json',dict(status='PASS',full_D_components=78,
        carried_S0_components=8,components=reconstruction,nominees=nominees,
        full_D_mean_AQL=losses,all_inventory_bytes_and_contexts_verified=True,
        before_first_prediction=True,execution=execution))
    lease.note_written(lease.out/'carried_reconstruction.json')
    partial={ (r['task'],Path(r['folder']).name):r for r in inventory['rows']
        if r['kind']=='R155_checkpoint' and r['task'] in MISSING}
    require(len(partial)==15,'retained partial chunk count differs')
    # Validate every retained partial array before the first public prediction.
    for (name,chunk),row in partial.items():
        descriptor=next(d for d in chunks(tasks[name]) if d['name']==chunk)
        public.validate_arrays(tasks[name],public.read_npz(Path(row['folder'])/'predictions.npz'),
            read(tasks[name]['scaler_path']),descriptor)
    proof=prep['paired_cache_equivalence'];proof_done=False;calls=[];new_chunks=0;public_calls=0
    for name in MISSING:
        task=tasks[name]
        require(task['mode']=='S' and task['seed_index']==0 and len(calls)<1,'new task scope expansion forbidden')
        estimate=prep['task_estimates'][name]
        lease.check(estimate['estimated_cpu_seconds'],estimate['estimated_wall_seconds'],refresh_output=True)
        lease.reserve(name,estimate['estimated_cpu_seconds'])
        start,cpu0=time.monotonic(),cpu_seconds()
        lease.observe(dict(status='context_loading',task=name))
        context_started,context_cpu0=time.monotonic(),cpu_seconds()
        context=public.numerical_context(old,task);pools=numerical_pools();parts=[];prediction_timings=[]
        context_timing=dict(CPU_seconds=cpu_seconds()-context_cpu0,wall_seconds=time.monotonic()-context_started)
        immutable(lease.out/'context_readiness.json',dict(status='CONTEXT_READY',task=name,scientific_context=science(task,old),execution=execution,numerical_threadpools=pools,new_fits=0,new_forecasts_yet=0,source=prep['source']))
        lease.note_written(lease.out/'context_readiness.json')
        for descriptor in chunks(task):
            lease.check(estimate['estimated_max_chunk_cpu_seconds'],
                max(estimate['estimated_max_chunk_wall_seconds'],lease.a['maximum_atomic_wall_seconds']))
            retained=partial.get((name,descriptor['name']))
            must_prove=(name,descriptor['name'])==(proof['task'],proof['chunk'])
            reference=npz(Path(retained['folder'])/'predictions.npz') if retained else None
            if reference is not None and not must_prove:
                parts.append(reference);continue
            predict_started,predict_cpu0=time.monotonic(),cpu_seconds()
            prediction,truth,audit=public.predict(context,task,descriptor,lease.observe)
            prediction_timings.append(dict(chunk=descriptor['name'],origin_clock_windows=len(descriptor['origin_positions']),
                included_retained_proof=must_prove,CPU_seconds=cpu_seconds()-predict_cpu0,
                wall_seconds=time.monotonic()-predict_started))
            public_calls+=1
            arrays=public.retained_arrays(context,task,descriptor,prediction,truth)
            public.validate_arrays(task,public.light(arrays),context['scaler'],descriptor)
            if must_prove:
                require(reference is not None and not proof_done,'included proof identity differs')
                errors=included_equivalence(arrays,reference,proof['deterministic_rtol'],proof['deterministic_atol'])
                immutable(lease.out/'paired_cache_equivalence.json',dict(status='PASS',task=name,
                    descriptor=descriptor,retained_seal=retained['seal'],maximum_absolute_errors=errors,
                    included_in_full_component_budget=True,extra_component=False,
                    original_arrays_retained=True,execution=execution))
                lease.note_written(lease.out/'paired_cache_equivalence.json')
                proof_done=True;parts.append(reference);continue
            require(retained is None,'retained chunk must never be overwritten')
            folder=lease.out/'checkpoints'/name/descriptor['name']
            seal_new(folder,arrays,dict(status='COMPLETE_CHUNK',task=name,descriptor=descriptor,
                sampler_audit=audit,new_fits=0,official_origins=0,numerical_threadpools=pools),
                dict(context=science(task,old),descriptor=descriptor),execution)
            new_chunks+=1;lease.note_written(folder);parts.append(arrays)
            lease.observe(dict(status='chunk_sealed',task=name,chunk=descriptor['name']))
        arrays={k:np.ascontiguousarray(np.concatenate([p[k] for p in parts]),
            dtype='<i8' if k in public.INT_KEYS else '<f8') for k in public.array_shapes(1)}
        public.validate_arrays(task,public.light(arrays),context['scaler'])
        verify_hashes(task['parent_input_sha256'])
        value=public.metrics(public.light(arrays))
        folder=lease.out/'tasks_done'/name
        seal_new(folder,arrays,dict(status='COMPLETE_COMPONENT_DEVELOPMENT_ONLY',name=name,
            source=prep['source'],scientific_producer=old['source'],mode='S',seed_index=0,
            scientific_identity_sha256=task['scientific_identity_sha256'],metrics=value,units='EUR/MWh',
            carried_chunks=sum((name,d['name']) in partial for d in chunks(task)),
            full_component_origin_clock_windows=len(arrays['origin_positions']),
            predicted_origin_clock_windows=sum(t['origin_clock_windows'] for t in prediction_timings),
            public_chunk_calls=len(prediction_timings),new_chunk_seals=73,included_equivalence_origin_clock_windows=8,
            context_timing=context_timing,public_prediction_timings=prediction_timings,
            timing_scope='Actual included context and public calls; no extra timing task. Per-call CPU includes callbacks; component timing includes retained reads and validation before final packet serialization.',
            elapsed_seconds=time.monotonic()-start,measured_CPU_seconds=cpu_seconds()-cpu0,
            new_fits=0,posterior_updated=False,official_origins=0,test_opened=False,
            promotion_authorized=False,numerical_threadpools=numerical_pools()),science(task,old),execution)
        lease.note_written(folder);completed[name]=value;calls.append(name)
    require(calls==MISSING and proof_done and new_chunks==73 and public_calls==74,
            'exact completion/proof/component accounting differs')
    s0={p:sum(completed[f'EE_{p}_s{s}_S_seed0']['AQL'] for s in (1,2,3))/3 for p in wanted}
    gain={p:s0['C0']-s0[p] for p in (A,B)}
    margin=public.practical_margin(s0['C0'])
    qualified=[p for p in (A,B) if gain[p]>=.5*margin]
    result=dict(status='COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED' if qualified else 'COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER',
        full_D_components=78,full_S0_components=9,original_complete_D=20,R154_carried_D=58,R154_carried_S0=4,R155_carried_S0=1,
        original_control_S0_reuses=3,carried_S0_components=8,new_D=0,new_S0=1,new_component_names=calls,
        carried_partial_chunks=15,new_chunks=73,included_equivalence_public_calls=1,
        total_public_chunk_calls=public_calls,nominees=nominees,matched_S0_AQL=s0,
        matched_S0_gains=gain,practical_margin=margin,extra_seed_qualified=qualified,
        extra_seed_admitted=False,conditional_extra_components=0 if not qualified else 6*(1+len(qualified)),
        new_fits=0,official_origins=0,promotion_authorized=False,confirmatory_claim=False,
        algorithmic_three_seed_stability_established=False,previous_paid_scope=prep['previous_paid_scope'],
        old_unused_budget_credited=False,execution=execution)
    immutable(lease.out/'assessment.json',result)
    immutable(lease.out/'assessment_seal.json',dict(assessment=pin(lease.out/'assessment.json'),execution=execution))
    return result


def execute(preparation,authority,authority_sha):
    require(digest(authority)==authority_sha,'authority pin differs')
    prep=read(preparation)
    require(prep.get('schema')=='r155_final_preparation_v1','unknown completion preparation')
    verify_hashes(prep['execution_source_sha256'])
    a=validate_authority(read(authority),prep,preparation,source_identity(ROOT),time.time(),socket.gethostname().split('.')[0])
    for name in THREAD_ENV:os.environ[name]='1'
    lease=Lease(a,prep,authority)
    immutable(lease.out/'authority.json',read(authority))
    immutable(lease.out/'preparation_pin.json',pin(preparation))
    try:value=run(prep,lease)
    except BaseException as exc:
        lease.close('INCOMPLETE',dict(type=type(exc).__name__,message=str(exc),
            failed_charges_retained=True,retry_authorized=False));raise
    lease.close('COMPLETE_INITIAL_PREFIX')
    return value


def inspect(authority,authority_sha):
    """Read only actual source/owned-process/unit/packet metadata; no NumPy."""
    from pricefm_r155_final_contract import process_identity
    import subprocess
    require(digest(authority)==authority_sha,'inspect authority pin differs')
    a=read(authority);identity=source_identity(ROOT)
    require(a['schema']=='r155_final_authority_v1' and a['status']=='ADMITTED' and a['source']==identity,
            'inspect must use the actual new admitted source')
    prep=verify_pin(a['preparation']);verify_hashes(prep['execution_source_sha256']);out=Path(a['output_dir'])
    names=('claim.json','guardian.json','payload_identity.json','context_readiness.json',
           'carried_reconstruction.json','paired_cache_equivalence.json','assessment.json',
           'assessment_seal.json','exit_receipt.json','supervisor_exit_receipt.json')
    records={name:(dict(pin=pin(out/name),value=read(out/name)) if (out/name).exists() else None) for name in names}
    expected=[]
    if records['guardian.json']:
        expected += [records['guardian.json']['value'][k] for k in ('process','payload')]
    elif records['claim.json']:expected.append(records['claim.json']['value']['process'])
    processes=[]
    for old in expected:
        live=process_identity(old['pid']);masks=[]
        if live is not None:
            try:
                for thread in (Path('/proc')/str(live['pid'])/'task').iterdir():
                    try:masks.append(dict(tid=int(thread.name),cpus=sorted(os.sched_getaffinity(int(thread.name)))))
                    except ProcessLookupError:continue
            except FileNotFoundError:pass
        same=live is not None and all(live[k]==old[k] for k in ('pid','start_ticks','boot_id'))
        processes.append(dict(expected=old,live=live,all_thread_masks=masks,exact_lifetime_live=same,
            unavailable_fields=[] if live is not None else ['live_process','all_thread_masks']))
    keys=('Id','LoadState','MainPID','ExecMainPID','InvocationID','ActiveState','SubState','Restart','NRestarts','KillMode',
          'Result','ExecMainStatus','RemainAfterExit','WorkingDirectory')
    raw=subprocess.check_output(['systemctl','--user','show',a['unit'],*['--property='+k for k in keys]],text=True,timeout=10)
    unit=dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
    seals=sorted((out/'checkpoints').glob('*/*/completed_evidence.json')) if out.exists() else []
    first=dict(pin=pin(seals[0]),value=read(seals[0])) if seals else None
    return dict(schema='r155_final_actual_caller_inspection_v1',status='READ_ONLY_ACTUAL_SOURCE_METADATA',
        epoch=time.time(),source=identity,entry=pin(__file__),authority=pin(authority),preparation=a['preparation'],
        unit_show=unit,owned_processes=processes,records=records,first_sealed_chunk=first,
        context_receipt_available=records['context_readiness.json'] is not None,
        unavailable_records=[n for n,v in records.items() if v is None],
        new_chunk_seals=len(seals),numerical_modules_imported=False,new_forecasts=0,new_fits=0,
        claims_created=0,signals_sent=0,services_changed=0)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspect',action='store_true')
    parser.add_argument('--preparation');parser.add_argument('--authority',required=True)
    parser.add_argument('--authority-sha256',required=True)
    args=parser.parse_args()
    if args.inspect:value=inspect(args.authority,args.authority_sha256)
    else:
        require(args.preparation,'exact new preparation is required')
        value=execute(args.preparation,args.authority,args.authority_sha256)
    print(json.dumps(value,sort_keys=True,indent=2))
