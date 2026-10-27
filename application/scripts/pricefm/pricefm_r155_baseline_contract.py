"""New baseline-administration scope; unchanged numerical producers and fits.

This module imports only the standard library and the frozen administrative
observer. It neither launches work nor changes any live process or old record.
"""
from __future__ import annotations
import hashlib
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3]
OLD_ROOT=ROOT.parent/'pricefm_r153_control_lifecycle_20261025'
OLD_ENTRY=OLD_ROOT/'application/scripts/pricefm/513_supervise_pricefm_stage_r153_baseline.py'
OLD_ENTRY_SHA='467f69bc2c7cd6334e5fd9eecc8eecda60ac85efa9af6cedcbb02bba7b317444'
DATA=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
OLD_AUTHORITY=DATA/'launch_prep/pricefm_stage_r153_control_lifecycle_20261025/baseline/authority.json'
BRANCH='work/pricefm-r155-baseline-owner6-20261027'
ORIGINAL_START=1792970252.3571737
ORIGINAL_EXPIRY=1793575052.3571737
ORIGINAL_CPU=28800.
PRIOR_CONTROL_CPU=3911.9249712769997
ACTIVATION=dict(legacy_generations_spent=5,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=6)
OWNER5_FIXED_PAID_CPU=5381.924971277
OWNER6_PRIOR_CPU=5621.924971277
OWNER5_AUTHORITY_SHA='3fb27b48c10f69c1e3e1a6ac6605572432296819cd505bb5cef94dcb4b189be4'
OWNER5_FAILURE_KERNEL_REVIEW_SHA='d17b738aad47b81b9bbd0ec16e7b2cb98957c5b89ee7a2dccd3591b6d23ac1e2'


def require(value,message):
    if not value:raise RuntimeError(message)


PUBLICATION_OBSERVATIONS=[]


class PublicationPending(RuntimeError):
    def __init__(self,path,observations):
        self.observation=dict(path=str(path),status='BOUNDED_METADATA_PUBLICATION_INCOMPLETE',attempts=observations)
        super().__init__('bounded new-runtime metadata publication is incomplete: '+str(path))


class _PublicationChanged(RuntimeError):pass


def read_published(path,deadline=None,max_wait_seconds=2.):
    """Retry only missing/partial/changing metadata, never semantic mismatches."""
    path=Path(path);end=time.monotonic()+max_wait_seconds
    if deadline is not None:end=min(end,deadline)
    attempts=[]
    while True:
        try:
            raw=path.read_bytes();value=json.loads(raw);closing=path.read_bytes()
            if hashlib.sha256(raw).digest()!=hashlib.sha256(closing).digest():raise _PublicationChanged('metadata bytes changed across read')
            return value
        except (FileNotFoundError,json.JSONDecodeError,_PublicationChanged) as exc:
            observation=dict(path=str(path),epoch=time.time(),error=type(exc).__name__,detail=str(exc))
            attempts.append(observation);attempts=attempts[-16:]
            PUBLICATION_OBSERVATIONS.append(observation);del PUBLICATION_OBSERVATIONS[:-128]
            if time.monotonic()>=end:raise PublicationPending(path,attempts) from exc
            time.sleep(min(.01,max(0.,end-time.monotonic())))


def read(path):
    if str(Path(path)).startswith(str(DATA/'launch_prep/pricefm_stage_r155_baseline_continuation_')):
        return read_published(path)
    return json.loads(Path(path).read_text())


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):h.update(block)
    return h.hexdigest()


def pin(path):return dict(path=str(path),sha256=digest(path))


def verify_pin(value):
    require(pin(value['path'])==value,'pinned metadata/source bytes differ: '+str(value['path']))
    return read(value['path'])


require(digest(OLD_ENTRY)==OLD_ENTRY_SHA,'original baseline administrative dependency differs')
ADMIN_DEPENDENCIES={
    str(ROOT.parent/'pricefm_r152_parallel_20261024/application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'):'85040c4a9618ea2caee048decdcd0eea8c6c6218972af9adbecf7dec7b752250',
    str(ROOT.parent/'pricefm_r152_parent_recovery_20261024/application/scripts/pricefm/511_recover_pricefm_stage_r152_baseline_owner.py'):'fbd6ac6b01be81e8f975d07150fe15651cf62cdf73c47032f11c8a5ae208a214',
    str(ROOT.parent/'pricefm_r152_parent_recovery_20261024/application/scripts/pricefm/512_release_pricefm_stage_r152_baseline_owner.py'):'5a7234abcb9dfdedca221500994fe3da6b4e0d1345954107ca580f3460bba8a0'}
