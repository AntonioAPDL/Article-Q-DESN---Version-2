"""New EE matched-seed scope; unchanged R150 mathematics/b6 lifecycle guard.

Importing this module is metadata only. The original completion contract is
an unchanged, pinned lifecycle dependency. No globals or old sources are patched.
"""
from __future__ import annotations
import fcntl
import math
import os
from pathlib import Path
import resource
import signal
import socket
import subprocess
import time
from pricefm_r155_completion_contract import (Lease as BaseLease,THREAD_ENV,all_processes,
    cpu_seconds,digest,finite_positive,fingerprint,immutable,load_module,peer_conflicts,
    physical_siblings,pin,pressure,process_identity,read,require,same_lifetime,
    sealed_packet,singleton_affinity,validate_resource_bounds,verify_hashes,verify_pin,
    funded_payload_CPU_limit)
from pricefm_r155_completion_inventory import A,B,MISSING,chunks,science,validate_row

ROOT=Path(__file__).resolve().parents[3]
BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021')
R155=BASE/'r155_screening_recovery_20261027'
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')


def source_identity(root=ROOT):
    def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
    require(not git('status','--porcelain'),'clean committed matched-seed execution source required')
    branch=git('branch','--show-current')
    require(branch.startswith('work/pricefm-r155-qualified-seeds-'),'dedicated new matched-seed source required')
    return dict(branch=branch,head=git('rev-parse','HEAD'))


def qualified_from_s0(losses):
    require(set(losses)=={'C0',A,B} and all(isinstance(v,(int,float)) and not isinstance(v,bool)
            and math.isfinite(v) and v>0 for v in losses.values()),'complete finite matched C0/A/B S0 required')
    margin=max(.10,.01*losses['C0'])
    gains={p:losses['C0']-losses[p] for p in (A,B)}
    qualified=[p for p in (A,B) if gains[p]>=.5*margin]
    return dict(practical_margin=margin,gains=gains,qualified=qualified,
                components=0 if not qualified else 6*(1+len(qualified)))


def names_for(qualified):
    require(qualified in ([],[A],[B],[A,B]),'only unchanged frozen A/B qualifier sets allowed')
    return [f'EE_{p}_s{s}_S_seed{k}' for p in (['C0']+qualified if qualified else [])
            for k in (1,2) for s in (1,2,3)]


def same_lock_free(global_contract,identity):
    path=Path(global_contract['lock_dir'])/'muscat_cpu30.lock'
    expected=lambda st:dict(device=st.st_dev,inode=st.st_ino)
    require(expected(path.stat())==identity,'original lock path device/inode replaced')
    with path.open('r+') as stream:
        require(expected(os.fstat(stream.fileno()))==identity,'opened original lock differs')
        try:fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return False
        require(expected(path.stat())==identity,'original lock changed while proving free')
        return True


def exact_unit_gone(unit,claim):
    properties=subprocess.check_output(['systemctl','--user','show',unit,
        '--property=Id,MainPID,InvocationID,ActiveState,Restart,NRestarts,KillMode'],text=True)
    actual=dict(line.split('=',1) for line in properties.splitlines() if '=' in line)
    require(actual.get('Id')==unit and actual.get('MainPID')=='0'
            and actual.get('ActiveState') in ('inactive','failed') and actual.get('Restart')=='no'
            and actual.get('NRestarts')=='0' and actual.get('KillMode')=='process'
            and actual.get('InvocationID')==claim['unit']['InvocationID'],'exact prior controller unit not naturally drained')
    return actual


