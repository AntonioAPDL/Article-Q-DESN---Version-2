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


def final_decision(public,split_metrics,qualified):
    """Canonical three-seed practical/stability acceptance and strongest tie rule."""
    control=[sum(split_metrics['C0'][str(seed)][str(s)]['AQL'] for s in (1,2,3))/3 for seed in (0,1,2)]
    matched={}
    for p in qualified:
        values=[sum(split_metrics[p][str(seed)][str(s)]['AQL'] for s in (1,2,3))/3 for seed in (0,1,2)]
        matched[p]=dict(public.confirm_gains(control,values),control_AQL_by_seed=control,candidate_AQL_by_seed=values)
    eligible={p:-v['mean_gain'] for p,v in matched.items() if v['eligible_for_AL_proposal']}
    lead=public.strongest(eligible) if eligible else None
    disposition=('ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED' if lead else
        'STOP_NO_QUALIFYING_CONFIRMED_LEAD' if not any(v['practical_gain'] for v in matched.values())
        else 'HOLD_ALGORITHMIC_STABILITY_UNRESOLVED')
    return dict(matched_three_seed_results=matched,lead_for_separate_AL_proposal=lead,disposition=disposition)


def replay_original_branch(public,original):
    pricing=original['pricing']
    values=(pricing['estimated_B1_max_cpu_seconds'],pricing['estimated_B2_max_cpu_seconds'],pricing['benchmark_adjusted_available_CPU_seconds'])
    branch,disposition=public.select_branch(*values)
    c.require(branch==pricing['branch']==original['prefix_contract']['branch']=='B1'
            and disposition==pricing['budget_disposition'],'frozen original B1/B2 branch selection replay differs')
    return dict(branch=branch,original_budget_disposition=disposition,original_selector_inputs=list(values),
                branch_reselected_for_new_study=False,new_B2_or_seed0_tasks_authorized=False)


