#!/usr/bin/env python3
"""Metadata-only conditional A-only/B-only/both matched seed1/2 preparation."""
import argparse
import json
import math
import os
import socket
from pathlib import Path
import sys
import time
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pricefm_r155_seed_contract as c
ROOT=Path(__file__).resolve().parents[3]
EE=c.R155/'ee_completion'
INITIAL_PREP=EE/'prepared_v2/preparation.json'
TEMPLATE=EE/'ROOT_EE_CHILD_TEMPLATE_ADMITTED_01.json'
ENDOWMENT=EE/'ROOT_EE_CONDITIONAL_ENDOWMENT_ADMITTED_01.json'
DIRECT=c.R155/'ee_direct_recovery/ROOT_DIRECT_EXECUTION_MANIFEST_01.json'
LEGACY_ROLE=c.R155/'review/legacy_490_waiter_audit_03/LEGACY_490_ROLE_PROPOSAL_01.json'
LEGACY_ROLE_REVIEW=c.R155/'review/legacy_490_waiter_audit_03/LEGACY_490_MATCHER_CASE_SPEC_01.json'


def full_task_audit(original):
    tasks=original['tasks'];by_name={t['name']:t for t in tasks}
    c.require(len(tasks)==len(by_name)==312 and sum(t['mode']=='D' for t in tasks)==78,'complete original312-task universe required')
    selected=[]
    for name in c.names_for([c.A,c.B]):
        task=by_name[name]
        c.require(task['mode']=='S' and task['seed_index'] in (1,2) and task['reuse'] is None
            and task['forecast_seed']==[2026101502,2026102301,2026102302][task['seed_index']]
            and task['paths']==100 and task['horizon_steps']==96
            and task['clock_offsets_steps']==[0,24,48,72]
            and task['new_model_fits']==0 and task['posterior_updated'] is False and task['test_opened'] is False,
            'original seed1/2 task/RNG/shape differs')
        c.verify_hashes(task['parent_input_sha256'])
        c.verify_hashes({task['scaler_path']:task['scaler_sha256'],task['bank']['path']:task['bank']['sha256']})
        selected.append(task)
    c.require(len(selected)==18 and len({t['parent_fit'] for t in selected})==9,'exact18possible extras/9cachedparents required')
    return selected