def complete_initial(prep,analysis_seal=None,root_closing_proof=None):
    """Read the actual complete R155 output; no new array/model computation."""
    template=verify_pin(prep['initial_child_template']);endowment=verify_pin(prep['initial_endowment'])
    require(template['source']==prep['initial_source'] and template['max_new_tasks']==2
            and endowment['child_authority_template']==prep['initial_child_template'], 'original initial-scope binding differs')
    out=Path(template['output_dir']);actual=read(out/'authority.json')
    require(actual['LV_completed_drain_proof'] is not None
            and dict(template,LV_completed_drain_proof=actual['LV_completed_drain_proof'])==actual,
            'actual initial authority changed frozen scientific/source/budget fields')
    verify_pin(actual['LV_completed_drain_proof'])
    assessment=read(out/'assessment.json');seal=read(out/'assessment_seal.json')
    require(seal['assessment']==pin(out/'assessment.json') and seal['execution']==assessment['execution'],
            'complete initial assessment seal differs')
    execution=assessment['execution']
    require(execution['source']==prep['initial_source'] and execution['scope_id']==actual['scope_id']
            and execution['authority']==pin(out/'authority.json')
            and execution['composite_inventory']==prep['composite_inventory'], 'initial composite execution differs')
    require(assessment['full_D_components']==78 and assessment['new_D']==0 and assessment['new_S0']==2
            and assessment['new_component_names']==MISSING and assessment['new_chunks']==108
            and assessment['extra_seed_admitted'] is False and assessment['new_fits']==0
            and assessment['official_origins']==0,'exact complete original initial prefix required')
    nominees=verify_pin(prep['nominees'])
    require(assessment['nominees']=={k:nominees[k] for k in assessment['nominees']}
            and (nominees['A'],nominees['B'],nominees['full_D_complete'])==(A,B,78),
            'fixed complete-D nominees changed; re-nomination forbidden')
    decision=qualified_from_s0(assessment['matched_S0_AQL'])
    require(decision['qualified']==assessment['extra_seed_qualified']
            and decision['components']==assessment['conditional_extra_components']
            and math.isclose(decision['practical_margin'],assessment['practical_margin'],rel_tol=1e-11,abs_tol=1e-10)
            and all(math.isclose(v,assessment['matched_S0_gains'][p],rel_tol=1e-11,abs_tol=1e-10) for p,v in decision['gains'].items()),
            'unchanged S0 qualification rule differs')
    expected='COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED' if decision['qualified'] else 'COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER'
    require(assessment['status']==expected and read(out/'exit_receipt.json')['status']=='COMPLETE_INITIAL_PREFIX',
            'initial scientific disposition incomplete')
    supervisor=read(out/'supervisor_exit_receipt.json');claim=read(out/'claim.json')
    require(supervisor['child_exit_code']==0 and verify_pin(claim['authority'])==actual, 'initial worker/supervisor failed')
    # The old525controller spent its claim before scientific launch. Its stop
    # is retained as a paid administrative failure, never relabelled success.
    control_out=Path(endowment['output_dir']);control_claim=read(control_out/'claim.json');control_exit=read(control_out/'exit_receipt.json')
    require(control_exit['status']=='STOPPED_NO_RETRY' and control_exit['scientific_reaped_CPU_seconds']==0
            and control_exit['claims_and_failed_charges_retained'] is True
            and control_exit['source']==prep['initial_source']
            and control_claim['authority']==prep['initial_endowment'],'spent original525 administrative lineage differs')
    require(root_closing_proof is not None,'distinct root-reviewed actual initial524 closing proof required')
    closing=verify_pin(root_closing_proof)
    require(closing['schema']=='r155_root_initial_ee_closing_proof_v1' and closing['status']=='ROOT_REVIEWED_COMPLETE_AND_DRAINED'
            and closing['initial_child_template']==prep['initial_child_template']
            and closing['actual_child_authority']==claim['authority'] and closing['assessment']==pin(out/'assessment.json')
            and closing['supervisor_exit']==pin(out/'supervisor_exit_receipt.json')
            and closing['source']==prep['initial_source'] and closing['automatic_retry'] is False,
            'actual manually reviewed initial execution/closing lineage differs')
    actual_launch=verify_pin(closing['actual_launch_receipt'])
    require(actual_launch['source']==prep['initial_source'] and actual_launch['scientific_entry']==prep['initial_scientific_entry']
            and actual_launch['cwd']==prep['initial_source_root']
            and same_lifetime(actual_launch['process'],claim['process'])
            and actual_launch['process']['argv']==claim['process']['argv']
            and actual_launch['authority']==claim['authority'] and actual_launch['automatic_retry'] is False,
            'actual524 manual launch source/cwd/argv/lifetime differs')
    require(closing['previous_failed_525_claim']==pin(control_out/'claim.json')
            and closing['previous_failed_525_exit']==pin(control_out/'exit_receipt.json')
            and closing['previous_failed_525_charge_retained'] is True,
            'failed525 claim/charge cannot be erased/refunded')
    require(closing['reviewed_unit_and_drain_evidence'],'root-reviewed actual unit/drain evidence absent')
    for evidence in closing['reviewed_unit_and_drain_evidence']:verify_pin(evidence)
    # Missing transient unit identity is never an automatic fallback. A root
    # proof must explicitly name its accepted evidence/limitation. Fresh kernel
    # lifetimes and the same physical flock are mandatory in either case.
    require(closing['unit_evidence_mode'] in ('EXACT_LIVE_UNIT_TERMINAL_RECORD','ROOT_EXPLICIT_TRANSIENT_UNIT_AMENDMENT')
            and actual_launch['unit'] and actual_launch['invocation_id']
            and closing['unit']==actual_launch['unit'] and closing['invocation_id']==actual_launch['invocation_id'],
            'root-selected actual unit/evidence mode absent')
    if closing['unit_evidence_mode']=='ROOT_EXPLICIT_TRANSIENT_UNIT_AMENDMENT':
        amendment=verify_pin(closing['explicit_unit_amendment'])
        require(amendment['status']=='ROOT_ADMITTED' and amendment['historical_systemd_exit_code_proven'] is False
                and amendment['actual_initial_launch_receipt']==closing['actual_launch_receipt']
                and amendment['no_automatic_retry'] is True,'explicit truthful transient-unit limitation amendment absent')
    else:
        properties=subprocess.check_output(['systemctl','--user','show',closing['unit'],
            '--property=Id,MainPID,InvocationID,ActiveState,Restart,NRestarts,KillMode,Result,ExecMainStatus'],text=True)
        unit=dict(line.split('=',1) for line in properties.splitlines() if '=' in line)
        require(unit.get('Id')==closing['unit'] and unit.get('InvocationID')==closing['invocation_id']
                and unit.get('MainPID')=='0' and unit.get('ActiveState') in ('inactive','failed')
                and unit.get('Restart')=='no' and unit.get('NRestarts')=='0' and unit.get('KillMode')=='process'
                and unit.get('Result')=='success' and unit.get('ExecMainStatus')=='0',
                'exact actual initial numerical unit has not closed successfully')
    for life in (claim['process'],supervisor['parent'],supervisor['payload'],control_claim['process']):
        require(not same_lifetime(process_identity(life['pid']),life),'initial exact controller/guardian/payload still lives')
    glob=verify_pin(prep['global_contract'])
    require(same_lock_free(glob,prep['original_global_lock_identity']),'original numerical permit still held')
    analysis=None
    if analysis_seal is not None:
        independent=verify_pin(analysis_seal)
        require(independent['status']=='PASS','root-reviewed independent full-array analysis seal absent')
        analysis=verify_pin(independent['analysis'])
        require(analysis['status']=='PASS_COMPLETE_EE_SAVED_ARRAY_ANALYSIS'
                and analysis['independent_all78D_and9S0_array_arithmetic'] is True
                and analysis['completed_assessment']==pin(out/'assessment.json')
                and analysis['unchanged_rule_qualified']==decision['qualified']
                and analysis['prospective_extra_seed_components']==decision['components']
                and analysis['algorithmic_three_seed_stability_established'] is False,
                'independent complete87-component saved-array qualification differs')
        verify_hashes({v['path']:v['sha256'] for v in analysis['input_pins']})
        verify_hashes({analysis['analysis_source']['path']:analysis['analysis_source']['sha256']})
    return dict(assessment=pin(out/'assessment.json'),assessment_seal=pin(out/'assessment_seal.json'),
        authority=pin(out/'authority.json'),supervisor=pin(out/'supervisor_exit_receipt.json'),
        previous_failed_conditional_exit=pin(control_out/'exit_receipt.json'),physical_drain=True,
        root_actual_initial_closing_proof=root_closing_proof,actual_launch=closing['actual_launch_receipt'],
        source_preserving_composite_execution=execution,decision=decision,
        independent_analysis_seal=analysis_seal,analysis=analysis)