for _path,_sha in ADMIN_DEPENDENCIES.items():require(digest(_path)==_sha,'original transitive administration changed: '+_path)
_spec=importlib.util.spec_from_file_location('r155_frozen_r153_administration',OLD_ENTRY)
old=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(old)
core=old.core


class CensusDeferred(RuntimeError):
    """Typed prohibition of every new scientific dispatch until reconciliation."""
    def __init__(self,observation):
        self.observation=observation
        super().__init__('DEFER_ALL_NEW_DISPATCH: full own-UID census is incomplete')


def partial_identity(system,path,error,pre_read_anchor=None):
    """Persist readable anchors and explicit unknowns without inventing a role."""
    pid=int(path.name);value=dict(pid=pid,boot_id=system.boot_id,epoch=time.time(),
        error=type(error).__name__+': '+str(error),unavailable_fields=[],ownership_assumed=False,
        census_pre_read_stat=pre_read_anchor)
    readers=dict(stat=lambda:system.stat_sample(pid),directory_uid=lambda:path.stat().st_uid,
        status=lambda:(path/'status').read_text(),comm=lambda:(path/'comm').read_text().strip(),
        argv=lambda:[v.decode(errors='replace') for v in (path/'cmdline').read_bytes().split(b'\0') if v],
        cwd=lambda:os.readlink(path/'cwd'),executable=lambda:os.readlink(path/'exe'),
        cmdline_file_uid=lambda:(path/'cmdline').stat().st_uid,cwd_link_uid=lambda:(path/'cwd').lstat().st_uid,
        threads=lambda:[dict(tid=int(p.name),cpus=sorted(os.sched_getaffinity(int(p.name)))) for p in (path/'task').iterdir()])
    for name,reader in readers.items():
        try:value[name]=reader()
        except (OSError,ValueError,RuntimeError) as exc:
            value[name]=None;value['unavailable_fields'].append(dict(field=name,error=type(exc).__name__))
    # Status may contain fields beyond the required UID/PID anchors. Retain only
    # those explicit anchors, never environment contents or inferred ownership.
    if value.get('status') is not None:
        status=dict(line.split(':',1) for line in value['status'].splitlines() if ':' in line)
        value['status']={k:status.get(k,'').strip() for k in ('Name','State','Pid','PPid','Uid','Gid')}
    try:value['final_stat']=system.stat_sample(pid)
    except (OSError,ValueError,RuntimeError) as exc:
        value['final_stat']=None;value['unavailable_fields'].append(dict(field='final_stat',error=type(exc).__name__))
    samples=[pre_read_anchor,value.get('stat'),value['final_stat']]
    if any(s is None for s in samples):value['observation_lifetime']='UNAVAILABLE'
    elif len({(s['pid'],s['start_ticks']) for s in samples})!=1:value['observation_lifetime']='MIXED_OR_CHANGED_LIFETIME'
    else:value['observation_lifetime']='SAME_LIFETIME_SEQUENTIAL_METADATA_NOT_ATOMIC'
    value['protected_predicate_observations']={name:None if value.get(name) is None else value[name]!=os.getuid()
        for name in ('cmdline_file_uid','cwd_link_uid')}
    value['failure_time_role_or_cause_inferred']=False
    return value


