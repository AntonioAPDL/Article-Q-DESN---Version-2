#!/usr/bin/env python3
"""Prepare the exact two-S0 completion, using JSON/byte checks only."""
import argparse
from pathlib import Path
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pricefm_r155_completion_contract import digest,immutable,pin,read,require,source_identity
from pricefm_r155_completion_inventory import build_inventory,OLD_PREP,R154,DATA,MISSING
ROOT=Path(__file__).resolve().parents[3]


def prepare(destination):
    identity=source_identity(ROOT)
    destination=Path(destination)
    inventory=build_inventory()
    old=read(OLD_PREP)
    estimates={n:old['task_estimates'][n] for n in MISSING}
    floor=sum(v['estimated_cpu_seconds'] for v in estimates.values())
    require(abs(floor-2092.2750262410005)<1e-8,'whole two-component historical price differs')
    immutable(destination/'carry_inventory.json',inventory)
    sources=[Path(__file__),Path(__file__).with_name('524_run_pricefm_stage_r155_ee_completion.py'),
        Path(__file__).with_name('pricefm_r155_completion_contract.py'),
        Path(__file__).with_name('pricefm_r155_completion_inventory.py')]
    value=dict(schema='r155_ee_completion_preparation_v1',status='PREPARED_NOT_ADMITTED',
        study='EE',source=identity,execution_source_sha256={str(p):digest(p) for p in sources},
        composite_inventory=pin(destination/'carry_inventory.json'),
        original_preparation=old['original_preparation'],R154_preparation=pin(OLD_PREP),
        public_helper=old['public_helper'],tasks=old['tasks'],packages=old['packages'],
        audit_key=old['audit_key'],control='C0',negative_control='C5',
        previous_paid_scope=inventory['previous_paid_scope'],remaining_component_names=MISSING,
        task_estimates=estimates,historical_model_only_two_full_components_CPU=floor,
        historical_prefix_floor_CPU=4500,historical_replacement_floor_CPU=1200,
        new_campaign_parent=str(DATA/'campaigns'),max_new_tasks=2,max_new_D=0,max_new_S0=2,
        paired_cache_equivalence=dict(task=MISSING[0],chunk='clock00_part000',
            deterministic_rtol=1e-11,deterministic_atol=1e-10,
            rule='One retained chunk replay inside the full undiscounted declared component; retain original arrays after equivalence. No extra component.'),
        new_fits=0,official_origins=0,allow_extra_seeds=False,extra_seeds_authorized=False,
        dispatch_authorized=False,promotion_authorized=False,
        qualification_unchanged='gain >= 0.5*max(0.10,0.01*matched_S0_C0_AQL)',
        LV_completed_gate=dict(authority=pin(R154/'screening/ROOT_LV_ADMITTED_01.json'),
            output_dir=str(DATA/'campaigns/pricefm_stage_r154_lv_361753cd84a64ae69892b8bdcef32a04')),
        global_contract=pin(R154/'resources/GLOBAL_PERMIT_CONTRACT_V2.json'),
        original_global_lock_identity=dict(device=2304,inode=59124844))
    immutable(destination/'preparation.json',value)
    immutable(destination/'prepared.json',dict(schema='r155_completion_prepared_seal_v1',
        preparation=pin(destination/'preparation.json'),inventory=pin(destination/'carry_inventory.json'),
        source=identity,metadata_only=True,new_forecasts=0,new_fits=0,dispatch_authorized=False))
    return read(destination/'prepared.json')


if __name__=='__main__':
    import json
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination',required=True)
    print(json.dumps(prepare(parser.parse_args().destination),sort_keys=True,indent=2))
