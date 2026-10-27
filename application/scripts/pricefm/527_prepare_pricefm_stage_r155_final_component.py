#!/usr/bin/env python3
"""Byte/JSON-only preparation of the final one-component EE completion."""
import argparse
from pathlib import Path
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pricefm_r155_final_contract import digest,immutable,pin,read,require,source_identity
from pricefm_r155_final_inventory import build_inventory,OLD_PREP,MISSING,R155
ROOT=Path(__file__).resolve().parents[3]


def prepare(destination,legacy_metadata_role,role_sha):
    identity=source_identity(ROOT);destination=Path(destination);inventory=build_inventory();old=read(OLD_PREP)
    require(digest(legacy_metadata_role)==role_sha,'explicit metadata-role preparation pin differs')
    role=read(legacy_metadata_role)
    require(role['schema']=='r155_legacy_490_metadata_role_v1','unknown metadata role schema')
    estimates={n:old['task_estimates'][n] for n in MISSING}
    require(abs(sum(v['estimated_cpu_seconds'] for v in estimates.values())-1178.4300025665002)<1e-8,'whole Bsplit3 price differs')
    immutable(destination/'carry_inventory.json',inventory)
    names=['527_prepare_pricefm_stage_r155_final_component.py','528_run_pricefm_stage_r155_final_component.py',
        'pricefm_r155_final_contract.py','pricefm_r155_final_inventory.py','pricefm_r155_metadata_waiter.py',
        'pricefm_r155_completion_inventory.py','pricefm_r155_completion_contract.py']
    sources={str(Path(__file__).with_name(name)):digest(Path(__file__).with_name(name)) for name in names}
    value=dict(schema='r155_final_preparation_v1',status='PREPARED_NOT_ADMITTED',study='EE',source=identity,
        execution_source_sha256=sources,composite_inventory=pin(destination/'carry_inventory.json'),
        original_preparation=old['original_preparation'],R154_preparation=old['R154_preparation'],R155_preparation=pin(OLD_PREP),
        public_helper=old['public_helper'],tasks=old['tasks'],packages=old['packages'],audit_key=old['audit_key'],
        control='C0',negative_control='C5',previous_paid_scope=inventory['previous_paid_scope'],remaining_component_names=MISSING,
        task_estimates=estimates,historical_model_only_one_full_component_CPU=1178.4300025665002,
        historical_prefix_floor_CPU=4250,historical_replacement_floor_CPU=1200,
        new_campaign_parent=old['new_campaign_parent'],max_new_tasks=1,max_new_D=0,max_new_S0=1,
        paired_cache_equivalence=dict(task=MISSING[0],chunk='clock00_part000',deterministic_rtol=1e-11,deterministic_atol=1e-10,
            rule='One retained Bsplit3 chunk replay inside its full undiscounted component budget, then preserve original arrays; no extra task.'),
        new_fits=0,official_origins=0,allow_extra_seeds=False,extra_seeds_authorized=False,dispatch_authorized=False,
        promotion_authorized=False,qualification_unchanged='gain >= 0.5*max(0.10,0.01*matched_S0_C0_AQL)',
        LV_completed_gate=old['LV_completed_gate'],global_contract=old['global_contract'],
        original_global_lock_identity=old['original_global_lock_identity'],
        source_only_preparation_allowance=pin(R155/'final_component_recovery/SOURCE_PREPARATION_ALLOWANCE_01.json'))
    value['legacy_metadata_role']=pin(legacy_metadata_role)
    immutable(destination/'preparation.json',value)
    immutable(destination/'prepared.json',dict(schema='r155_final_prepared_seal_v1',source=identity,
        preparation=pin(destination/'preparation.json'),inventory=value['composite_inventory'],metadata_only=True,new_forecasts=0,new_fits=0,dispatch_authorized=False))
    return read(destination/'prepared.json')


if __name__=='__main__':
    import json
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--destination',required=True)
    p.add_argument('--legacy-metadata-role',required=True);p.add_argument('--legacy-metadata-role-sha256',required=True)
    a=p.parse_args()
    print(json.dumps(prepare(a.destination,a.legacy_metadata_role,a.legacy_metadata_role_sha256),indent=2,sort_keys=True))