def collect_census(system,paths=None):
    paths=list(Path('/proc').iterdir()) if paths is None else list(paths)
    paths=[p for p in paths if p.name.isdigit()];rows=[];unknown=[];started=time.monotonic();cpu0=time.process_time();scanned=0
    for index,path in enumerate(paths):
        if time.monotonic()-started>=5 or time.process_time()-cpu0>=2:
            unknown.append(dict(pid=None,error='BOUNDED_CENSUS_OBSERVATION_LIMIT_REACHED',
                unobserved_process_count=len(paths)-index,unavailable_fields=['remaining_census_members'],ownership_assumed=False))
            break
        anchor=None
        try:
            anchor=system.stat_sample(int(path.name))
            row=system.census_process(path)
            if row is not None:rows.append(row)
        except (OSError,ValueError,RuntimeError) as exc:
            # A protected/unstable own-UID process is never silently omitted.
            # Even if a subsequent stat says gone, retain the unresolved scan;
            # a later full scan must establish a clean reconciliation boundary.
            unknown.append(partial_identity(system,path,exc,anchor))
        scanned+=1
    try:namespace=os.readlink('/proc/self/ns/pid')
    except OSError:namespace=None
    expected=getattr(system,'expected_pid_namespace',None)
    host_view=bool(expected and namespace==expected and len(paths)>=100)
    evidence=dict(schema='r155_baseline_census_v1',epoch=time.time(),host=os.uname().nodename,
        observer_PID=os.getpid(),observer_UID=os.getuid(),pid_namespace=namespace,
        expected_pid_namespace=expected,total_visible_processes=len(paths),own_UID_readable_processes=len(rows),
        scanned_processes=scanned,scan_entry_budget_wall_seconds=5,scan_entry_budget_own_CPU_seconds=2,
        budget_checked_before_each_process=True,individual_read_uses_frozen_bounded_retry=True,hard_preemption_claimed=False,
        wall_seconds=time.monotonic()-started,own_CPU_seconds=time.process_time()-cpu0,
        full_host_view_verified=host_view,unresolved=unknown,complete=host_view and not unknown,
        action='RECONCILE_BEFORE_DISPATCH' if host_view and not unknown else 'DEFER_ALL_NEW_DISPATCH',
        unknown_or_unreadable_processes_ignored=False,numerical_worker_signals=0)
    return rows,evidence


class System(old.System):
    def __init__(self,expected_pid_namespace=None):
        super().__init__();self.expected_pid_namespace=expected_pid_namespace;self.last_census=None

    def process(self,pid):
        anchor=None
        try:
            anchor=self.stat_sample(pid)
            return super().process(pid)
        except OSError as exc:
            evidence=dict(schema='r155_baseline_direct_identity_defer_v1',epoch=time.time(),complete=False,
                action='DEFER_ALL_NEW_DISPATCH',unresolved=[partial_identity(self,Path('/proc')/str(pid),exc,anchor)],
                unknown_or_unreadable_processes_ignored=False,numerical_worker_signals=0)
            self.last_census=evidence;raise CensusDeferred(evidence) from exc

    def processes(self):
        rows,evidence=collect_census(self);self.last_census=evidence
        if not evidence['complete']:raise CensusDeferred(evidence)
        return rows

    def unit(self,name):
        fields=list(dict.fromkeys(core().PROPERTIES+['CPUAccounting','MemoryAccounting','RuntimeMaxUSec',
            'ExecMainPID','ExecMainStatus','ExecMainCode','RemainAfterExit','Nice','CPUSchedulingPolicy',
            'IOSchedulingClass','LimitCPU','LimitCPUSoft']))
        run=subprocess.run(['systemctl','--user','show',name,'--property='+','.join(fields)],text=True,capture_output=True,timeout=10)
        value=dict(line.split('=',1) for line in run.stdout.splitlines() if '=' in line)
        require(run.returncode==0 or value.get('LoadState')=='not-found','explicit control unit read unavailable')
        return value


def finite_json(value):
    if isinstance(value,float):return math.isfinite(value)
    if isinstance(value,dict):return all(finite_json(v) for v in value.values())
    if isinstance(value,list):return all(finite_json(v) for v in value)
    return True


def precision_rhs_exclusion(task,terminal):
    """Typed finite screening exclusion; never a certificate or required-fit waiver."""
    if task.get('kind')!='rhs' or terminal.get('termination_reason')!='gaussian_conditional_accuracy_rejected':return False
    accuracy=terminal.get('precision_accuracy',{})
    require(isinstance(accuracy,dict),'RHS precision diagnostic is not structured metadata')
    maximum=accuracy.get('maximum_inverse_residual');tolerance=accuracy.get('tolerance')
    require(finite_json(terminal) and terminal.get('status')=='R123_SUCCESSOR_UNCERTIFIED'
        and terminal.get('iterations')==2000 and terminal.get('full_variational_certified') is False
        and terminal.get('initialization_only') is True and terminal.get('test_opened') is False
        and terminal.get('official_validation_opened') is False and accuracy.get('accepted') is False
        and accuracy.get('jitter')==0 and not isinstance(accuracy.get('jitter'),bool)
        and isinstance(maximum,(int,float)) and not isinstance(maximum,bool)
        and isinstance(tolerance,(int,float)) and not isinstance(tolerance,bool)
        and tolerance==1e-5 and maximum>tolerance,
        'RHS precision exclusion lacks finite original-threshold false-certificate evidence')
    return True


