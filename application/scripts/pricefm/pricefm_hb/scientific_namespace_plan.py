"""Explicit new namespace-code envelope; old2048 startup gate stays unchanged.

No package is loaded and no archive is extracted by this preparation module.
Compute extraction/startup needs separately reviewed actual Slurm/source/root
authority. Source preparation does not issue it.
"""
from __future__ import annotations

from pathlib import PurePosixPath
import re

from .runtime_archive import require

MAX_FILES = 4096
MAX_BYTES = 384 * 1024**2
MAX_FILE = 64 * 1024**2
PURPOSE = 'NEW_SCIENTIFIC_NAMESPACE_CODE_AND_STOCK_BODY_METADATA_ONLY'


def validate_closure(base,addon):
    require(base.get('schema')=='pricefm_streaming_runtime_archive_v1' and base.get('file_count')==680,
            'exact verified base code manifest required')
    require(addon.get('schema')=='r179_scientific_code_closure_v1'
            and addon.get('status')=='COMPLETE_ADDITIVE_CODE_CARRIERS_NOT_RUNTIME_OR_NUMERICAL_PROOF',
            'distinct scientific addon code manifest required')
    require(addon.get('R_executions')==0 and addon.get('scientific_data_access') is False
            and addon.get('namespace_startup_proved') is False and addon.get('base_members_overwritten')==[],
            'code preparation must not claim namespace or scientific proof')
    base_names={r['relative'] for r in base['files']}
    require(len(base_names)==len(base['files'])==base['file_count']
            and sum(r['bytes'] for r in base['files'])==base['total_bytes'],'duplicate/inconsistent base code member metadata')
    count=base['file_count']+addon['file_count'];size=base['total_bytes']+addon['code_bytes']
    require(0<count<=MAX_FILES and 0<size<=MAX_BYTES,'new scientific code closure exceeds explicit finite envelope')
    require(0<len(addon['parts'])<=4 and all(p['runtime_file_count']<=2048 and p['runtime_total_bytes']<=128*1024**2 for p in addon['parts']),
            'each existing opaque archive container retains its original shape bounds')
    require(sum(p['runtime_file_count'] for p in addon['parts'])==addon['file_count']
            and sum(p['runtime_total_bytes'] for p in addon['parts'])==addon['code_bytes'],'addon part totals differ')
    return {'schema':'r179_scientific_namespace_code_envelope_v1','purpose':PURPOSE,
            'status':'PREPARED_NEW_ENVELOPE_NOT_EXECUTION_AUTHORITY','assembled_files':count,'assembled_bytes':size,
            'max_regular_files':MAX_FILES,'max_code_bytes':MAX_BYTES,'max_one_file_bytes':MAX_FILE,
            'old_startup2048_gate_unchanged':True,'base_R_not_rebuilt':True,'scientific_target_data_allowed':False,
            'independent_new_role_source_review_required':True,'numerical_admission':False}


def validate_part_members(base,parts):
    """Validate disjoint exact member surface before any compute extraction."""
    rows=list(base['files'])
    for part in parts:rows.extend(part['files'])
    names=set();size=0;base_names={x['relative'] for x in base['files']}
    for row in rows:
        name=row['relative'];p=PurePosixPath(name)
        require(isinstance(name,str) and re.fullmatch(r'[A-Za-z0-9_./+@-]+',name)
                and not p.is_absolute() and '..' not in p.parts and str(p)==name
                and p.parts[0] in {'R_HOME','lib'},'unsafe scientific code member')
        require(name not in names,'addon cannot overwrite a base or another addon member')
        require(type(row['bytes']) is int and 0<=row['bytes']<=MAX_FILE
                and type(row['mode']) is int and 0<=row['mode']<=0o777
                and isinstance(row['sha256'],str) and re.fullmatch(r'[0-9a-f]{64}',row['sha256']),
                'finite regular code member metadata required')
        if name.startswith('R_HOME/library/'):
            relative=p.parts[3:]
            require(not relative or relative[0] not in {'data','doc','demo','help','html','tests','include'}
                    or name in base_names,'addon contains excluded dataset/documentation/header path')
        names.add(name);size+=row['bytes']
    require(len(names)<=MAX_FILES and size<=MAX_BYTES,'combined namespace code limits exceeded')
    return {'files':len(names),'bytes':size,'all_members_disjoint':True,'archive_extraction_not_performed':True}


