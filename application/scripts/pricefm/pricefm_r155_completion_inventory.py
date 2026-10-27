"""Byte/JSON-only R150 and R154 carry inventory; no numerical imports."""
from pathlib import Path
from pricefm_r155_completion_contract import (digest,fingerprint,immutable,pin,read,
    require,sealed_packet,verify_hashes,verify_pin)

BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021')
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
R154=BASE/'r154_parallel_repair_20261026'
OLD_PREP=R154/'screening/ee_prepared_v4/preparation.json'
OLD_PREP_SHA='aa67326e2591792b94e0602d73d549f950253e9598764ddaed34ca623b8919eb'
OLD_OUT=DATA/'campaigns/pricefm_stage_r154_ee_41f4681164dd4d0989253889de3be8ae'
FROZEN_HEAD='cd113800f7db31068ace2f2a2abdd8b227cefe28'
A='r134_5c42f007409acfb3'
B='r134_984fd326bd5fd13e'
MISSING=[f'EE_{B}_s{s}_S_seed0' for s in (2,3)]


def science(task, original):
    return dict(source=original['source'],task_sha256=fingerprint(task),
        scientific_identity_sha256=task['scientific_identity_sha256'],mode=task['mode'],
        seed=task['forecast_seed'],parent_seal_sha256=task['parent_seal_sha256'],
        scaler_sha256=task['scaler_sha256'],bank=task['bank'],paths=100)


def chunks(task):
    return [dict(name=f'clock{offset:02d}_part{start//8:03d}',clock_offset_steps=offset,
        origin_positions=task['daily_origin_positions'][start:start+8],
        origin_timestamps=task['origin_timestamps'][str(offset)][start:start+8],
        stable_rng_origin_keys=[p*96+offset for p in task['daily_origin_positions'][start:start+8]])
        for offset in task['clock_offsets_steps'] for start in range(0,len(task['daily_origin_positions']),8)]


def packet_row(folder, task, expected, execution=None, checkpoint=False):
    """Schemas are deliberately separate: R150 context/identity vs R154 science/execution."""
    folder=Path(folder)
    seal=sealed_packet(folder)
    if execution is None:
        require(seal.get('identity' if checkpoint else 'context')==expected,
                'R150 original mathematical context differs: '+str(folder))
        kind='R150_checkpoint' if checkpoint else 'R150_component'
    else:
        require(seal.get('schema')=='r154_prediction_packet_v1'
                and seal.get('scientific_context')==expected and seal.get('execution')==execution,
                'R154 scientific/execution lineage differs: '+str(folder))
        kind='R154_checkpoint' if checkpoint else 'R154_component'
    return dict(kind=kind,task=task['name'],folder=str(folder),seal=pin(folder/'completed_evidence.json'))


def validate_row(row, tasks, original, execution):
    require(pin(Path(row['folder'])/'completed_evidence.json')==row['seal'],'carried seal changed')
    task=tasks[row['task']]
    checkpoint=row['kind'].endswith('checkpoint')
    expected=science(task,original)
    if checkpoint:
        descriptor=next(d for d in chunks(task) if d['name']==Path(row['folder']).name)
        expected=dict(context=expected,descriptor=descriptor)
    actual=packet_row(row['folder'],task,expected,
        execution if row['kind'].startswith('R154') else None,checkpoint)
    require(actual==row,'carried inventory row changed')