def failed_certificates(config,region,diagnostics=None):
    """Preserve exact seals/contracts, adding only finite RHS precision rejection."""
    folder=core().campaign(config,region);policy=old.ContractPolicy(config,None);prep=None;blockers=[];screened=[]
    for path in sorted((folder/'tasks_done').glob('*')):
        seal_path=path/'completed_evidence.json'
        if not seal_path.is_file() or read(seal_path).get('metadata',{}).get('certified') is not False:continue
        seal=core().verify_packet(path);task_path=folder/'tasks'/(path.name+'.json');task=read(task_path)
        terminal_path=path/'fit/terminal.json';contract_path=folder/'contracts'/(path.name+'.json')
        require(seal.get('metadata',{}).get('source_head')==config['source_head']
            and seal['metadata'].get('task_sha256')==digest(task_path) and terminal_path.is_file()
            and task.get('region')==region and task.get('name')==path.name,'unclassified failed scientific packet/source/task')
        terminal=read(terminal_path)
        require(terminal.get('contract_path')==str(contract_path) and terminal.get('contract_sha256')==digest(contract_path),
            'failed scientific packet contract differs')
        if prep is None:prep=policy.preparation(region)
        require(read(contract_path)==policy.expected_contract(prep,task,{'region':region}),
            'failed fit is outside its exact frozen producer contract')
        record=dict(task=path.name,kind=task['kind'],completed_evidence_sha256=digest(seal_path),
            terminal_sha256=digest(terminal_path),task_sha256=digest(task_path),contract_sha256=digest(contract_path))
        if precision_rhs_exclusion(task,terminal):
            require(set(seal['artifacts'])=={'fit/beta_cov.bin','fit/beta_mean.bin','fit/convergence_trace.csv',
                'fit/fit.rds','fit/fit_summary.json','fit/terminal.json','result.json'},'precision RHS seal must cover all seven original artifacts')
            require(finite_json(read(path/'fit/fit_summary.json')) and finite_json(read(path/'result.json')),
                'RHS precision exclusion has nonfinite saved scalar metadata')
            record.update(subtype='FINITE_UNCERTIFIED_RHS_GAUSSIAN_PRECISION_EXCLUSION',certified=False,
                accuracy=terminal['precision_accuracy'],retry_admitted=False,threshold_changed=False)
            screened.append(record);continue
        if task['kind'] in {'rhs','normal_full'}:
            require(terminal.get('status')=='R123_SUCCESSOR_UNCERTIFIED' and terminal.get('iterations')==2000
                and terminal.get('termination_reason')=='iteration_cap' and terminal.get('full_variational_certified') is False
                and terminal.get('test_opened') is False and terminal.get('official_validation_opened') is False
                and terminal.get('initialization_only') is True,'Normal exclusion is not finite original-cap evidence')
            (screened if task['kind']=='rhs' else blockers).append(record)
        elif task['kind'] in {'al','internal_al'}:
            require(terminal.get('finite_core') is True and terminal.get('iterations')==300
                and terminal.get('computationally_certified') is False and terminal.get('termination')=='iteration_cap_uncertified'
                and terminal.get('test_opened') is False,'AL blocker is not finite original-cap evidence')
            blockers.append(record)
        else:raise RuntimeError('unknown false scientific task kind cannot be waived')
    if diagnostics is not None:diagnostics['preserved_RHS_screening_exclusions']=screened
    return blockers


def runtime_files():
    return [Path(__file__).with_name(name) for name in ('pricefm_r155_baseline_contract.py',
        '530_supervise_pricefm_stage_r155_baseline_continuation.py','531_prepare_pricefm_stage_r155_baseline_continuation.py',
        '532_activate_pricefm_stage_r155_baseline_continuation.py','533_inspect_pricefm_stage_r155_baseline_continuation.py',
        '534_materialize_pricefm_stage_r155_baseline_owner6.py')]