def stage_packets(envelope,original_plan):
    """A concrete unissued gate/cost graph, preserving old science contracts."""
    require(envelope['purpose']==PURPOSE and envelope['numerical_admission'] is False,'new unadmitted code envelope required')
    return {'schema':'r179_hb_scientific_stage_preparation_v1','status':'PREPARED_UNISSUED_STAGE_PACKETS',
      'code_envelope':envelope,'unchanged_caps':original_plan['caps'],'acceptance_logic':original_plan['acceptance_logic'],
      'stages':[
        {'id':'Q_NAMESPACE','purpose':PURPOSE,'optimizer_invocations':0,'requires':['accepted actual baseR qualification','exact disjoint new namespace code envelope','fresh source/config/role/Slurm/root/peer authority','independent source review and complete cost'],
         'outputs':['all48 namespace versions/paths','exact stock body SHA','actual loaded package DLL/ABI pins','complete guard and primary Slurm accounting'],
         'proposed_whole_CPU_ceiling':600,'proposed_whole_wall_ceiling':1200,'proposal_not_reserved_or_measured':True},
        {'id':'Q_BOUNDARY','purpose':'HB_ZERO_TARGET_ZERO_OPTIMIZER_NATIVE_SCIENTIFIC_TSYNC_BOUNDARY','optimizer_invocations':0,'requires':['Q_NAMESPACE','unchanged r157 tracer and boundary source/binary pins','new host-specific owner/resource/peer/lock authority','independent review and full cost'],
         'outputs':['kernel-held ptrace ownership from first newborn','actual TSYNC scientific filter bytes/kernel return','proof/ACK before target access','reaped/drained whole accounting'],
         'H_ptrace_child_filter_cannot_be_bypassed_or_relaxed':True,'cannot_nest_tracer_below_H':True,'proposed_whole_CPU_ceiling':600,'proposed_whole_wall_ceiling':1200,'proposal_not_reserved_or_measured':True},
        {'id':'TOY_PARITY','purpose':'HB_SAME_FROZEN_525_FULL_STATE_TOY','requires':['Q_BOUNDARY','reviewed authority-only HB prefix port','new finite exact stage grant'],
         'optimizer_invocations':8,'combined_iterations':30,'maximum_n':128,'maximum_p':32,'production_fits':0,
         'new_whole_attempt_cost_required':True,'historical_ceiling300_not_new_funding':True},
        {'id':'ZERO_UPDATE_BRIDGE','purpose':'EXACT_REAL_TARGET_CONDITIONAL_STATE_BRIDGE','requires':['TOY_PARITY','opaque target delivery separately authorized and fully hashed','new alias/source/host/target manifest and cost'],
         'optimizer_updates':0,'all7_gates_and_both_RHS_starts_required':True,'source_context_whole_cost_required':True},
        {'id':'NO3_AL300_PILOT','purpose':'ONE_NEW_INITIALIZATION_NOT_EXACT_RESUME','requires':['ZERO_UPDATE_BRIDGE','new complete target/initializer/root authority','measured source-context price'],
         'max_iter':300,'new_attempts':1,'automatic_retry':False,'production_acceptance':False,
         'historical_pricing_provisional_not_new_funding':original_plan.get('pricing',{})},
      ],'scientific_target_transfer_not_performed':True,'no_stage_execution_authority':True,
      'whole_cost_model':'Each stage separately reserves startup+source hashing+extraction+owned supervision+payload+failure+checkpoint/return/finalization and outer parent cost. Add shared sequential prerequisites, then compute the admitted dependency-graph critical path with resource/queue assumptions. No unused old balances or elapsed-as-CPU substitution.'}
