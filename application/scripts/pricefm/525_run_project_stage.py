#!/usr/bin/env python3
"""One explicit real bridge or pilot grant; never a standby/automatic fit chain."""
import argparse
import ctypes
import datetime
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
def module(name):
    spec=importlib.util.spec_from_file_location(name,HERE/(name+'.py'))
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
registry=module('525_candidate_registry');physical=module('524_run_toy_validation')
owned_guard=module('525_owned_stage_guard')
base=physical.base;ref=base.ref
AUDIT=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates/conditional_pilot')
RESERVATIONS={registry.NO3:11321.738,registry.AT:17079.5}
FINALIZATION_TAIL_CPU_SECONDS=30.0

def cumulative_CPU():
    own=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
    return own.ru_utime+own.ru_stime+children.ru_utime+children.ru_stime

def native_R_command(runtime,script,arguments):
    return [runtime['actual_executable'],'--no-echo','--no-restore','--file='+str(script),'--args',*map(str,arguments)]

def native_R_environment(env,runtime):
    env=dict(env);home=runtime['R_home']
    env.update(R_HOME=home,R_SHARE_DIR=home+'/share',R_INCLUDE_DIR=home+'/include',R_DOC_DIR=home+'/doc',R_ARCH='')
    env['LD_LIBRARY_PATH']=home+'/lib'
    return env


def pin(path):return dict(path=str(Path(path).resolve()),sha256=ref.sha256(path))
def pinned(value):return registry.read(registry.verify_pin(value))


def priority_ready(value):
    proof=pinned(value)
    if proof['status']!='EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED':raise ValueError('priority chain not complete/drained')
    for key,status in [('EE_exit','COMPLETE_INITIAL_PREFIX'),('LV_exit','COMPLETE_DIAGNOSTIC')]:
        if pinned(proof[key])['status']!=status:raise ValueError('exact EE/LV exit is not successful')
    if not all(proof.get(k) is True for k in ['no_live_owned_numerical_lifetimes','no_pending_refill','shared_permit_physically_free']):
        raise ValueError('priority chain lifetime/refill proof missing')
    if not 0<=time.time()-proof['observed_epoch']<=60:raise ValueError('priority drain proof stale')
    return proof


def load_config(path):
    cfg=json.loads(Path(path).read_text());original=registry.load_original_manifest()
    if cfg['schema']!='r154_conditional_pilot_plan_v1' or cfg['original_manifest']!={'path':registry.MANIFEST_PATH,'sha256':registry.MANIFEST_SHA256}:
        raise ValueError('wrong original manifest or plan')
    if set(cfg['execution'])!=registry.ALLOWED_TARGETS:raise ValueError('not exact two-target allowlist')
    if cfg['caps']!={'Normal':2000,'AL':300} or cfg['acceptance_logic']!=registry.ACCEPTANCE:raise ValueError('changed cap or OR criterion')
    ref.verify_files([cfg['fixedpoint_helper_source']])
    ref.verify_files([cfg['alias_source_manifest']])
    aliases=json.loads(Path(cfg['alias_source_manifest']['path']).read_text())['execution']
    for target in registry.ALLOWED_TARGETS:
        if cfg['execution'][target]['aliases']!=aliases[target]['aliases']:raise ValueError('execution aliases changed')
        if 'alias_manifest' in cfg['execution'][target]:ref.verify_files([cfg['execution'][target]['alias_manifest']])
    return cfg,original