def source_identity(remote=False):
    def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,timeout=20).strip()
    require(git('branch','--show-current')==BRANCH and not git('status','--porcelain'),'clean committed new baseline source required')
    value=dict(root=str(ROOT),branch=BRANCH,head=git('rev-parse','HEAD'),
        runtime_sha256={str(p.relative_to(ROOT)):digest(p) for p in runtime_files()})
    if remote:
        require(git('remote','get-url','origin')=='git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git','untrusted publication origin')
        line=git('ls-remote','--heads','origin','refs/heads/'+BRANCH)
        require(line and line.split()[0]==value['head'],'fresh published baseline feature head differs')
    return value


def check_pins(pins):
    for path,sha in pins.items():require(digest(path)==sha,'frozen administrative/scientific input changed: '+path)


def verify_source(source,remote=False):
    require(source_identity(remote)==source,'truthful new baseline control source differs')


def intent(unit,mode,authority_path):
    return dict(unit=unit,mode=mode,administrative_cpu=31,unit_nice=0,kernel_nice=0 if mode=='run' else 10,
        scheduler_policy='SCHED_OTHER',io_class=3,CPU_hard_limit='infinity' if mode=='run' else 600,
        argv=[str(DATA/'runtime_envs/r137_py311/bin/python'),'-B',
        str(Path(__file__).with_name('530_supervise_pricefm_stage_r155_baseline_continuation.py')),
        mode,'--authority',str(authority_path),'--unit',unit])


def verify_guardian_priority_proof(value):
    proof=verify_pin(value)
    require(proof['schema']=='r155_two_strategy_private_nice_proof_v1'
        and proof['status']=='PASS_TWO_FINITE_METADATA_UNITS_NO_NUMERICAL_CALLS'
        and proof['source']['sha256']=='cf9c58654f3150e269c09fd45c2b6ca787acebf1209dcba9cdd05177adb064a1'
        and pin(proof['source']['path'])==proof['source'] and proof['actual_host_pid_namespace']=='pid:[4026531836]'
        and proof['requested10_kernel_nice']==0 and proof['explicit_unit0_self10_kernel_nice']==10
        and proof['all_exact_fixture_processes_exited_naturally'] is True and proof['foreign_process_signals']==0
        and proof['baseline_activations']==0 and proof['numerical_calls']==0,'exact installed-host two-strategy priority proof required')
    for strategy,unit_nice,kernel_nice in (('requested10',10,0),('explicit10',0,10)):
        row=proof['outcomes'][strategy];before=row['before']['process'];ready=row['ready']['process'];unit=row['retained_unit']
        require(before['pid']==ready['pid']==int(unit['ExecMainPID']) and before['start_ticks']==ready['start_ticks']
            and ready['boot_id']=='37b80e3b-9596-4c75-85e1-aca85af8fa7f' and ready['nice']==kernel_nice
            and ready['cpus']==[31] and ready['scheduler']==os.SCHED_OTHER
            and ('\nNice='+str(unit_nice)+'\n') in row['literal_fragment'] and unit['Nice']=='0'
            and unit['MainPID']=='0' and unit['SubState']=='exited' and unit['ExecMainStatus']=='0'
            and unit['Restart']=='no' and unit['NRestarts']=='0','two-strategy source/kernel/unit priority facts differ')
    return proof


def establish_guardian_priority():
    """Only this new administrative guardian changes its own kernel priority."""
    before=os.getpriority(os.PRIO_PROCESS,0)
    require(before in (0,10) and os.sched_getaffinity(0)=={31} and os.sched_getscheduler(0)==os.SCHED_OTHER,
        'guardian own-process startup scheduling differs')
    os.setpriority(os.PRIO_PROCESS,0,10)
    after=os.getpriority(os.PRIO_PROCESS,0)
    require(after==10,'guardian own-process kernelNice10 setup failed')
    return dict(pid=os.getpid(),before_kernel_nice=before,after_kernel_nice=after,unit_requested_nice=0,
        target='this guardian process only',foreign_process_changes=0,affinity=[31],scheduler='SCHED_OTHER',epoch=time.time())