def run(prep,lease,gate):
    import numpy as np
    old=c.verify_pin(prep['original_preparation']);public=c.load_module('r155_qualified_seed_frozen_public',prep['public_helper']['path'],prep['public_helper']['sha256'])
    branch=replay_original_branch(public,old)
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
        pool_path=lease.out/'runtime_numerical_threadpools.json'
        if not pool_path.exists():
            c.immutable(pool_path,dict(source=prep['source'],numerical_threadpools=pools,
                first_loaded_context_only=True,actual_affinity=sorted(os.sched_getaffinity(0))))
            lease.note_written(pool_path)
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
            and set(seal['artifacts'])=={'predictions.npz','result.json'}
            and seal['execution']==execution,'new seed component lineage differs')
        with np.load(folder/'predictions.npz',allow_pickle=False) as stream:arrays={k:stream[k] for k in stream.files}
        revalidate_saved_component(public,tasks[name],arrays,c.read(tasks[name]['scaler_path']),completed[name])
    S0={r['task']:r for r in gate['analysis']['component_records'] if r['mode']=='S'}
    split_metrics={p:{'0':{str(s):S0[f'EE_{p}_s{s}_S_seed0']['metrics'] for s in (1,2,3)},
        **{str(seed):{str(s):completed[f'EE_{p}_s{s}_S_seed{seed}'] for s in (1,2,3)} for seed in (1,2)}}
        for p in ['C0']+qualified}
    decision=final_decision(public,split_metrics,qualified);matched=decision['matched_three_seed_results']
    lead=decision['lead_for_separate_AL_proposal'];proposal=None
    if lead:
        package=next(p for p in prep['packages'] if p['package_id']==lead)
        control=next(p for p in prep['packages'] if p['package_id']=='C0')
        exact_cached_scale=package['candidate_id']==control['candidate_id'] and package['tau0']==.00024929739307713865
        proposal=dict(package_id=lead,new_candidate_fits_if_exact_identity_reused=0 if exact_cached_scale else 21,
            control_refits_authorized=False,forecast_components=18,paths=500,default_iterations=300,
            separately_benchmarked_and_budgeted_required=True,launched=False,
            stop_if_control_cache_identity_cannot_be_reused=True,operator='cdf_pool_clipped',
            same_package_Normal_driver_and_AL_receiver=True)
    c.verify_pin(gate['assessment']);c.verify_pin(prep['nominees'])
    result=dict(status='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED',execution=execution,
        required_task_names=names,new_components=len(names),new_seed0_components=0,public_chunk_calls=public_calls,
        qualified_from_unchanged_initial_S0=qualified,matched_three_seed_results=matched,
        full_matched_metrics_by_package_seed_split=split_metrics,original_B1_branch_replay=branch,
        disposition=decision['disposition'],lead_for_separate_AL_proposal=lead,conditional_AL_proposal=proposal,
        equal_three_split_macro=True,all_new_components_independently_revalidated=True,
        AL_proposal_eligibility_only={p:v['eligible_for_AL_proposal'] for p,v in matched.items()},
        AL_proposal_selection_is_original_training_only_rule=True,AL_proposal_admitted=False,automatic_followon=False,new_fits=0,official_origins=0,
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
    unit=c.own_unit(a['unit'])
    lease=c.SeedLease(a,prep,authority,unit)
    c.immutable(lease.out/'authority.json',a);c.immutable(lease.out/'preparation_pin.json',c.pin(preparation))
    try:result=run(prep,lease,gate)
    except BaseException as exc:
        lease.close('INCOMPLETE',dict(type=type(exc).__name__,message=str(exc),all_failed_charges_retained=True,automatic_retry=False));raise
    lease.close('COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT');return result


def inspect(preparation,authority,expected):
    c.require(os.sched_getaffinity(0)=={31},'read-only seed observer requiresCPU31')
    c.require(c.digest(authority)==expected,'exact seed authority pin required')
    a=c.read(authority);prep=c.read(preparation);identity=c.source_identity()
    c.require(a['schema']=='r155_ee_qualified_seed_authority_v1' and a['source']==prep['source']==identity
            and a['preparation']==c.pin(preparation),'actual source/preparation authority differs')
    c.verify_hashes(prep['execution_source_sha256']);out=Path(a['output_dir'])
    def captured(name):
        p=out/name;return None if not p.is_file() else dict(pin=c.pin(p),value=c.read(p))
    records={name:captured(name) for name in ('claim.json','authority.json','guardian.json','payload_identity.json','heartbeat.json',
        'exit_receipt.json','supervisor_exit_receipt.json','assessment.json','assessment_seal.json','full_matched_set.json','runtime_numerical_threadpools.json')}
    if records['claim.json']:c.require(records['claim.json']['value']['authority']==c.pin(authority),'seed claim binding differs')
    processes=[]
    for name,key in [('guardian.json','process'),('payload_identity.json','process')]:
        if not records[name]:continue
        old=records[name]['value'][key];current=c.process_identity(old['pid']);live=c.same_lifetime(current,old)
        result=dict(role=name,recorded=old,current=current,live_exact_lifetime=live)
        if live:
            root=Path('/proc')/str(old['pid']);fields=(root/'stat').read_text().rsplit(')',1)[1].split()
            masks={p.name:sorted(os.sched_getaffinity(int(p.name))) for p in (root/'task').iterdir()}
            c.require(current['cpus']==[30] and all(v==[30] for v in masks.values()) and int(fields[16])==10
                and os.sched_getscheduler(old['pid'])==os.SCHED_OTHER,'live seed numerical scheduling differs')
            io=c.subprocess.check_output(['ionice','-p',str(old['pid'])],text=True).strip()
            c.require(io.startswith('idle'),'live seed idle IO differs')
            result.update(thread_masks=masks,nice=int(fields[16]),scheduler='SCHED_OTHER',IO=io)
        processes.append(result)
    tasks={t['name']:t for t in prep['tasks']};old=c.verify_pin(prep['original_preparation']);verified=[]
    for name in a['required_task_names']:
        folder=out/'tasks_done'/name
        if not (folder/'completed_evidence.json').exists():continue
        seal=c.sealed_packet(folder);value=c.read(folder/'result.json')
        c.require(seal['schema']=='r155_qualified_seed_packet_v1' and seal['scientific_context']==c.science(tasks[name],old)
            and seal['execution']['source']==identity and seal['execution']['scope_id']==a['scope_id']
            and seal['execution']['authority']==c.pin(out/'authority.json') and value['seed_index'] in (1,2)
            and value['name']==name and value['mode']=='S' and value['source']==identity
            and value['numerical_threadpools'] and all(p['num_threads']==1 for p in value['numerical_threadpools']), 'seed packet source/task/pools differ')
        verified.append(dict(name=name,seal=c.pin(folder/'completed_evidence.json'),result=c.pin(folder/'result.json'),
            measured_CPU=value['measured_CPU_seconds'],seed_index=value['seed_index']))
    complete=bool(records['assessment.json'] and records['assessment_seal.json'] and records['supervisor_exit_receipt.json'] and records['exit_receipt.json']
        and records['supervisor_exit_receipt.json']['value']['child_exit_code']==0 and len(verified)==a['max_new_tasks'])
    if complete:
        assessment=records['assessment.json']['value'];seal=records['assessment_seal.json']['value']
        c.require(seal['assessment']==records['assessment.json']['pin'] and seal['execution']==assessment['execution']
            and assessment['status']=='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED'
            and assessment['required_task_names']==a['required_task_names'] and assessment['new_components']==a['max_new_tasks']
            and assessment['new_seed0_components']==0 and assessment['execution']['source']==identity
            and assessment['execution']['authority']==c.pin(out/'authority.json')
            and records['exit_receipt.json']['value']['status']=='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT',
            'full seed assessment/status/scope/bytes differ')
        complete=all(not r['live_exact_lifetime'] for r in processes)
    free=c.same_lock_free(c.verify_pin(a['global_contract']),a['original_global_lock_identity'])
    fields=('Id','MainPID','InvocationID','ActiveState','SubState','RemainAfterExit','Restart','NRestarts','KillMode','Result','ExecMainStatus')
    raw=c.subprocess.check_output(['systemctl','--user','show',a['unit'],*['--property='+k for k in fields]],text=True)
    unit=dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
    phase='PREPARED_NO_SCIENTIFIC_CLAIM'
    if records['claim.json']:
        claimed=records['claim.json']['value']['unit']
        c.require(unit.get('Id')==a['unit']==claimed['Id'] and unit.get('InvocationID')==claimed['InvocationID']
            and unit.get('Restart')=='no' and unit.get('NRestarts')=='0' and unit.get('KillMode')=='process'
            and unit.get('RemainAfterExit')=='yes','actual seed unit/invocation/no-restart contract differs')
        live_claim=c.same_lifetime(c.process_identity(records['claim.json']['value']['process']['pid']),records['claim.json']['value']['process'])
        if not processes and live_claim:phase='CLAIMED_INITIALIZING_NO_COMPLETED_COMPONENTS'
        elif any(p['live_exact_lifetime'] for p in processes):phase='RUNNING_PARTIAL_MATCHED_SET'
        else:
            phase='COMPLETED_RETAINED_UNIT_SCIENCE_INCOMPLETE'
            if complete and free:
                c.require(unit.get('MainPID')=='0' and unit.get('ActiveState')=='active' and unit.get('SubState')=='exited'
                    and unit.get('Result')=='success' and unit.get('ExecMainStatus')=='0','retained completed seed unit exit differs')
                phase='COMPLETED_RETAINED_UNIT_FULL_MATCHED_SET_DRAINED'
    elif unit.get('ActiveState')=='failed':phase='STOPPED_BEFORE_SCIENTIFIC_CLAIM_NO_RETRY'
    pools=records['runtime_numerical_threadpools.json']
    if pools:c.require(pools['value']['numerical_threadpools'] and all(p['num_threads']==1 for p in pools['value']['numerical_threadpools']), 'recorded actual loaded pools differ')
    return dict(status='READ_ONLY_SOURCE_BOUND_MATCHED_SEED_OBSERVATION',source=identity,authority=c.pin(authority),epoch=time.time(),
        phase=phase,actual_unit=unit,records=records,processes=processes,complete_components=len(verified),required_components=a['max_new_tasks'],
        remaining_components=a['max_new_tasks']-len(verified),verified_components=verified,
        scientifically_complete_and_physically_drained=complete and free,same_original_flock_free=free,
        fixed_first_T0=a['start_epoch'],fixed_expiry=a['expires_epoch'],original_global_expiry=c.verify_pin(a['global_contract'])['expires_epoch'],
        actual_loaded_pool_record_single_thread=None if not pools else True,
        runtime_writes=0,new_forecasts=0,new_fits=0,signals=0,model_helpers_imported=False)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preparation',required=True)
    parser.add_argument('--authority',required=True);parser.add_argument('--authority-sha256',required=True)
    parser.add_argument('--inspect',action='store_true',help='Read-only actual source/lifetimes/claim/seals/pools; never launch')
    args=parser.parse_args()
    value=inspect(args.preparation,args.authority,args.authority_sha256) if args.inspect else execute(args.preparation,args.authority,args.authority_sha256)
    print(json.dumps(value,sort_keys=True,indent=2))