def profile(census,admin_rules,role):
    rows=[]
    for _ in range(3):
        cpu0=c.cpu_seconds();started=time.monotonic();processes=c.all_processes()
        conflicts,accepted=c.reviewed_peer_conflicts(30,census,{os.getpid()},processes,admin_rules,[30,62],role,{})
        rows.append(dict(CPU=c.cpu_seconds()-cpu0,wall=time.monotonic()-started,
            processes=len(processes),threads=sum(len(p.get('threads') or []) for p in processes),
            conflicts=conflicts,reviewed_metadata_role_observations=accepted,
            active_initial_study_conflicts_are_observations_not_exemptions=True))
    prior_path=c.R155/'lv_handoff/ADMIN_SCAN_PROFILE_01.json';prior=c.read(prior_path)
    floor=prior['three_scan_max_CPU_seconds']
    c.require(floor>=.321704-1e-12 and min(r['processes'] for r in rows)>100,
            'actual full-host view and frozen prior scan price required')
    return dict(schema='r155_seed_actual_host_classifier_price_v1',rows=rows,
        host=socket.gethostname(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        observer_pid_namespace=os.readlink('/proc/self/ns/pid'),proc1_pid_namespace=os.readlink('/proc/1/ns/pid'),
        prior_actual_scan_CPU_floor=floor,floor_evidence=c.pin(prior_path),
        upper_scan_CPU=max(floor,max(r['CPU'] for r in rows))*1.5,actual_affinity=sorted(os.sched_getaffinity(0)),
        base_numerical_detection_unchanged=True,reviewed_admin_role_added=True,
        scientific_claims=0,new_forecasts=0)


def partial_public_windows(task,retained_names):
    descriptors=c.chunks(task);by_name={d['name']:d for d in descriptors}
    c.require(retained_names and retained_names.issubset(by_name)
            and descriptors[0]['name'] in retained_names,
            'partial timing must pin valid retained chunks and the included retained proof')
    newly_predicted=sum(len(d['origin_positions']) for d in descriptors if d['name'] not in retained_names)
    proof=len(descriptors[0]['origin_positions'])
    c.require(newly_predicted>0,'partial timing has no remaining public windows')
    return newly_predicted+proof


def timing_inventory(initial,inventory,original,final_manifest=None):
    tasks={t['name']:t for t in original['tasks']};oldrows={r['task']:r for r in inventory['rows'] if r['kind'].endswith('component')}
    reused={r['task']:r for r in inventory['reuses']};new_out=Path(c.read(TEMPLATE)['output_dir'])
    records=[]
    for p in ('C0',c.A,c.B):
        for s in (1,2,3):
            name=f'EE_{p}_s{s}_S_seed0';task=tasks[name]
            if name in oldrows:folder=Path(oldrows[name]['folder']);source='R154'
            elif name in reused:folder=Path(reused[name]['packet']);source='R149'
            elif name==c.MISSING[1] and final_manifest is not None:
                final_authority=c.verify_pin(final_manifest['authority'])
                folder=Path(final_authority['output_dir'])/'tasks_done'/name;source='R155_FINAL'
            else:folder=new_out/'tasks_done'/name;source='R155'
            if not (folder/'completed_evidence.json').exists():
                records.append(dict(task=name,source=source,complete=False));continue
            seal=c.sealed_packet(folder);result=c.read(folder/'result.json')
            if name in oldrows:c.require(c.pin(folder/'completed_evidence.json')==oldrows[name]['seal'],'old S0 timing packet changed')
            if name in reused:c.require(c.pin(folder/'completed_evidence.json')==reused[name]['seal'],'original control timing packet changed')
            windows=len(task['daily_origin_positions'])*4;normalization=windows;partial=False
            if source=='R155' and name==c.MISSING[0]:
                retained={Path(r['folder']).name for r in inventory['rows'] if r['kind']=='R154_checkpoint' and r['task']==name}
                normalization=partial_public_windows(task,retained)
                partial=True
            if source=='R155_FINAL':
                final_preparation=c.verify_pin(final_manifest['preparation'])
                retained={Path(r['folder']).name for r in c.verify_pin(final_preparation['composite_inventory'])['rows']
                    if r['kind'].endswith('checkpoint') and r['task']==name}
                normalization=partial_public_windows(task,retained)
                c.require(result['full_component_origin_clock_windows']==windows==692
                    and result['predicted_origin_clock_windows']==normalization==580
                    and result['included_equivalence_origin_clock_windows']==8
                    and result['public_chunk_calls']==74 and result['new_chunk_seals']==73,
                    'final Bsplit3 partial public timing boundary differs')
                partial=True
            observed=result.get('measured_CPU_seconds') if source!='R149' else None
            if observed is not None:c.require(math.isfinite(observed) and observed>0,'complete S0 timing malformed')
            records.append(dict(task=name,source=source,complete=True,seal=c.pin(folder/'completed_evidence.json'),
                result=c.pin(folder/'result.json'),measured_CPU_seconds=observed,full_origin_clock_windows=windows,
                priced_public_windows_for_partial_normalization=normalization,
                timing_includes_retained_chunk_discount=partial,
                normalized_CPU_per_window=None if observed is None else observed/normalization,
                source_control_has_no_separate_S_CPU=source=='R149',
                partial_charge_never_treated_as_full_component_discount=True))
    return records


def prices(tasks,historical,timings,scan):
    observed=[r['normalized_CPU_per_window'] for r in timings if r.get('normalized_CPU_per_window') is not None]
    c.require(observed,'at least one exact completed S0 timing required for source preparation')
    upper_per_window=1.5*max(observed);cold=max(10.,2*max(historical[t['name']]['setup_cpu_seconds_once'] for t in tasks))
    estimates={}
    for task in tasks:
        old=historical[task['name']];n=4*len(task['daily_origin_positions'])
        model=max(old['estimated_cpu_seconds'],upper_per_window*n+cold)
        estimates[task['name']]=dict(undiscounted_model_CPU=model,historical_full_CPU=old['estimated_cpu_seconds'],
            windows=n,chunks=len(c.chunks(task)),cold_CPU_once=cold,observed_S0_global_fallback=True,
            estimated_max_chunk_cpu_seconds=max(old['estimated_max_chunk_cpu_seconds'],upper_per_window*8+cold),
            old_components_or_budget_credited=False)
    scenarios={};scan_CPU=scan['upper_scan_CPU'];share=.5;cadence=5.;guardian_rate=.01
    c.require(scan_CPU/(share*cadence)+guardian_rate/share<.8,'current metadata guard cost cannot be finitely funded')
    for qualified in ([c.A],[c.B],[c.A,c.B]):
        names=c.names_for(qualified);model=sum(estimates[n]['undiscounted_model_CPU'] for n in names)
        replacement=max(estimates[n]['undiscounted_model_CPU'] for n in names)
        forced=sum(estimates[n]['chunks']+3 for n in names)+max(estimates[n]['chunks'] for n in names)
        total=model+replacement+1000.;planned=0.
        for _ in range(100):
            wall=total/share+600+1800
            peer=scan_CPU*(forced+math.ceil(wall/cadence))
            guardian=math.ceil(max(300.,wall*guardian_rate))
            updated=model+replacement+peer+500.+guardian+500.
            if abs(updated-total)<1:total=updated;planned=wall;break
            total=updated
        c.require(planned>0 and planned<=129600,'whole12/18 study lacks finite36h calendar at current guard price')
        full=math.ceil(model+peer+500);rep=math.ceil(replacement);admin=guardian+500
        # Per-component reservations include all prospective peer costs; no
        # refund/discount is taken when a reserved replacement is not used.
        ratio=full/model
        per={n:dict(estimates[n],estimated_cpu_seconds=math.ceil(estimates[n]['undiscounted_model_CPU']*ratio),
            estimated_wall_seconds=math.ceil(estimates[n]['undiscounted_model_CPU']*ratio/share),
            estimated_max_chunk_wall_seconds=math.ceil(estimates[n]['estimated_max_chunk_cpu_seconds']/share)+10)
            for n in names}
        full=max(full,sum(v['estimated_cpu_seconds'] for v in per.values()))
        scenarios['+'.join(qualified)]=dict(qualified=qualified,required_task_names=names,max_new_tasks=len(names),
            full_prefix_CPU=full,replacement_CPU=rep,admin_drain_CPU=admin,guardian_CPU_reserve=guardian,
            total_new_live_CPU=full+rep+admin,minimum_delivered_share=share,
            planned_worst_wall_seconds=math.ceil((full+rep+admin)/share+2400),
            strict_peer_scan_upper_CPU=scan_CPU,peer_Census_CPU_in_prefix=peer,forced_census_count=forced,
            task_estimates=per,preparation_CPU_conservatively_debited=200,no_old_credit=True,
            automatic_retry=False,new_seed0_components=0)
    complete=sum(r['complete'] for r in timings)==9 and sum(r.get('measured_CPU_seconds') is not None for r in timings)==6
    return dict(schema='r155_seed_undiscounted_price_v1',status='COMPLETE_INITIAL_S0_TIMING_PRICE_NOT_ADMISSION' if complete else 'PROVISIONAL_INITIAL_S0_INCOMPLETE_NOT_ADMISSIBLE',
        all_S0_complete=complete,completed_initial_S0_timings=timings,scan_profile=scan,
        full_component_model_policy='max(original full task price,1.5max completedS0 CPU/publicwindow ×fullwindows+coldonce); global fallback for allcontrols',
        partial_component_timing_policy='R155 Bsplit2 and final Bsplit3 CPU normalized only by newly predicted+includedproofwindows; never divide partial charges by fullcohort to discount future components',
        guard_price_policy='upper1.5actualhostscanCPU ×(allforcedchunkchecks +wholeactivecalendar/5s), fixedpoint funds guardCPU and guardianwall before admission',
        scenarios=scenarios,new_fits=0,new_forecasts=0,admission=False)


def prepare(destination,final_manifest_path=None,legacy_role_path=LEGACY_ROLE,legacy_role_review_path=LEGACY_ROLE_REVIEW):
    c.require(os.sched_getaffinity(0)=={31},'all metadata preparation must enter CPU31')
    destination=Path(destination);c.require(not destination.exists(),'new immutable conditional preparation directory required')
    identity=c.source_identity();initial=c.read(INITIAL_PREP);original=c.verify_pin(initial['original_preparation'])
    final_manifest=None if final_manifest_path is None else c.read(final_manifest_path)
    final_source_root=None if final_manifest is None else Path(final_manifest['source_root'])
    final_contract=None if final_source_root is None else final_source_root/'application/scripts/pricefm/pricefm_r155_final_contract.py'
    inventory=c.verify_pin(initial['composite_inventory']);root_template=c.read(TEMPLATE)
    c.require(root_template['source']==initial['source'] and initial['source']['head']=='b6a8525bf83c187908e499e0a75424354bb7ed1e','exact b6 initial scope required')
    c.verify_hashes(original['source_sha256']);c.verify_hashes(original['input_sha256'])
    tasks=full_task_audit(original);nominees=c.verify_pin(inventory['nominees'])
    c.require((nominees['A'],nominees['B'],nominees['full_D_complete'])==(c.A,c.B,78),'frozen original A/B changed')
    role=c.read(legacy_role_path)
    scan=profile(c.read(root_template['peer_census']['path']),c.read(root_template['admin_rules']['path']),role)
    timings=timing_inventory(initial,inventory,original,final_manifest)
    historical=c.verify_pin(initial['R154_preparation'])['task_estimates']
    price=prices(tasks,historical,timings,scan)
    destination.mkdir(parents=True)
    c.immutable(destination/'pricing.json',price)
    sources=[Path(__file__),Path(__file__).with_name('529_run_pricefm_stage_r155_qualified_seeds.py'),
        Path(__file__).with_name('pricefm_r155_seed_contract.py'),Path(__file__).with_name('pricefm_r155_completion_contract.py'),
        Path(__file__).with_name('pricefm_r155_completion_inventory.py'),Path(__file__).with_name('pricefm_r155_metadata_waiter.py')]
    value=dict(schema='r155_ee_qualified_seed_preparation_v1',status='CONDITIONAL_METADATA_PREPARED_NOT_ADMITTED',
        study='EE',source=identity,execution_source_sha256={str(p):c.digest(p) for p in sources},
        original_preparation=initial['original_preparation'],original_scientific_source=original['source'],
        initial_source=initial['source'],initial_preparation=c.pin(INITIAL_PREP),initial_child_template=c.pin(TEMPLATE),
        initial_source_root=str(Path(next(iter(initial['execution_source_sha256']))).parents[3]),
        initial_scientific_entry=str(Path(next(iter(initial['execution_source_sha256']))).with_name('524_run_pricefm_stage_r155_ee_completion.py')),
        initial_endowment=c.pin(ENDOWMENT),composite_inventory=initial['composite_inventory'],
        initial_direct_execution_manifest=c.pin(DIRECT),
        initial_final_execution_manifest=None if final_manifest is None else c.pin(final_manifest_path),
        initial_final_contract=None if final_contract is None else c.pin(final_contract),
        initial_final_source=None if final_manifest is None else final_manifest['source'],
        initial_final_source_root=None if final_source_root is None else str(final_source_root),
        initial_final_preparation=None if final_manifest is None else final_manifest['preparation'],
        initial_final_route_required_before_any_claim=True,failed_direct_route_is_never_success=True,
        legacy_metadata_role=c.pin(legacy_role_path),
        legacy_metadata_role_helper=c.pin(Path(__file__).with_name('pricefm_r155_metadata_waiter.py')),
        legacy_metadata_role_review=c.pin(legacy_role_review_path),
        nominees=inventory['nominees'],public_helper=initial['public_helper'],tasks=tasks,packages=initial['packages'],
        possible_scenarios=[dict(qualified=q,required_task_names=c.names_for(q),components=len(c.names_for(q))) for q in ([c.A],[c.B],[c.A,c.B])],
        pricing=c.pin(destination/'pricing.json'),global_contract=initial['global_contract'],
        original_global_lock_identity=initial['original_global_lock_identity'],
        previous_paid_scope=initial['previous_paid_scope'],all_prior_claims_clocks_and_charges_retained=True,
        allowed_seed_indices=[1,2],new_seed0_components=0,new_fits=0,official_origins=0,
        re_nomination_allowed=False,dispatch_authorized=False,automatic_retry=False,
        complete_87_component_independent_array_analysis_required=True,
        no_qualifiers_disposition='NO_SCIENCE_NEEDED_NO_CLAIM_NO_DISPATCH')
    c.immutable(destination/'preparation.json',value)
    c.immutable(destination/'prepared.json',dict(preparation=c.pin(destination/'preparation.json'),pricing=value['pricing'],
        source=identity,metadata_only=True,dispatch_authorized=False))
    for key,scenario in price['scenarios'].items():
        label=('A' if key==c.A else 'B' if key==c.B else 'AB')+'_'+str(scenario['max_new_tasks'])
        a=dict(schema='r155_ee_qualified_seed_authority_v1',status='PROPOSED',scope_id='ROOT_NEW_UUID',study='EE',
            unit='pricefm-r155-ee-qualified-seeds-ROOT_NEW_UUID.service',
            source=identity,preparation=c.pin(destination/'preparation.json'),
            output_dir=str(c.DATA/'campaigns'/('pricefm_stage_r155_ee_qualified_seeds_ROOT_NEW_UUID')),
            host='muscat',cpu=30,physical_sibling_cpus=[30,62],permit_id='muscat_cpu30',
            start_epoch=None,expires_epoch=None,max_wall_seconds=129600,max_execution_wall_seconds=129600,
            nonrenewing=True,automatic_retry=False,qualified_packages=scenario['qualified'],required_task_names=scenario['required_task_names'],
            max_new_tasks=scenario['max_new_tasks'],allowed_seed_indices=[1,2],new_seed0_components=0,
            allow_extra_seeds=True,new_fits=0,official_origins=0,
            full_prefix_CPU=scenario['full_prefix_CPU'],replacement_CPU=scenario['replacement_CPU'],
            admin_drain_CPU=scenario['admin_drain_CPU'],guardian_CPU_reserve=scenario['guardian_CPU_reserve'],
            prior_CPU_charged_seconds=200,total_CPU_cap=200+scenario['total_new_live_CPU'],
            source_preparation_200CPU_is_inclusive_prior_view_not_additional_charge=True,
            min_delivered_share=.5,drain_seconds=600,maximum_atomic_wall_seconds=1800,
            minimum_available_RAM_GiB=192,minimum_free_disk_GiB=80,own_RSS_soft_GiB=24,new_output_soft_GiB=4,
            peer_census_cadence_seconds=5,scheduler_policy='SCHED_OTHER',nice=10,io_class=3,
            hard_cgroup_isolation_claimed=False,independent_analysis_seal=None,initial_root_closing_proof=None,
            pricing_evidence=c.pin(destination/'pricing.json'),source_review=dict(path='ROOT_NEW_PASSED_SOURCE_REVIEW',sha256='ROOT_SHA256'),
            global_contract=value['global_contract'],original_global_lock_identity=value['original_global_lock_identity'])
        a['legacy_metadata_role']=value['legacy_metadata_role']
        a['legacy_metadata_role_helper']=value['legacy_metadata_role_helper']
        a['legacy_metadata_role_review']=value['legacy_metadata_role_review']
        for field in ('peer_census','admin_rules','resource_policy','process_classifier_proof'):a[field]=root_template[field]
        c.immutable(destination/('authority_proposal_'+label+'.json'),a)
    return c.read(destination/'prepared.json')


def no_science_disposition(preparation,analysis_seal,closing_proof,destination):
    c.require(os.sched_getaffinity(0)=={31},'no-science metadata disposition must remain CPU31')
    prep=c.read(preparation);gate=c.complete_initial(prep,c.pin(analysis_seal),c.pin(closing_proof))
    c.require(not gate['decision']['qualified'],'a qualified set cannot be silently declared unnecessary')
    result=dict(status='NO_SCIENCE_NEEDED_NO_CLAIM_NO_DISPATCH',initial_assessment=gate['assessment'],
        independent_analysis_seal=gate['independent_analysis_seal'],root_initial_closing_proof=gate['root_actual_initial_closing_proof'],
        unchanged_S0_decision=gate['decision'],new_fits=0,new_forecasts=0,claims_created=0,automatic_followon=False)
    c.immutable(destination,result);return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--destination',required=True)
    parser.add_argument('--no-science-disposition',action='store_true');parser.add_argument('--preparation')
    parser.add_argument('--analysis-seal');parser.add_argument('--root-closing-proof')
    parser.add_argument('--initial-final-manifest');parser.add_argument('--legacy-role',default=str(LEGACY_ROLE))
    parser.add_argument('--legacy-role-review',default=str(LEGACY_ROLE_REVIEW));args=parser.parse_args()
    if args.no_science_disposition:
        c.require(args.preparation and args.analysis_seal and args.root_closing_proof,'complete initial/independent/root proof paths required')
        value=no_science_disposition(args.preparation,args.analysis_seal,args.root_closing_proof,args.destination)
    else:value=prepare(args.destination,args.initial_final_manifest,args.legacy_role,args.legacy_role_review)
    print(json.dumps(value,sort_keys=True,indent=2))