def build_inventory():
    require(digest(OLD_PREP)==OLD_PREP_SHA,'frozen R154 preparation changed')
    prep=read(OLD_PREP)
    require(prep['source']['head']==FROZEN_HEAD,'R154 source head differs')
    original=verify_pin(prep['original_preparation'])
    require(original['source']==prep['original_scientific_source'],'R150 source lineage differs')
    verify_hashes(original['source_sha256']);verify_hashes(original['input_sha256'])
    tasks={t['name']:t for t in prep['tasks']}
    oldtasks={t['name']:t for t in original['tasks']}
    require(len(tasks)==156 and all(t==oldtasks[n] for n,t in tasks.items()),'original R150 task bytes differ')
    require(all(t['seed_index']==0 and t['mode'] in ('D','S') for t in tasks.values()),'seed0 universe differs')
    nominees=read(OLD_OUT/'nominees.json')
    require((nominees['A'],nominees['B'],nominees['full_D_complete'])==(A,B,78),'frozen nominees/barrier differ')
    authority=read(OLD_OUT/'authority.json')
    execution=dict(source=prep['source'],scope_id=authority['scope_id'],permit_id=authority['permit_id'],
        authority=pin(OLD_OUT/'authority.json'),new_fits=0,official_origins=0)
    require(nominees['execution']==execution,'nominee execution lineage differs')
    claim=read(OLD_OUT/'claim.json')
    require(verify_pin(claim['authority'])==authority and authority['source']==prep['source'],
            'old claim/authority source differs')
    require(read(OLD_OUT/'preparation_pin.json')==pin(OLD_PREP),'old claimed preparation differs')
    exit_record=read(OLD_OUT/'exit_receipt.json');paid=read(OLD_OUT/'supervisor_exit_receipt.json')
    require(exit_record['status']=='INCOMPLETE' and paid['child_exit_code']==1,'old spent scope disposition differs')
    require(abs(paid['all_inclusive_charged_CPU_seconds']-10961.212634375985)<1e-8,
            'old paid conservative charge changed')
    rows=[]
    for item in prep['old_produced_D']:
        folder=Path(prep['original_campaign'])/'tasks_done'/item['name']
        require(digest(folder/'completed_evidence.json')==item['seal_sha256'],'old full D pin differs')
        rows.append(packet_row(folder,tasks[item['name']],science(tasks[item['name']],original)))
    for item in prep['retained_checkpoint_packets']:
        folder=Path(item['path']).parent;task=tasks[item['task']]
        require(digest(folder/'completed_evidence.json')==item['seal_sha256'],'old checkpoint pin differs')
        descriptor=next(d for d in chunks(task) if d['name']==item['chunk'])
        rows.append(packet_row(folder,task,dict(context=science(task,original),descriptor=descriptor),checkpoint=True))
    require(sum(r['kind']=='R150_component' for r in rows)==14
            and sum(r['kind']=='R150_checkpoint' for r in rows)==225,'R150 inventory count differs')
    r154components=[]
    for seal in sorted((OLD_OUT/'tasks_done').glob('*/completed_evidence.json')):
        task=tasks[seal.parent.name]
        r154components.append(packet_row(seal.parent,task,science(task,original),execution))
    expected=set(prep['remaining_D_names'])|{f'EE_{A}_s{s}_S_seed0' for s in (1,2,3)}|{f'EE_{B}_s1_S_seed0'}
    require({r['task'] for r in r154components}==expected and len(expected)==62,'exact 58D+4S0 carry differs')
    rows+=r154components
    partial=[]
    for seal in sorted((OLD_OUT/'checkpoints').glob('*/*/completed_evidence.json')):
        task=tasks[seal.parent.parent.name]
        descriptor=next(d for d in chunks(task) if d['name']==seal.parent.name)
        row=packet_row(seal.parent,task,dict(context=science(task,original),descriptor=descriptor),execution,True)
        rows.append(row)
        if task['name'] in MISSING:partial.append(row)
    require(sum(r['kind']=='R154_checkpoint' for r in rows)==4400,'R154 checkpoint count differs')
    require(len(partial)==48 and {r['task'] for r in partial}=={MISSING[0]},'48 exact B split2 chunks required')
    present={Path(r['folder']).name for r in partial}
    require(present=={d['name'] for d in chunks(tasks[MISSING[0]])[:48]},'partial ordered prefix differs')
    require(len(chunks(tasks[MISSING[0]]))==68 and len(chunks(tasks[MISSING[1]]))==88,'remaining geometry differs')
    for name in MISSING:require(not (OLD_OUT/'tasks_done'/name).exists(),'remaining component already present')
    # Exact reused controls have their original R149 schema and producer; never relabel them as R150/R154.
    reuses=[]
    wanted={t['name'] for t in tasks.values() if t['mode']=='D'}|{f'EE_{p}_s{s}_S_seed0' for p in ('C0',A,B) for s in (1,2,3)}
    for name in sorted(wanted):
        task=tasks[name];reuse=task['reuse']
        if reuse:
            verify_hashes({reuse['task_path']:reuse['task_sha256'],
                str(Path(reuse['packet'])/'completed_evidence.json'):reuse['seal_sha256'],
                str(Path(reuse['packet'])/'predictions.npz'):reuse['predictions_sha256'],
                str(Path(reuse['packet'])/'result.json'):reuse['result_sha256']})
            sealed_packet(reuse['packet'])
            reuses.append(dict(task=name,producer=reuse['producer'],packet=reuse['packet'],seal=pin(Path(reuse['packet'])/'completed_evidence.json')))
    require(len(reuses)==9 and sum('_D_' in r['task'] for r in reuses)==6,'6D+3S0 original exact reuses required')
    return dict(schema='r155_ee_composite_inventory_v1',rows=rows,reuses=reuses,
        original_preparation=prep['original_preparation'],R154_preparation=pin(OLD_PREP),
        R154_execution=execution,nominees=pin(OLD_OUT/'nominees.json'),
        original_D_components=20,R154_D_components=58,R154_S0_components=4,
        R154_chunks=4400,R150_chunks=225,partial_S0_chunks=48,missing_chunks=108,
        remaining_component_names=MISSING,full_D_components=78,
        previous_paid_scope=dict(scope_id=authority['scope_id'],authority=pin(OLD_OUT/'authority.json'),
            claim=pin(OLD_OUT/'claim.json'),exit=pin(OLD_OUT/'exit_receipt.json'),
            supervisor_exit=pin(OLD_OUT/'supervisor_exit_receipt.json'),
            conservative_CPU_charge=paid['all_inclusive_charged_CPU_seconds'],
            observed_CPU_inclusive=paid['all_inclusive_observed_CPU_seconds'],refund_authorized=False))