def validate_authority(a,prep,prep_path,identity,now,hostname):
    require(a.get('schema')=='r155_ee_qualified_seed_authority_v1' and a.get('status')=='ADMITTED',
            'distinct root numerical seed admission absent')
    require(isinstance(a.get('scope_id'),str) and len(a['scope_id'])==32
            and all(ch in '0123456789abcdef' for ch in a['scope_id']),'new exact UUID seed scope required')
    require(isinstance(a.get('independent_analysis_seal'),dict)
            and set(a['independent_analysis_seal'])>={'path','sha256'}
            and isinstance(a.get('initial_root_closing_proof'),dict)
            and set(a['initial_root_closing_proof'])>={'path','sha256'},
            'explicit full87-analysis and actual initial closing pins required before claim')
    require(a['source']==identity and prep['source']==identity and a['host']==hostname=='muscat'
            and a['preparation']==pin(prep_path),'actual matched-seed source/preparation/host differs')
    require(prep['schema']=='r155_ee_qualified_seed_preparation_v1' and a['study']==prep['study']=='EE', 'seed study schema differs')
    verify_hashes(prep['execution_source_sha256'])
    require(a['nonrenewing'] is True and a['automatic_retry'] is False and a['new_fits']==0
            and a['official_origins']==0 and a['allow_extra_seeds'] is True
            and a['allowed_seed_indices']==[1,2] and a['new_seed0_components']==0,
            'exact seed1/2-only zero-fit scope required')
    for name in ('start_epoch','expires_epoch','max_wall_seconds','max_execution_wall_seconds','full_prefix_CPU',
                 'replacement_CPU','admin_drain_CPU','total_CPU_cap','min_delivered_share','own_RSS_soft_GiB',
                 'minimum_available_RAM_GiB','minimum_free_disk_GiB','new_output_soft_GiB','drain_seconds','maximum_atomic_wall_seconds'):
        finite_positive(a[name],name)
    require(a['start_epoch']<=now<a['expires_epoch'] and a['expires_epoch']-a['start_epoch']<=a['max_wall_seconds']
            and a['max_execution_wall_seconds']<=a['max_wall_seconds'],'finite new seed clock invalid')
    require(a['global_contract']==prep['global_contract'] and a['original_global_lock_identity']==prep['original_global_lock_identity']
            ==dict(device=2304,inode=59124844),'original global contract/inode differs')
    glob=verify_pin(a['global_contract']);policy=verify_pin(a['resource_policy'])
    validate_resource_bounds(a,glob,policy,now)
    require(a['cpu']==30 and a['physical_sibling_cpus']==sorted(physical_siblings(30))==[30,62]
            and a['permit_id']=='muscat_cpu30' and glob['max_new_numerical']==1,
            'same sole physical permit required')
    for key in ('peer_census','admin_rules','process_classifier_proof','source_review','pricing_evidence'):
        verify_pin(a[key])
    review=verify_pin(a['source_review'])
    require(review.get('source')==identity and str(review.get('status','')).startswith('PASS'),
            'new actual seed source needs its own passed source review')
    price=verify_pin(a['pricing_evidence'])
    require(price==verify_pin(prep['pricing']) and price['status']=='COMPLETE_INITIAL_S0_TIMING_PRICE_NOT_ADMISSION',
            'whole-prefix price must include complete initial S0 timings')
    gate=complete_initial(prep,a['independent_analysis_seal'],a['initial_root_closing_proof'])
    qualified=gate['decision']['qualified'];names=names_for(qualified)
    require(qualified and qualified==a['qualified_packages'] and names==a['required_task_names']
            and len(names)==a['max_new_tasks'] in (12,18),'no qualifier or partial/unqualified matched set')
    scenario=price['scenarios']['+'.join(qualified)]
    require(a['full_prefix_CPU']>=scenario['full_prefix_CPU'] and a['replacement_CPU']>=scenario['replacement_CPU']
            and a['admin_drain_CPU']>=scenario['admin_drain_CPU'] and a['guardian_CPU_reserve']>=scenario['guardian_CPU_reserve'],
            'undiscounted whole-prefix/replacement/guardian price not funded')
    prior=a['prior_CPU_charged_seconds']
    require(isinstance(prior,(int,float)) and not isinstance(prior,bool) and math.isfinite(prior) and prior>=0
            and prior+a['full_prefix_CPU']+a['replacement_CPU']+a['admin_drain_CPU']<=a['total_CPU_cap'],
            'explicit prior/full-prefix/reserves exceed total cap')
    require(a['peer_census_cadence_seconds']==5 and isinstance(a['guardian_CPU_reserve'],int)
            and 1<=a['guardian_CPU_reserve']<a['admin_drain_CPU'] and a['hard_cgroup_isolation_claimed'] is False,
            'strict peer cadence or honest funded lifecycle differs')
    require(0<a['min_delivered_share']<=.5,'unproved optimistic delivered share forbidden')
    required=(a['full_prefix_CPU']+a['replacement_CPU']+a['admin_drain_CPU'])/a['min_delivered_share']+a['drain_seconds']+a['maximum_atomic_wall_seconds']
    require(a['expires_epoch']-now>=required and a['max_execution_wall_seconds']>=required,
            'whole matched set does not fit active/absolute calendar')
    require(Path(a['output_dir']).parent==DATA/'campaigns'
            and Path(a['output_dir']).name=='pricefm_stage_r155_ee_qualified_seeds_'+a['scope_id'],
            'new seed namespace required')
    require(not (Path(a['output_dir'])/'claim.json').exists(),'seed claim spent; no retry')
    # Every original source/input/parent/RNG descriptor remains immutable.
    old=verify_pin(prep['original_preparation']);verify_hashes(old['source_sha256']);verify_hashes(old['input_sha256'])
    by_name={t['name']:t for t in old['tasks']}
    for name in names:
        task=next(t for t in prep['tasks'] if t['name']==name)
        require(task==by_name[name] and task['reuse'] is None and task['mode']=='S'
                and task['seed_index'] in (1,2),'original seed task changed or old output credit introduced')
        verify_hashes(task['parent_input_sha256']);verify_hashes({task['scaler_path']:task['scaler_sha256'],task['bank']['path']:task['bank']['sha256']})
    return gate


