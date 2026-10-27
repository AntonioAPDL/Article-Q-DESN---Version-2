"""Stdlib-only composite carry inventory through spent R155 ce9; no numerics."""
from pathlib import Path
from pricefm_r155_final_contract import (digest,immutable,pin,read,require,sealed_packet,verify_pin)
from pricefm_r155_completion_inventory import (build_inventory as original_inventory,
    science,chunks,A,B,validate_row as original_validate_row)

BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021')
R155=BASE/'r155_screening_recovery_20261027'
OLD_PREP=R155/'ee_completion/prepared_v2/preparation.json'
OLD_PREP_SHA='3cb562ccd1db79864a95c6ed0bcdd2dcaf19c0a928c2e04c3a4fced17b904479'
OLD_OUT=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns/pricefm_stage_r155_ee_completion_ce9fcaa3510d4d92b8aafc9a602ba719')
CARRIED_B2=f'EE_{B}_s2_S_seed0'
MISSING=[f'EE_{B}_s3_S_seed0']


def r155_row(folder,task,original,execution,checkpoint=False):
    folder=Path(folder);seal=sealed_packet(folder);context=science(task,original)
    if checkpoint:
        descriptor=next(d for d in chunks(task) if d['name']==folder.name)
        context=dict(context=context,descriptor=descriptor)
    require(seal.get('schema')=='r155_completion_packet_v1' and seal.get('scientific_context')==context
            and seal.get('execution')==execution,'R155 scientific/composite execution differs: '+str(folder))
    return dict(kind='R155_checkpoint' if checkpoint else 'R155_component',task=task['name'],
        folder=str(folder),seal=pin(folder/'completed_evidence.json'))


def validate_row(row,tasks,original,inventory):
    if row['kind'].startswith('R155'):
        require(pin(Path(row['folder'])/'completed_evidence.json')==row['seal'],'carried R155 seal changed')
        require(r155_row(row['folder'],tasks[row['task']],original,inventory['R155_execution'],
                row['kind']=='R155_checkpoint')==row,'R155 carry row differs')
    else:original_validate_row(row,tasks,original,inventory['R154_execution'])


def build_inventory():
    value=original_inventory()
    require(digest(OLD_PREP)==OLD_PREP_SHA,'spent R155 preparation changed')
    prep=read(OLD_PREP);original=verify_pin(prep['original_preparation']);tasks={t['name']:t for t in prep['tasks']}
    old_inventory=verify_pin(prep['composite_inventory'])
    require(value==old_inventory,'entire original R149/R150/R154 inventory differs')
    require(prep['source']['head']=='b6a8525bf83c187908e499e0a75424354bb7ed1e','spent R155 source differs')
    authority=read(OLD_OUT/'authority.json');claim=read(OLD_OUT/'claim.json')
    require(verify_pin(claim['authority'])==authority and authority['source']==prep['source']
            and read(OLD_OUT/'preparation_pin.json')==pin(OLD_PREP),'spent R155 authority/claim/preparation differs')
    paid=read(OLD_OUT/'supervisor_exit_receipt.json');exit_record=read(OLD_OUT/'exit_receipt.json')
    require(exit_record['status']=='INCOMPLETE' and paid['child_exit_code']==1
            and abs(paid['all_inclusive_charged_CPU_seconds']-2692.2750262410004)<1e-8,
            'spent R155 disposition/conservative charge differs')
    execution=dict(source=prep['source'],scope_id=authority['scope_id'],permit_id=authority['permit_id'],
        authority=pin(OLD_OUT/'authority.json'),composite_inventory=prep['composite_inventory'],
        original_scientific_source=original['source'],R154_execution=value['R154_execution'],new_fits=0,official_origins=0)
    require({p.parent.name for p in (OLD_OUT/'tasks_done').glob('*/completed_evidence.json')}=={CARRIED_B2},
            'exactly Bsplit2 must be carried complete from R155')
    new_rows=[r155_row(OLD_OUT/'tasks_done'/CARRIED_B2,tasks[CARRIED_B2],original,execution)]
    for seal in sorted((OLD_OUT/'checkpoints').glob('*/*/completed_evidence.json')):
        task=tasks[seal.parent.parent.name]
        require(task['name'] in (CARRIED_B2,MISSING[0]),'unexpected R155 checkpoint task')
        new_rows.append(r155_row(seal.parent,task,original,execution,True))
    require(sum(r['kind']=='R155_checkpoint' for r in new_rows)==35,'exact35 R155 new chunks required')
    partial=[r for r in new_rows if r['kind']=='R155_checkpoint' and r['task']==MISSING[0]]
    require(len(partial)==15 and {Path(r['folder']).name for r in partial}=={d['name'] for d in chunks(tasks[MISSING[0]])[:15]},
            'exact15 ordered Bsplit3 chunks required')
    require(len(chunks(tasks[MISSING[0]]))==88,'whole Bsplit3 geometry differs')
    previous=value['previous_paid_scope']
    current=dict(scope_id=authority['scope_id'],source=prep['source'],authority=pin(OLD_OUT/'authority.json'),
        claimed_authority=claim['authority'],claim=pin(OLD_OUT/'claim.json'),exit=pin(OLD_OUT/'exit_receipt.json'),
        supervisor_exit=pin(OLD_OUT/'supervisor_exit_receipt.json'),
        conservative_CPU_charge=paid['all_inclusive_charged_CPU_seconds'],
        observed_CPU_inclusive=paid['all_inclusive_observed_CPU_seconds'],refund_authorized=False)
    value.update(schema='r155_final_component_composite_inventory_v1',rows=value['rows']+new_rows,
        previous_paid_scope=dict(schema='r155_paid_scope_chain_v1',scopes=[previous,current],refund_authorized=False),
        R155_preparation=pin(OLD_PREP),R155_execution=execution,R155_carried_S0_components=1,
        R155_new_chunks=35,partial_S0_chunks=15,missing_chunks=73,carried_S0_components=8,
        remaining_component_names=MISSING,one_component_only=True)
    return value