def verify_predecessor(authority,system,require_full_census=False):
    prior=verify_pin(authority['predecessor_authority']);state=verify_pin(authority['predecessor_state'])
    if 'predecessor_state_original' in authority:
        require(verify_pin(authority['predecessor_state_original'])==state,
            'original fourth-owner state changed after archival')
    require(prior['activation']==dict(legacy_generations_spent=3,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=4)
        and state['activation']==prior['activation'] and state['phase']=='blocked'
        and state['control_budget']['cumulative_control_charged_CPU_seconds']==PRIOR_CONTROL_CPU,
        'exact spent fourth-owner state/charge differs')
    for relative,sha in prior['execution_source']['runtime_sha256'].items():
        require(digest(Path(prior['execution_source']['root'])/relative)==sha,'original R153 source changed')
    check_pins(ADMIN_DEPENDENCIES)
    attestation=verify_pin(authority['predecessor_attestation'])
    require(attestation['authority_sha256']==authority['predecessor_authority']['sha256']
        and attestation['source']==prior['execution_source'],'original fourth-owner attestation differs')
    for label in ('owner','guardian'):
        life=attestation[label]['process'];current=system.process(life['pid'])
        require(not core().same_process(current,life),'spent original administrative lifetime still lives: '+label)
    owner=system.unit(prior['new_unit']);guardian=system.unit(prior['guardian_unit'])
    require(owner.get('Id')==prior['new_unit'] and owner.get('LoadState')=='loaded' and owner.get('MainPID')=='0'
        and owner.get('ActiveState')=='failed' and owner.get('Result')=='exit-code' and owner.get('ExecMainStatus')=='1'
        and owner.get('ExecMainPID')==str(attestation['owner']['process']['pid'])
        and owner.get('InvocationID')==attestation['owner']['unit_properties']['InvocationID']
        and owner.get('Restart')=='no' and owner.get('NRestarts')=='0' and owner.get('KillMode')=='process',
        'original failed owner unit/invocation changed')
    require(guardian.get('MainPID')=='0' and guardian.get('ActiveState') not in ('active','activating'),
        'original guardian is not currently absent/inactive')
    # Its unloaded unit has no durable historical exit result. The old owner
    # cgroup deliberately retains original scientific sessions and is not drained.
    old.frozen_context(prior,authority['predecessor_authority']['path'])
    census=system.processes() if require_full_census else None
    spent_owner5=verify_spent_owner5(authority,system)
    return dict(authority=prior,state=state,attestation=attestation,old_owner_unit=owner,
        old_guardian_unit=guardian,guardian_historical_exit='UNKNOWN_NOT_INFERRED_FROM_UNLOADED_DEFAULTS',
        spent_owner5=spent_owner5,census=census)


