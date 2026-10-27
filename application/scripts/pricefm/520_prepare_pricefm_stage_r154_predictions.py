#!/usr/bin/env python3
"""Prepare or stage immutable R154 prediction inputs; never dispatch numerics."""
from __future__ import annotations
import argparse
import io
import json
import os
from pathlib import Path
import sys
import tarfile

sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pricefm_r154_prediction_contract import (digest,fingerprint,immutable,pin,read,
    require,source_identity,verify_hashes)

ROOT=Path(__file__).resolve().parents[3]
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021')
PLAN=BASE/'parallel_repair_and_screening_plan_20261026_1648PDT/screening'
R153=BASE/'r153_control_and_diagnostics_20261025/science'


def execution_sources():
    files=[Path(__file__),Path(__file__).with_name('521_run_pricefm_stage_r154_predictions.py'),
           Path(__file__).with_name('522_run_pricefm_stage_r154_serial.py'),
           Path(__file__).with_name('pricefm_r154_prediction_contract.py')]
    return {str(p):digest(p) for p in files}


def ee_preparation():
    manifest=read(PLAN/'EE_REMAINING_MANIFEST.json')
    old_path=Path(manifest['original_preparation'])
    require(digest(old_path)==manifest['original_preparation_sha256'],'original EE preparation changed')
    old=read(old_path)
    require(len(manifest['remaining_D'])==58 and manifest['D_complete']==20
            and len(manifest['checkpoint_packets'])==225,'EE exact frozen inventory differs')
    byname={t['name']:t for t in old['tasks']}
    for item in manifest['remaining_D']:
        require(fingerprint(byname[item['name']])==item['task_sha256'],'EE canonical task differs')
    # No old runtime JSON is mutated, no expired scope or old worker is reopened.
    config=read(ROOT/'application/config/pricefm_stage_r150_bounded_admission_20261023.json')
    helper=config['producer_entry']
    require(digest(helper)==config['producer_entry_sha256'],'frozen public helper changed')
    allowed=[t for t in old['tasks'] if t['seed_index']==0 and t['mode'] in ('D','S')]
    require(len(allowed)==156,'unexpected EE initial-only task universe')
    equivalence=min(manifest['checkpoint_packets'],key=lambda p:(p['task'],p['clock'],p['chunk']))
    return dict(study='EE',kind='cached_Normal_full_origin_D_then_matched_S0',
        original_preparation=pin(old_path),frozen_plan=pin(PLAN/'EE_REMAINING_MANIFEST.json'),
        frozen_prices=pin(PLAN/'HISTORICAL_PRICE_AUDIT.json'),
        original_scientific_source=old['source'],immutable_numerical_producer=old['immutable_numerical_producer'],
        public_helper=dict(path=helper,sha256=config['producer_entry_sha256']),
        original_campaign=str(DATA/'campaigns/pricefm_stage_r150_bounded_admission_20261023'),
        tasks=allowed,remaining_D_names=[t['name'] for t in manifest['remaining_D']],
        old_produced_D=manifest['completed_produced_D'],old_reused_D=manifest['exact_reused_D'],
        retained_checkpoint_packets=manifest['checkpoint_packets'],packages=old['packages'],
        control='C0',negative_control='C5',audit_key='pricefm_continuation_plan_20261023|audit_v1',
        task_estimates=old['pricing']['task_estimates'],
        historical_prefix_floor_CPU=11906.48450534399,
        historical_replacement_floor_CPU=1178.4300025665002,
        prefix_cost_includes_existing_50pct_contingency=True,
        paired_cache_equivalence=dict(task=equivalence['task'],chunk=equivalence['chunk'],
            original_seal=pin(equivalence['path']),
            rule='Recompute this included D chunk once within its full un-discounted component budget; compare original public-helper output to exact retained arrays before using it in the same component. No additional component or free benchmark.',
            deterministic_atol=1e-10,deterministic_rtol=1e-11),
        max_new_tasks=64,max_new_D=58,max_new_S0=6,extra_seeds_authorized=False,
        old_science_reserved_CPU=1846.990382145998,old_cached_control_CPU=428.62592073485877,
        old_ledgers_read_only=True)


def lv_preparation():
    path=R153/'LV_TRAINING_DIAGNOSTIC_MANIFEST.json'
    frozen=read(path)
    evidence_path=R153/'JEREZ_SAVED_EVIDENCE.json'
    evidence=read(evidence_path)['LV']
    require(len(frozen['call_manifest'])==12 and frozen['origin_clock_pairs']==144
            and frozen['posterior_paths']==500,'LV call boundary differs')
    sources=frozen['source_sha256']
    cores=[p for p in sources if p.endswith('/pricefm_r134_core.py')]
    require(len(cores)==1,'unambiguous frozen LV public core required')
    bank=[(p,h) for p,h in evidence['bank_expected_sha256'].items() if p.endswith('/target_only.npz')]
    require(len(bank)==1,'exact LV target-only bank required')
    # Artifact inventory is original absolute identity, not an execution rewrite.
    files=dict(sources)
    files[bank[0][0]]=bank[0][1]
    campaign=DATA/'campaigns/pricefm_stage_r141_recovery_rollout_20261019__LV'
    for group in evidence['prospective_training_groups']:
        design=Path(group['design_dir'])
        files[str(design/'terminal.json')]=group['design_terminal_sha256']
        files[str(design/'scaler.json')]=group['scaler_sha256']
        for name,parent in group['parents'].items():
            folder=campaign/'tasks_done'/name
            files[str(folder/'completed_evidence.json')]=parent['seal_sha256']
            for filename,sha in parent['artifacts'].items():files[str(folder/filename)]=sha
        files[str(campaign/'tasks'/(group['task']['name']+'.json'))]=group['task_sha256']
    # Source/task JSON below is retained verbatim from the prior sealed reader.
    return dict(study='LV',kind='fixed_training_pooling_diagnostic',frozen_plan=pin(path),
        prior_training_evidence=pin(evidence_path),call_manifest=frozen['call_manifest'],
        frozen_manifest=frozen,training_groups=evidence['prospective_training_groups'],
        source_sha256=sources,input_files_sha256=files,dependency=evidence['dependency'],
        public_core=dict(path=cores[0],sha256=sources[cores[0]]),
        bank=dict(path=bank[0][0],sha256=bank[0][1]),
        candidate=evidence['frozen_choice'],forecast_seed=evidence['protocol']['forecast_seed'],
        original_campaign=str(campaign),historical_prefix_floor_CPU=0,
        historical_replacement_floor_CPU=0,max_new_tasks=12,new_fits=0,
        current_CPU_price=None,current_ETA=None,
        first_call_is_included_pricing_observation=True,no_thirteenth_call=True,
        official_origins_used=0,candidate_nomination_authorized=False)