def authority(config_path,grant_path,grant_sha):
    if os.path.realpath('/proc/self/exe')!=os.path.realpath(ref.PINNED_PYTHON):raise ValueError('pinned Python required')
    g=pinned(dict(path=grant_path,sha256=grant_sha));cfg,original=load_config(config_path)
    if cfg.get('production_runtime_compatible') is not True:
        raise ValueError('known filtered-R startup incompatibility: production stages closed')
    mode=g['mode'];target=g['target_name'];registry.target_record(original,target)
    expected='ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY' if mode=='bridge' else 'ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY'
    if mode not in ('bridge','pilot') or g['status']!=expected or g['manifest_sha256']!=ref.sha256(config_path):raise ValueError('not admitted exact stage')
    registry.source_identity(g['source'])
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    if g['source']['head']!=head or subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip():raise ValueError('source not exact frozen clean head')
    if g['max_iter']!=(0 if mode=='bridge' else 300) or g['new_attempt_index']!=1 or g['maximum_new_attempts']!=1:
        raise ValueError('one new attempt/cap contract changed')
    if g['expected_stock_body_sha256']!=cfg['expected_stock_body_sha256']:raise ValueError('stock source body differs')
    if g['seed']!=registry.target_record(original,target)['seed'] or g['authorizes_production_acceptance'] is not False:
        raise ValueError('seed or candidate-only authority changed')
    if g['host']!='muscat' or os.uname().nodename.split('.')[0]!='muscat' or g['affinity']!=[30] or g['cores']!=1:
        raise ValueError('execution resource identity differs')
    if g['global_contract']!=cfg['global_contract'] or g['memory_GiB']!=8 or g['disk_GiB']!=2:raise ValueError('global/runtime resource bounds differ')
    pool=base.global_permit(g);drain=priority_ready(g['priority_drain_pin'])
    scope=pinned(g['resource_scope_pin'])
    if scope['status']!='ROOT_ADMITTED_NEW_PROJECT_STAGE_ON_EXISTING_PHYSICAL_PERMIT' or scope['mode']!=mode or scope['target_name']!=target or scope['source']!=g['source']:
        raise ValueError('V2 reference scope is not new-production resource authority')
    if scope['science']!=('REAL_ZERO_OPTIMIZER_BRIDGE' if mode=='bridge' else 'NEW_PRODUCTION_INITIALIZATION_PILOT'):
        raise ValueError('new stage resource science type differs')
    if scope['global_created_epoch']!=pool['created_epoch'] or scope['global_expires_epoch']!=pool['expires_epoch'] or scope['permit_id']!='muscat_cpu30' or scope['physical_guard_cpus']!=[30,62] or scope['own_science_affinity']!=[30] or scope['new_core_or_global_clock_reset'] is not False:
        raise ValueError('new scope changed physical allocation or old global clock')
    if scope['authorizes_only_owned_new_child_guard_abort'] is not True:raise ValueError('owned disposable-child safety authority absent')
    clock=pinned(g['clock_authority_pin'])
    if clock['status']!='ROOT_ADMITTED_NEW_STAGE_CLOCK_WITHOUT_GLOBAL_RESET' or clock['mode']!=mode or clock['target_name']!=target:
        raise ValueError('new bridge/pilot clock authority missing')
    if clock['global_created_epoch']!=pool['created_epoch'] or clock['global_expires_epoch']!=pool['expires_epoch'] or clock['not_old_diagnostic_clock_reset'] is not True:
        raise ValueError('old global clock reset or inherited expired diagnostic clock')
    expiry=datetime.datetime.fromisoformat(g['expires_UTC']).timestamp()
    if not drain['observed_epoch']<=clock['not_before_epoch']<=time.time()<expiry<=clock['not_after_epoch']<=pool['expires_epoch']:
        raise ValueError('stage/global clock invalid')
    funding=pinned(g['funding_pin'])
    if funding['status']!='ROOT_FUNDED_WHOLE_TARGET_ATTEMPT' or funding['target_name']!=target or funding['source']!=g['source']:
        raise ValueError('whole-attempt funding absent')
    if funding['reservation_CPU_seconds']!=RESERVATIONS[target] or funding['all_parent_lineage_costs_paid'] is not True or funding['original_failed_costs_refunded'] is not False:
        raise ValueError('funding/paid lineage contract changed')
    for value in funding['historical_parent_lineage_pins']:ref.verify_files([value])
    if not funding['historical_parent_lineage_pins']:raise ValueError('paid parent lineage evidence absent')
    charged=funding['charged_before_child_CPU_seconds'];child=g['maximum_CPU_seconds']
    if funding['reserved_parent_and_finalize_CPU_seconds']<300 or charged<funding['reserved_parent_and_finalize_CPU_seconds']:
        raise ValueError('administrative/finalization CPU not funded')
    if not math.isfinite(charged) or charged<0 or not 0<child<=RESERVATIONS[target]-charged:raise ValueError('whole-attempt reservation exceeded')
    if mode=='bridge' and child>cfg['execution'][target]['bridge_child_ceiling_CPU_seconds']:raise ValueError('bridge CPU ceiling exceeded')
    if not 0<g['maximum_wall_seconds']<=2*RESERVATIONS[target]+300:raise ValueError('unbounded wall authority')
    if mode=='pilot' and (g['maximum_wall_seconds']<child or expiry-time.time()<g['maximum_wall_seconds']):
        raise ValueError('whole pilot wall reservation does not fit stage/global expiry')
    required={str(ROOT/'application/R/525_project_fullstate_consumer.R'),str(HERE/'525_project_bridge_or_pilot.R'),str(Path(__file__).resolve()),str(HERE/'525_candidate_registry.py'),str(HERE/'525_owned_stage_guard.py'),str(HERE/'524_run_toy_validation.py'),str(HERE/'522_fixed_state_control.py'),str(HERE/'522_certificate_reference.py')}
    required.add(cfg['fixedpoint_helper_source']['path'])
    if not required<={v['path'] for v in g['source_bindings']}:raise ValueError('missing source pins')
    ref.verify_files(g['source_bindings'])
    if g['actual_R_runtime_binding']!=cfg['actual_R_runtime_binding']:raise ValueError('runtime pin differs')
    runtime=pinned(g['actual_R_runtime_binding'])
    ref.verify_files([dict(path=runtime['actual_executable'],sha256=runtime['actual_executable_sha256']),dict(path=runtime['Rscript'],sha256=runtime['Rscript_sha256'])])
    ref.verify_files([dict(path=str(Path(runtime['package_path'])/k),sha256=v) for k,v in runtime['package_files_sha256'].items()])
    ref.verify_files([dict(path=k,sha256=v) for k,v in runtime['loaded_shared_object_sha256'].items()])
    if target==registry.AT:
        predecessor=pinned(g['NO3_candidate_registration_pin'])
        if predecessor['target_name']!=registry.NO3 or predecessor['source']!=g['source'] or predecessor['accepted'] is not True:
            raise ValueError('AT blocked until accepted exact NO3 candidate')
    elif g.get('NO3_candidate_registration_pin') is not None:raise ValueError('NO3 is first, not a replay')
    proof=pinned(g['project_validation_pin'])
    if proof.get('schema')!='r154_project_adapter_validation_v1' or proof.get('source')!=g['source'] or proof.get('toy_default_and_import_parity_pass') is not True or proof.get('checkpoint_all_factors_schedules_RNG_IO_verified') is not True or proof.get('stock_AST_exactly_preserved') is not True or proof.get('no_production_data_used') is not True:
        raise ValueError('new project adapter numerical/checkpoint proof absent')
    launch=pinned(proof['owned_guard_receipt_pin'])
    if proof.get('actual_R_runtime_binding')!=cfg['actual_R_runtime_binding'] or proof.get('native_R_ELF_seccomp_startup_pass') is not True or launch.get('actual_R_runtime_binding')!=cfg['actual_R_runtime_binding'] or launch.get('source')!=g['source'] or launch.get('status')!='EXITED' or launch.get('returncode')!=0 or launch.get('launcher')!='pinned_native_ELF_no_Rscript_shell_wrapper' or not all(launch.get(k) is True for k in ['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied']):
        raise ValueError('exact runtime native-ELF owned-guard startup proof absent')
    price=pinned(g['production_price_proof_pin'])
    if price.get('status')!='ROOT_REVIEWED_MEASURED_SOURCE_CONTEXT_PRICE' or price.get('source')!=g['source'] or price.get('target_name')!=target or price.get('mode')!=mode or price.get('project_validation_pin')!=g['project_validation_pin'] or price.get('full_peer_resource_interval_seconds')!=10 or price.get('owned_lifetime_CPU_wall_interval_seconds')!=1:
        raise ValueError('measured new-source parent/census price proof absent')
    if not 0<price['measured_full_census_CPU_seconds']<=price['conservative_full_census_CPU_seconds'] or price['priced_maximum_wall_seconds']<g['maximum_wall_seconds'] or price['required_parent_and_finalize_CPU_seconds']>funding['reserved_parent_and_finalize_CPU_seconds']:
        raise ValueError('realistic administrative census/finalization reservation missing')
    if price['required_parent_and_finalize_CPU_seconds']<300+math.ceil(g['maximum_wall_seconds']/10)*price['conservative_full_census_CPU_seconds']:
        raise ValueError('census extrapolation or finalization reserve understated')
    if mode=='pilot':
        bridge=pinned(g['bridge_pin'])
        if bridge.get('schema')!='r154_conditional_state_bridge_v1' or bridge['target_name']!=target or bridge['source']!=g['source']:
            raise ValueError('reviewed real bridge identity differs')
        for key in ('full_state_factors_verified','explicit_factor_elbo_verified','original_seven_certificate_computed','rhs_unit_and_dispersed_verified','source_recipe_reproduced'):
            if bridge.get(key) is not True:raise ValueError('bridge prerequisite missing: '+key)
        if bridge['optimizer_updates']!=0:raise ValueError('bridge performed optimization')
    return cfg,original,g,runtime,funding