def verify_spent_owner5(authority,system):
    """Retain failed5 separately; scientific state is still the original owner4."""
    binding=authority['spent_owner5'];old5=verify_pin(binding['authority']);failure=verify_pin(binding['activation_failure'])
    claim=verify_pin(binding['activation_claim']);execution=verify_pin(binding['materializer_receipt'])
    review=verify_pin(binding['actual_failure_kernel_review']);ledger=verify_pin(authority['paid_scope_ledger'])
    require(binding['authority']['sha256']==OWNER5_AUTHORITY_SHA
        and binding['actual_failure_kernel_review']['sha256']==OWNER5_FAILURE_KERNEL_REVIEW_SHA,
        'the exact admitted owner5 authority and actual failure review are required')
    require(authority['historical_owner5_start_ticks_unavailable_acknowledged'] is True,
        'root acknowledgement of unavailable historical owner5 kernel anchors required')
    require(old5['activation']==dict(legacy_generations_spent=4,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=5)
        and old5['authority_id']=='7a16315cdb234785970c9d608a34d501' and old5['status']=='ADMITTED'
        and old5['execution_source']['head']=='7fb9d80874f61caced6ba8e888cb2b271f413c75',
        'exact spent owner5 authority/source differs')
    require(failure['activation_spent'] is True and failure['automatic_retry'] is False
        and failure['authority']==binding['authority'] and claim['authority']==binding['authority']
        and execution['status']=='FAILED_ONCE_NO_RETRY' and execution['actual_authority']==binding['authority']
        and failure['error']=="RuntimeError('actual new control lifetime/unit/cwd/argv/scheduling differs: guardian')",
        'owner5 once-only failure/claim graph differs')
    require(old5['grant']['prior_control_CPU_seconds']+old5['guardian_CPU_reserve']+100==OWNER5_FIXED_PAID_CPU
        and ledger['retained_owner5_fixed_paid_CPU']==OWNER5_FIXED_PAID_CPU
        and ledger['new_failure_inspection_CPU_debit']==10 and ledger['new_preparation_CPU_debit']==200
        and ledger['new_activation_wrapper_CPU_reserve']==30 and ledger['new_prior_control_CPU']==OWNER6_PRIOR_CPU,
        'owner5 retained fixed price or new paid ledger differs')
    require(ledger['no_unused_old_reserve_credit'] is True and ledger['owner5_terminal_wall_upper_bound_CPU']<100,
        'spent owner5 tail is not conservatively funded')
    for relative,sha in old5['execution_source']['runtime_sha256'].items():
        require(digest(Path(old5['execution_source']['root'])/relative)==sha,'frozen failed owner5 source changed')
    observed=[]
    for item in review['units']:
        expected=item['properties'];name=item['unit'];props=system.unit(name);pid=int(expected['ExecMainPID'])
        require(name in (old5['new_unit'],old5['guardian_unit']) and props.get('Id')==name
            and props.get('LoadState')=='loaded' and props.get('ActiveState')=='failed' and props.get('SubState')=='failed'
            and props.get('MainPID')=='0' and props.get('ExecMainPID')==str(pid) and props.get('ExecMainStatus')=='1'
            and props.get('Result')=='exit-code' and props.get('InvocationID')==expected['InvocationID']
            and props.get('Restart')=='no' and props.get('NRestarts')=='0' and props.get('KillMode')=='process'
            and props.get('RemainAfterExit')=='yes' and props.get('ExecStart')==expected['ExecStart'],
            'spent owner5 retained failed unit/invocation differs')
        # No failure-time /proc start anchor was saved. Require the recorded
        # ExecMainPID entirely absent; never infer a reused PID's old lifetime.
        require(system.process(pid) is None,'spent owner5 PID present; unknown/reused lifetime cannot be waived')
        observed.append(dict(unit=name,properties=props,ExecMainPID=pid,current_process_absent=True,
            historical_process_start_ticks='UNKNOWN_NOT_FABRICATED'))
    require(len(observed)==2 and len({row['unit'] for row in observed})==2,'both exact failed owner5 units required')
    runtime=Path(old5['runtime'])
    require(all(not (runtime/name).exists() for name in ('launch_attestation.json','ready.json','state.json',
        'resource_ownership_epoch.json','registration.json','activation_verified.json','guardian_heartbeat.json')),
        'owner5 bootstrap/adoption history changed')
    return dict(authority=binding['authority'],failure=binding['activation_failure'],units=observed,
        paid_CPU_retained=OWNER5_FIXED_PAID_CPU,scientific_predecessor='unchanged owner4 state',no_retry=True)


def verify_original_locks(authority,require_free=False):
    for expected in authority['original_dispatch_locks']:
        path=Path(expected['path']);require(not path.is_symlink(),'dispatch lock is a symlink')
        def matches(st):return (st.st_dev,st.st_ino)==(expected['device'],expected['inode'])
        require(matches(path.stat()),'original dispatch lock path was replaced')
        with path.open('r+') as stream:
            require(matches(os.fstat(stream.fileno())),'opened original dispatch lock differs')
            if require_free:fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
            require(matches(path.stat()),'dispatch lock changed during proof')