class SeedLease(BaseLease):
    """New truthful claim, unchanged b6 held-child/peer/accounting machinery."""
    def __init__(self,a,prep,authority_path):
        self.a,self.prep=a,prep;self.out=Path(a['output_dir']);self.out.mkdir(parents=True,exist_ok=True)
        self.started=time.monotonic();self.cpu0=cpu_seconds();self.own=process_identity(os.getpid())
        require(self.own is not None,'own seed lifetime unavailable')
        self.guardian=None;self.reserve_total=0.0;self._peer_at=0.;self._pressure_at=0.;self._heartbeat_at=0.
        self._pressure={};self._written={};self._written_total=0
        self.census=read(a['peer_census']['path']);self.admin_rules=read(a['admin_rules']['path'])
        self.lock=(self.out/'scope.lock').open('a+');fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        glob=read(a['global_contract']['path']);path=Path(glob['lock_dir'])/(a['permit_id']+'.lock');self.global_lock_path=path
        identity=lambda st:dict(device=st.st_dev,inode=st.st_ino)
        require(identity(path.stat())==a['original_global_lock_identity'],'original physical lock replaced')
        self.permit_lock=path.open('r+');require(identity(os.fstat(self.permit_lock.fileno()))==a['original_global_lock_identity'],'opened lock inode differs')
        fcntl.flock(self.permit_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        require(identity(path.stat())==a['original_global_lock_identity'],'lock path changed during acquisition')
        self.scan_peers('before_seed_claim',{os.getpid()});self._peer_at=time.monotonic()
        require(not (self.out/'claim.json').exists(),'seed claim spent; no retry')
        immutable(self.out/'claim.json',dict(schema='r155_ee_qualified_seed_claim_v1',authority=pin(authority_path),
            permit_id=a['permit_id'],scope_id=a['scope_id'],study='EE_MATCHED_SEED1_2',process=self.own,
            required_tasks=a['required_task_names'],output_dir=str(self.out),started_epoch=time.time(),new_fits=0,official_origins=0))
        os.sched_setaffinity(0,{a['cpu']});singleton_affinity(os.sched_getaffinity(0),a['cpu'])
        policy={'SCHED_OTHER':os.SCHED_OTHER,'SCHED_IDLE':os.SCHED_IDLE}
        os.sched_setscheduler(0,policy[a['scheduler_policy']],os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,a['nice'])
        require(os.sched_getscheduler(0)==policy[a['scheduler_policy']] and os.getpriority(os.PRIO_PROCESS,0)==a['nice'],'actual seed scheduler/nice differs')
        subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
        require(subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'),'actual seed idle IO differs')
        for name in THREAD_ENV:require(os.environ.get(name)=='1','single-thread environment differs: '+name)
        usage=resource.getrusage(resource.RUSAGE_SELF);inherited=resource.getrlimit(resource.RLIMIT_CPU)[1]
        hard=funded_payload_CPU_limit(usage.ru_utime+usage.ru_stime,a['total_CPU_cap'],a['prior_CPU_charged_seconds'],a['guardian_CPU_reserve'],inherited)
        resource.setrlimit(resource.RLIMIT_CPU,(hard,hard));self._start_guardian()
        try:self.check(refresh_output=True)
        except BaseException as exc:self.close('INCOMPLETE',dict(stage='seed_bootstrap',message=str(exc)));raise