def locked_run(args,cfg,original,g,runtime,funding,lock_fd):
    target=g['target_name'];mode=g['mode'];label='NO3_LARGER_TAU' if target==registry.NO3 else 'AT_MEDIAN'
    output=AUDIT/label/(mode+'_01')
    if output.exists():raise ValueError('completed/failed stage already exists; no automatic retry')
    if mode=='pilot':
        bridge_ledger=AUDIT/label/'bridge_01/resource_ledger.json'
        paid=pinned(g['bridge_resource_ledger_pin'])
        paid_guard=pinned(paid['owned_guard_receipt_pin'])
        flags=['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied']
        paid_funding=pinned(paid['funding_pin'])
        if g['bridge_resource_ledger_pin']['path']!=str(bridge_ledger) or paid['status']!='BRIDGE_REAPED' or paid['returncode']!=0 or paid['target_name']!=target or paid['source']!=g['source'] or not all(paid.get(k) is True and paid_guard.get(k) is True for k in flags) or paid_guard['status']!='EXITED' or paid_guard['returncode']!=0 or paid_guard['source']!=g['source'] or paid_guard['target_name']!=target or paid_guard['child_CPU_seconds']!=paid['child_CPU_seconds'] or paid_guard['root_grant_sha256']!=paid['root_grant_sha256']:
            raise ValueError('bridge not successfully reaped and paid')
        if paid['all_parent_lineage_costs_paid'] is not True or paid['whole_stage_debit_CPU_seconds']!=max(paid['actual_whole_stage_CPU_seconds_at_ledger'],paid['child_CPU_seconds']+paid_funding['reserved_parent_and_finalize_CPU_seconds']):
            raise ValueError('whole bridge administrative/finalization debit understated')
        if funding['charged_before_child_CPU_seconds']<paid['whole_stage_debit_CPU_seconds']+funding['reserved_parent_and_finalize_CPU_seconds']:
            raise ValueError('whole bridge debit plus current parent/finalization not carried')
    pool=base.global_permit(g)
    census=pinned(pool['evidence']['peer_census'])
    peer_callback=lambda identity:owned_guard.physical_peer_guard(census,AUDIT,identity)
    observation=peer_callback(None)
    registry.branch_predecessor(target,g.get('NO3_candidate_registration_pin'),original,g['source'])
    # Hash scientific bytes only with the shared numerical permit held.
    target_record=registry.target_record(original,target);aliases=cfg['execution'][target]['aliases']
    for item in target_record['bindings']:
        ref.verify_files([dict(path=aliases.get(item['path'],item['path']),sha256=item['sha256'])])
    if mode=='pilot':ref.verify_files([pinned(g['bridge_pin'])['factor_state']])
    claims=AUDIT/'claims';claims.mkdir(parents=True,exist_ok=True)
    ref.immutable_json(claims/(ref.canonical_hash([target,mode])+'.json'),dict(target_name=target,mode=mode,root_grant_sha256=args.root_grant_sha256,source=g['source'],no_automatic_retry=True))
    output.mkdir(parents=True)
    ref.immutable_json(output/'peer_preflight.json',observation)
    admission=dict(g);admission['root_grant_pin']=pin(args.root_grant)
    ref.immutable_json(output/'admission.json',admission)
    ref.immutable_json(output/'runtime_context.json',dict(status='VERIFIED_EXECUTION_RUNTIME',source=g['source'],host='muscat',package_repository='CRAN',package_version='1.1.1',actual_R_runtime_binding=g['actual_R_runtime_binding']))
    env=native_R_environment(dict(os.environ,TZ='UTC',R154_PROJECT_ROOT_ADMITTED='1',R154_PROJECT_MODE=mode,R154_GLOBAL_PERMIT_LOCK_FD=str(lock_fd),R154_PROJECT_ADMISSION_PATH=str(output/'admission.json'),R154_PROJECT_ADMISSION_SHA256=ref.sha256(output/'admission.json'),R154_PROJECT_RUNTIME_PATH=str(output/'runtime_context.json'),R154_PROJECT_RUNTIME_SHA256=ref.sha256(output/'runtime_context.json')),runtime)
    for k in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):env[k]='1'
    parent=os.getpid()
    def child_limits():
        libc=ctypes.CDLL(None,use_errno=True)
        if libc.prctl(1,signal.SIGKILL,0,0,0)!=0 or os.getppid()!=parent:os._exit(125)
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        limit=int(math.floor(g['maximum_CPU_seconds']))
        resource.setrlimit(resource.RLIMIT_CPU,(limit,limit));resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,)*2);resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,)*2)
    before=resource.getrusage(resource.RUSAGE_CHILDREN);started=time.monotonic();code=None;guard_receipt=None
    try:
        wall=min(g['maximum_wall_seconds'],datetime.datetime.fromisoformat(g['expires_UTC']).timestamp()-time.time())
        if wall<=0:raise ValueError('stage clock expired')
        with open(output/'stdout.log','x') as stdout,open(output/'stderr.log','x') as stderr:
            guard_receipt=owned_guard.run_owned(native_R_command(runtime,HERE/'525_project_bridge_or_pilot.R',[mode,ROOT,Path(args.config).resolve(),Path(args.root_grant).resolve(),args.root_grant_sha256,output]),env=env,stdout=stdout,stderr=stderr,preexec_fn=child_limits,pass_fds=(lock_fd,),lock_fd=lock_fd,wall_seconds=wall,maximum_combined_CPU_seconds=g['maximum_CPU_seconds']+funding['reserved_parent_and_finalize_CPU_seconds'],maximum_administrative_CPU_seconds=funding['reserved_parent_and_finalize_CPU_seconds']-FINALIZATION_TAIL_CPU_SECONDS,absolute_deadline_UTC=g['expires_UTC'],peer_check_callback=peer_callback,expected_child_affinity={30},interval_seconds=1,peer_interval_seconds=10)
        guard_receipt.update(source=g['source'],target_name=target,root_grant_sha256=args.root_grant_sha256)
        ref.immutable_json(output/'owned_guard_receipt.json',guard_receipt)
        successful=guard_receipt['status']=='EXITED' and guard_receipt['returncode']==0 and all(guard_receipt.get(k) is True for k in ['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied'])
        code=0 if successful else (guard_receipt['returncode'] if guard_receipt['returncode'] else -1)
    finally:
        after=resource.getrusage(resource.RUSAGE_CHILDREN);cpu=None if guard_receipt is None else guard_receipt['child_CPU_seconds']
        proved=guard_receipt is not None and all(guard_receipt.get(k) is True for k in ['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied'])
        actual=cumulative_CPU();admin=None if cpu is None else actual-cpu;reserve=funding['reserved_parent_and_finalize_CPU_seconds']
        paid=admin is not None and admin+FINALIZATION_TAIL_CPU_SECONDS<=reserve
        ledger=dict(status=('PILOT_REAPED' if mode=='pilot' else 'BRIDGE_REAPED') if proved and paid and code==0 else 'STAGE_ACCOUNTING_OR_DRAIN_FAILED',target_name=target,source=g['source'],mode=mode,returncode=code,child_CPU_seconds=cpu,parent_CPU_seconds=time.process_time(),administrative_CPU_seconds_including_startup_and_reaped_helpers=admin,actual_whole_stage_CPU_seconds_at_ledger=actual,reserved_finalization_tail_CPU_seconds=FINALIZATION_TAIL_CPU_SECONDS,wall_seconds=time.monotonic()-started,max_child_RSS_KiB=after.ru_maxrss,whole_stage_debit_CPU_seconds=actual if cpu is None else max(actual,cpu+reserve),all_parent_lineage_costs_paid=paid,original_failed_costs_refunded=False,funding_pin=g['funding_pin'],previous_charged_CPU_seconds=funding['charged_before_child_CPU_seconds'],charged_with_this_child_CPU_seconds=actual if cpu is None else max(funding['charged_before_child_CPU_seconds']+cpu,actual),root_grant_sha256=args.root_grant_sha256,owned_guard_receipt_pin=None if guard_receipt is None else pin(output/'owned_guard_receipt.json'))
        for key in ['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied']:ledger[key]=False if guard_receipt is None else guard_receipt.get(key) is True
        ref.immutable_json(output/'resource_ledger.json',ledger)
    if code!=0 or not paid:raise SystemExit(1)
    if mode=='pilot':
        registry.finalize_terminal_core(output,pin(output/'resource_ledger.json'),original,g['source'])
        seal=registry.seal_candidate_packet(output,original,g['source'])
        actual=cumulative_CPU();admin=actual-cpu
        ref.immutable_json(output/'finalization_accounting.json',dict(status='WITHIN_RESERVED_PARENT_AND_FINALIZATION' if admin<=reserve else 'PARENT_RESERVATION_OVERRUN_STOP',source=g['source'],target_name=target,actual_whole_stage_CPU_seconds=actual,administrative_CPU_seconds_including_startup_and_reaped_helpers=admin,reserved_parent_and_finalize_CPU_seconds=reserve,whole_stage_debit_CPU_seconds=max(actual,cpu+reserve),candidate_registration_not_yet_started=True))
        if admin>reserve:raise SystemExit('charged parent overrun; no candidate registration')
        registration=registry.register_candidate(AUDIT/'candidate_registry',seal,original,g['source'])
        terminal=json.loads((output/'terminal.json').read_text())
        ref.immutable_json(output/'branch_decision.json',dict(target_name=target,accepted=terminal['computationally_certified'],registration_pin=registration,status='CANDIDATE_ONLY_AWAIT_REVIEW' if terminal['computationally_certified'] else 'STOP_BRANCH_UNCERTIFIED',automatic_dependant_release=False,automatic_next_target=False))


def main():
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--root-grant',required=True);p.add_argument('--root-grant-sha256',required=True);p.add_argument('--check-authority',action='store_true');args=p.parse_args()
    if os.sched_getaffinity(0)!={31}:raise ValueError('administrative caller CPU31 required')
    cfg,original,g,runtime,funding=authority(args.config,args.root_grant,args.root_grant_sha256)
    if args.check_authority:print('PASS new stage authority only; no scientific bytes/claim/optimizer');return
    pool=base.global_permit(g)
    with open(Path(pool['lock_dir'])/'muscat_cpu30.lock','a+') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);priority_ready(g['priority_drain_pin'])
        os.sched_setaffinity(0,[30]);os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
        subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
        if not subprocess.check_output(['ionice','-p',str(os.getpid())],text=True).startswith('idle'):raise ValueError('I/O class differs')
        parent_limit=int(math.ceil(funding['reserved_parent_and_finalize_CPU_seconds']))
        resource.setrlimit(resource.RLIMIT_CPU,(parent_limit,max(parent_limit,int(math.ceil(g['maximum_CPU_seconds'])))))
        locked_run(args,cfg,original,g,runtime,funding,lock.fileno())


if __name__=='__main__':main()