def validate_authority(path,expected_sha=None,unclaimed=False,allow_proposed=False):
    path=Path(path).resolve();a=read(path)
    if expected_sha is not None:require(digest(path)==expected_sha,'root admitted authority hash differs')
    require(a.get('schema')=='r155_baseline_control_authority_v1'
        and a.get('status') in (('ADMITTED','PROPOSED') if allow_proposed else ('ADMITTED',)),
        'distinct explicit sixth-owner admission absent')
    require(a.get('activation')==ACTIVATION and a.get('automatic_retry') is False
        and a.get('cached_restart_authorized') is False and a.get('numerical_parameters_changed') is False,
        'one explicit sixth control activation required; no retry or numerical change')
    require(a.get('historical_owner5_start_ticks_unavailable_acknowledged') is True,
        'unavailable historical owner5 kernel anchors need explicit root acknowledgement')
    require(isinstance(a.get('authority_id'),str) and len(a['authority_id'])==32
        and all(ch in '0123456789abcdef' for ch in a['authority_id']),'new exact authority UUID required')
    runtime=Path(a['runtime']);require(runtime.parent==DATA/'launch_prep'
        and runtime.name=='pricefm_stage_r155_baseline_continuation_'+a['authority_id'],'new administrative namespace required')
    require(a['new_unit']=='pricefm-r155-baseline-owner-'+a['authority_id']+'.service'
        and a['guardian_unit']=='pricefm-r155-baseline-guardian-'+a['authority_id']+'.service','new scope-specific control units required')
    grant=a['grant']
    require(grant['starts_epoch']==ORIGINAL_START and grant['expires_epoch']==ORIGINAL_EXPIRY
        and grant['wall_seconds']==604800 and grant['control_CPU_seconds']==ORIGINAL_CPU,
        'original seven-day absolute clock and cumulative28800CPU must be preserved')
    require(a['predecessor_control_CPU_retained']==PRIOR_CONTROL_CPU
        and a['predecessor_unobserved_tail_CPU_reserve']==60 and a['preparation_CPU_debit']==200
        and a['retained_owner5_fixed_control_CPU']==OWNER5_FIXED_PAID_CPU and a['failure_inspection_CPU_debit']==10
        and a['activation_wrapper_CPU_reserve']==30 and grant['prior_control_CPU_seconds']==OWNER6_PRIOR_CPU
        and grant['prior_control_CPU_seconds']==sum(a[k] for k in ('retained_owner5_fixed_control_CPU',
            'failure_inspection_CPU_debit','preparation_CPU_debit','activation_wrapper_CPU_reserve')),
        'all owner5 fixed reserves plus failure audit/new preparation/activation must remain paid without credit')
    require(grant['prior_control_CPU_seconds']+a['guardian_CPU_reserve']+10<ORIGINAL_CPU
        and a['guardian_CPU_reserve']==600 and grant['administrative_source_check_CPU_reservation']>=.5,
        'finite cumulative control budget/reserves are insufficient')
    require(grant.get('administrative_poll_CPU_reservation',0)>=.1,
        'per-poll administrative subprocess costs must remain conservatively funded')
    now=time.time();require(ORIGINAL_START<=now<ORIGINAL_EXPIRY and a['activation_epoch']<=now
        and 0<a['unit_runtime_max_seconds']<=math.floor(ORIGINAL_EXPIRY-a['activation_epoch']-300),
        'new control activation cannot renew the original absolute deadline')
    require(a['poll_seconds']==20 and a['source_verify_seconds']==60 and a['guardian_lease_seconds']==180
        and a['administrative_cpu']==31 and a['expected_host_pid_namespace']=='pid:[4026531836]'
        and a['expected_boot_id']=='37b80e3b-9596-4c75-85e1-aca85af8fa7f',
        'finite observer cadence/host namespace/admin CPU differs')
    require(a['control_intent']==intent(a['new_unit'],'run',path)
        and a['guardian_intent']==intent(a['guardian_unit'],'guard',path),'actual new entry/cwd/argv intent differs')
    verify_source(a['execution_source']);prep=verify_pin(a['preparation'])
    require(prep['execution_source']==a['execution_source'] and a['predecessor_authority']==prep['predecessor_authority']
        and a['predecessor_state']==prep['predecessor_state'] and a['predecessor_attestation']==prep['predecessor_attestation']
        and a['predecessor_state_original']==prep['predecessor_state_original']
        and a['original_dispatch_locks']==prep['original_dispatch_locks']
        and a['spent_owner5']==prep['spent_owner5'] and a['paid_scope_ledger']==prep['paid_scope_ledger'],
        'exact prepared predecessor/failed5/paidledger/locks/source differ')
    check_pins(prep['dependency_sha256'])
    check_pins(prep['predecessor_runtime_sha256'])
    check_pins(prep['spent_owner5_runtime_sha256'])
    require(a['guardian_priority_policy']=='unit0_kernel10_self_only_before_attestation'
        and a['guardian_priority_compatibility_proof']==prep['guardian_priority_compatibility_proof'],
        'explicit guardian unit/kernel compatibility policy differs')
    verify_guardian_priority_proof(a['guardian_priority_compatibility_proof'])
    if not allow_proposed:
        review=verify_pin(a['source_review'])
        require(str(review.get('status','')).startswith('PASS') and review.get('administrative_runtime_review') is True
            and review.get('execution_source')==a['execution_source'],'distinct complete actual-source runtime review required')
    if unclaimed:require(not (runtime/'activation_claim.json').exists(),'sixth-owner activation spent; no retry')
    return a