def prepare(study,destination):
    identity=source_identity(ROOT)
    value=ee_preparation() if study=='EE' else lv_preparation()
    value.update(schema='r154_prediction_preparation_v1',status='PREPARED_NOT_ADMITTED',
        source=identity,execution_source_sha256=execution_sources(),new_campaign_parent=str(DATA/'campaigns'),
        new_fits=0,official_origins=0,dispatch_authorized=False,promotion_authorized=False)
    destination=Path(destination)
    immutable(destination/'preparation.json',value)
    immutable(destination/'prepared.json',dict(schema='r154_prepared_seal_v1',
        preparation=pin(destination/'preparation.json'),source=identity,dispatch_authorized=False))
    return dict(status=value['status'],preparation=pin(destination/'preparation.json'),study=study)


def export_lv(preparation,archive):
    """Byte-only staging, no fit load or numerical imports; source host only."""
    prep=read(preparation)
    require(prep['study']=='LV','only LV may use staged read aliases')
    files=prep['input_files_sha256']
    verify_hashes(files)
    archive=Path(archive)
    require(not archive.exists(),'refuse to overwrite staged archive')
    manifest=dict(schema='r154_lv_byte_stage_v1',preparation=pin(preparation),
                  original_file_sha256=files,byte_preserving=True,new_predictions=0,new_fits=0)
    with tarfile.open(archive,'w') as tar:
        data=(json.dumps(manifest,sort_keys=True,indent=2)+'\n').encode()
        info=tarfile.TarInfo('stage_manifest.json');info.size=len(data)
        tar.addfile(info,io.BytesIO(data))
        for filename,expected in sorted(files.items()):
            require(Path(filename).is_absolute(),'absolute identity required')
            tar.add(filename,arcname='files/'+filename.lstrip('/'),recursive=False)
    return pin(archive)


def import_lv(preparation,archive,destination):
    prep=read(preparation)
    require(prep['study']=='LV','only LV may use staged read aliases')
    destination=Path(destination).resolve()
    require(not destination.exists(),'new staging destination required')
    with tarfile.open(archive) as tar:
        members=tar.getmembers()
        require(len({m.name for m in members})==len(members),'duplicate staging member')
        mf=tar.extractfile('stage_manifest.json')
        require(mf is not None,'staging manifest missing')
        manifest=json.loads(mf.read())
        require(manifest['preparation']==pin(preparation)
                and manifest['original_file_sha256']==prep['input_files_sha256'], 'staging mathematical lineage differs')
        expected={'stage_manifest.json'}|{'files/'+p.lstrip('/') for p in prep['input_files_sha256']}
        require({m.name for m in members}==expected,'staging member set differs')
        for member in members:
            target=(destination/member.name).resolve()
            require(member.isfile() and target.is_relative_to(destination),'unsafe staging member')
        destination.mkdir(parents=True)
        for member in members:
            target=destination/member.name
            target.parent.mkdir(parents=True,exist_ok=True)
            with tar.extractfile(member) as src,target.open('xb') as dst:
                while True:
                    block=src.read(1024*1024)
                    if not block:break
                    dst.write(block)
    aliases={p:str(destination/'files'/p.lstrip('/')) for p in prep['input_files_sha256']}
    verify_hashes({aliases[p]:h for p,h in prep['input_files_sha256'].items()})
    receipt=dict(schema='r154_lv_read_aliases_v1',preparation=pin(preparation),
        archive=pin(archive),read_aliases=aliases,original_files_untouched=True,
        original_descriptor_rewritten=False)
    immutable(destination/'read_aliases.json',receipt)
    return pin(destination/'read_aliases.json')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('prepare');p.add_argument('--study',choices=['EE','LV'],required=True);p.add_argument('--destination',required=True)
    p=sub.add_parser('export-lv');p.add_argument('--preparation',required=True);p.add_argument('--archive',required=True)
    p=sub.add_parser('import-lv');p.add_argument('--preparation',required=True);p.add_argument('--archive',required=True);p.add_argument('--destination',required=True)
    args=parser.parse_args()
    if args.command=='prepare':value=prepare(args.study,args.destination)
    elif args.command=='export-lv':value=export_lv(args.preparation,args.archive)
    else:value=import_lv(args.preparation,args.archive,args.destination)
    print(json.dumps(value,sort_keys=True,indent=2))


if __name__=='__main__':main()
