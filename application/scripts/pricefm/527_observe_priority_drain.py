#!/usr/bin/env python3
"""Bounded read-only EE/LV/successor capture; never a numerical admission."""
import argparse
import ast
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import signal
import sys
import time

ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
PY='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
MAX=16*1024**2;START=time.monotonic()
spec=importlib.util.spec_from_file_location('r157_observer_guard',HERE/'526_traced_bootstrap_guard.py')
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
NAMES={'EE':'528_run_pricefm_stage_r155_final_component.py','LV':'526_run_pricefm_stage_r155_lv_handoff.py',
       'successor':'529_run_pricefm_stage_r155_qualified_seeds.py'}

def require(ok,message):
 if not ok:raise ValueError(message)

def safe(path):
 p=Path(path);require(p.is_absolute() and '..' not in p.parts,'absolute canonical path required')
 require(not any(x.is_symlink() for x in (p,*p.parents)),'symlink evidence forbidden');return p

def pin(path):
 p=safe(path);require(p.is_file(),'regular evidence file required')
 return {'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}

def read(value):
 require(isinstance(value,dict) and set(value)=={'path','sha256'} and pin(value['path'])==value,'exact immutable pin differs')
 p=Path(value['path']);require(p.suffix=='.json' and p.stat().st_size<=MAX,'bounded JSON evidence required')
 return json.loads(p.read_text())

def capture(raw,name,records='records'):
 item=raw.get(records,{}).get(name);require(isinstance(item,dict) and set(item)=={'pin','value'},'missing captured '+name)
 require(read(item['pin'])==item['value'],'captured bytes differ: '+name);return item['value'],item['pin']

def fresh(raw,now):
 require(type(raw.get('epoch')) in (int,float) and 0<=now-raw['epoch']<=60,'observer epoch stale or future')

def dead(rows,key,minimum):
 require(isinstance(rows,list) and len(rows)>=minimum,'exact owned process inventory missing')
 seen=set()
 for row in rows:
  require(row.get(key) is False,'old exact lifetime remains live or unknown')
  identity=row.get('expected') if key=='exact_lifetime_live' else row.get('recorded')
  require(isinstance(identity,dict) and all(k in identity for k in ('pid','start_ticks','boot_id')),'exact historical lifetime identity missing')
  life=tuple(identity[k] for k in ('pid','start_ticks','boot_id'));require(life not in seen,'duplicate historical process identity');seen.add(life)

def unit(value):
 require(isinstance(value,dict) and value.get('MainPID')=='0' and value.get('Restart')=='no' and value.get('NRestarts')=='0',
         'live/restarting/pending-refill unit')
 require(value.get('ActiveState') in ('active','inactive') and value.get('SubState') in ('exited','dead') and
         value.get('Result')=='success' and value.get('ExecMainStatus')=='0','unit is not retained successful completion')

def lv_unit_after_sealed_completion(lv,expected_id):
 """LV's unchanged eight-field observer never emitted exit-status fields.

 Called only after exact LV exit/supervisor/seal success and dead lifetimes
 are verified below. An unloaded unit contributes drain evidence only; its
 defaults are never treated as a successful scientific exit.
 """
 value=lv.get('unit')
 require(isinstance(value,dict),'LV current unit evidence missing')
 if 'Result' in value or 'ExecMainStatus' in value:
  unit(value)
  return 'RETAINED_UNIT_EXIT_STATUS_OBSERVED'
 fields={'Id','MainPID','InvocationID','ActiveState','SubState','Restart','NRestarts','KillMode'}
 require(set(value)==fields and isinstance(expected_id,str) and value['Id']==expected_id and
         value['ActiveState']=='inactive' and value['SubState']=='dead' and value['MainPID']=='0' and
         value['Restart']=='no' and value['NRestarts']=='0' and value['InvocationID']=='' and
         value['KillMode']=='control-group','LV missing exit-status fields are not exact known unloaded unit')
 rows=lv.get('actual_processes')
 require(isinstance(rows,list) and len(rows)==3 and {x.get('role') for x in rows}=={'administrative','guardian','payload'},
         'unloaded LV requires exact three-role lifetime inventory')
 dead(rows,'live_exact_lifetime',3)
 return 'UNLOADED_UNIT_DRAIN_ONLY_SCIENTIFIC_SUCCESS_FROM_SEALED_EXIT'

def validate_observations(rows,plan,now):
 require(set(rows)==set(NAMES),'exact EE/LV/successor observer set required')
 for name,raw in rows.items():
  fresh(raw,now)
  expected=plan['observers'][name]['authority_pin']
  actual=raw.get('administrative_authority') if name=='LV' else raw.get('authority')
  require(actual==expected,'actual observer authority differs: '+name)
 ee,lv,successor=(rows[k] for k in ('EE','LV','successor'))
 require(ee.get('status')=='READ_ONLY_ACTUAL_SOURCE_METADATA' and ee.get('schema')=='r155_final_actual_caller_inspection_v1', 'wrong EE observer')
 require(all(ee.get(k)==0 for k in ('new_forecasts','new_fits','claims_created','signals_sent','services_changed')) and ee.get('numerical_modules_imported') is False,'EE observer did work')
 dead(ee.get('owned_processes'),'exact_lifetime_live',2);unit(ee.get('unit_show'))
 ee_exit,ee_pin=capture(ee,'exit_receipt.json');ee_super,_=capture(ee,'supervisor_exit_receipt.json')
 ee_assessment,ee_ap=capture(ee,'assessment.json');ee_seal,_=capture(ee,'assessment_seal.json')
 require(ee_exit.get('status')=='COMPLETE_INITIAL_PREFIX' and ee_super.get('status')=='PAYLOAD_EXITED' and
         ee_super.get('child_exit_code')==0 and ee_seal.get('assessment')==ee_ap,'EE historical completion/seal differs')
 require(lv.get('status')=='READ_ONLY_EXACT_R155_ADMIN_AND_ORIGINAL_R154_LV_HEALTH' and
         lv.get('complete_calls')==12 and lv.get('calls_remaining')==0 and lv.get('same_original_permit_free') is True and
         all(lv.get(k)==0 for k in ('runtime_mutations','scientific_dispatches','signals')),'LV incomplete or not read-only/drained')
 dead(lv.get('actual_processes'),'live_exact_lifetime',3)
 admin,_=capture(lv,'exit_receipt.json','administrative_records')
 require(admin.get('status')=='COMPLETE_LV_TRAINING_DIAGNOSTIC_NOT_PROMOTED','LV administrative completion absent')
 lv_authority=read(plan['observers']['LV']['authority_pin']);scientific=read(lv_authority['stage']['authority'])
 lv_pin=pin(Path(scientific['output_dir'])/'exit_receipt.json');lv_exit=read(lv_pin)
 lv_super,_=capture(lv,'supervisor_exit_receipt.json','LV_records')
 lv_assessment,lv_ap=capture(lv,'assessment.json','LV_records');lv_seal,_=capture(lv,'assessment_seal.json','LV_records')
 require(lv_exit.get('status')=='COMPLETE_DIAGNOSTIC' and lv_super.get('status')=='PAYLOAD_EXITED' and
         lv_super.get('child_exit_code')==0 and lv_seal.get('assessment')==lv_ap,'LV exact historical completion/seal differs')
 lv_unit_kind=lv_unit_after_sealed_completion(lv,lv_authority.get('unit'))
 require(successor.get('status')=='READ_ONLY_SOURCE_BOUND_MATCHED_SEED_OBSERVATION' and
         successor.get('complete_components')==successor.get('required_components')==12 and successor.get('remaining_components')==0 and
         successor.get('scientifically_complete_and_physically_drained') is True and successor.get('same_original_flock_free') is True and
         all(successor.get(k)==0 for k in ('new_fits','new_forecasts','runtime_writes','signals')) and successor.get('model_helpers_imported') is False,
         'successor incomplete/live/unknown/refill pending')
 dead(successor.get('processes'),'live_exact_lifetime',2);unit(successor.get('actual_unit'))
 assessment,ap=capture(successor,'assessment.json');seal,_=capture(successor,'assessment_seal.json')
 end,_=capture(successor,'exit_receipt.json');supervisor,_=capture(successor,'supervisor_exit_receipt.json')
 matched,_=capture(successor,'full_matched_set.json');claim,_=capture(successor,'claim.json')
 names=assessment.get('required_task_names');qualified=assessment.get('qualified_from_unchanged_initial_S0')
 require(qualified in (['r134_5c42f007409acfb3'],['r134_984fd326bd5fd13e']),'original matched nominee differs')
 expected=['EE_{}_s{}_S_seed{}'.format(p,s,k) for p in ['C0']+qualified for k in (1,2) for s in (1,2,3)]
 require(names==expected and matched.get('required_task_names')==names and matched.get('components')==12 and claim.get('required_tasks')==names,
         'successor matched task inventory differs')
 require(assessment.get('status')=='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED' and
         assessment.get('automatic_followon') is False and assessment.get('AL_proposal_admitted') is False and
         assessment.get('all_new_components_independently_revalidated') is True and seal.get('assessment')==ap and
         end.get('status')=='COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT' and supervisor.get('status')=='PAYLOAD_EXITED' and supervisor.get('child_exit_code')==0,
         'successor seal/completion or no-refill decision differs')
 return {'EE_exit':ee_pin,'LV_exit':lv_pin,'no_live_owned_numerical_lifetimes':True,'no_pending_refill':True,
         'LV_unit_evidence_class':lv_unit_kind,'LV_scientific_success_basis':'exact_COMPLETE_DIAGNOSTIC_exit_PAYLOAD_EXITED_zero_child_and_assessment_seal',
         'no_pending_refill_basis':'exact completed fixed matched set; no automatic followon or AL admission; retained successful no-restart units; final original flock probe'}

def metadata_import_closure(entry):
 """Inspect top-level imports without importing any historical observer."""
 seen=set();todo=[safe(entry)]
 while todo:
  p=todo.pop()
  if p in seen:continue
  seen.add(p);tree=ast.parse(p.read_text(),str(p))
  for node in tree.body:
   if isinstance(node,(ast.Import,ast.ImportFrom)):
    modules=[x.name for x in node.names] if isinstance(node,ast.Import) else [node.module or '']
    for name in modules:
     require(name.split('.')[0] not in ('numpy','scipy','pandas','threadpoolctl','exdqlm'),'numerical top-level observer import forbidden')
     candidate=p.parent/(name.split('.')[0]+'.py')
     if candidate.is_file():todo.append(candidate)
 return [pin(p) for p in sorted(seen)]

def validate_plan(plan_pin):
 plan=read(plan_pin)
 require(plan.get('schema')=='r157_priority_drain_observation_plan_v1' and plan.get('status')=='ROOT_ADMITTED_METADATA_PRIORITY_DRAIN_CAPTURE_ONLY','not root-admitted metadata capture')
 require(plan.get('maximum_combined_CPU_seconds')==20 and plan.get('maximum_wall_seconds')==60 and plan.get('affinity')==[31] and
         plan.get('actual_target_inputs') is False and plan.get('optimizer_invocations')==0,'capture metadata/resource scope differs')
 require(os.path.realpath('/proc/self/exe')==os.path.realpath(PY) and os.sched_getaffinity(0)=={31},'pinned Python -B/CPU31 required')
 require(sys.dont_write_bytecode and not {'numpy','scipy','pandas'}&set(sys.modules),'metadata-only Python process required')
 cfg=json.loads((ROOT/'application/config/pricefm/525_conditional_pilot_plan.json').read_text())
 require(plan['global_contract']==cfg['global_contract'],'not exact original global contract')
 pool=read(plan['global_contract']);require(pool['max_new_numerical']==1 and pool['nonrenewing'] is True,'original permit differs')
 expiry=dt.datetime.fromisoformat(plan['expires_UTC']).timestamp();require(time.time()+60<=expiry<=pool['expires_epoch'],'whole metadata capture clock unavailable')
 supplied={p['path']:p for p in plan['source_bindings']}
 for p in supplied.values():require(pin(p['path'])==p,'capture source changed')
 needed=[pin(__file__),pin(HERE/'526_traced_bootstrap_guard.py')]
 require(set(plan['observers'])==set(NAMES),'wrong observer set')
 for role,value in plan['observers'].items():
  require(Path(value['entry_pin']['path']).name==NAMES[role] and pin(value['entry_pin']['path'])==value['entry_pin'],'exact unchanged observer entry required')
  read(value['authority_pin']);needed+=metadata_import_closure(value['entry_pin']['path'])
  if role=='successor':read(value['preparation_pin'])
 for p in needed:require(supplied.get(p['path'])==p,'complete producer/observer import closure missing')
 return plan,pool

def probe_original_lock(pool,expected):
 path=safe(Path(pool['lock_dir'])/'muscat_cpu30.lock');st=path.stat()
 actual={'path':str(path),'device':st.st_dev,'inode':st.st_ino}
 require(actual==expected,'exact original flock device/inode/path differs')
 with path.open('r+') as stream:
  now=os.fstat(stream.fileno());require((now.st_dev,now.st_ino)==(st.st_dev,st.st_ino),'lock changed before probe')
  fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
  require(guard.held_lock(stream.fileno())['inode']==st.st_ino,'actual FLOCK proof absent')
  fcntl.flock(stream,fcntl.LOCK_UN)
 return dict(actual,physically_free=True,observed_epoch=time.time())

def run_observer(role,value,plan,out,private_fd):
 command=[PY,'-B',value['entry_pin']['path'],'--inspect','--authority',value['authority_pin']['path'],'--authority-sha256',value['authority_pin']['sha256']]
 if role=='successor':command+=['--preparation',value['preparation_pin']['path']]
 allowed={str(Path(p).resolve()):hashlib.sha256(Path(p).resolve().read_bytes()).hexdigest() for p in (PY,'/usr/bin/git','/usr/bin/systemctl','/usr/bin/ionice')}
 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONNOUSERSITE='1',PYTHONPATH='',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
 with (out/(role+'.stdout.json')).open('x') as stdout,(out/(role+'.stderr.log')).open('x') as stderr:
  receipt=guard.run_traced(command,env=env,stdout=stdout,stderr=stderr,lock_fd=private_fd,affinity={31},
    wall_seconds=58-(time.monotonic()-START),maximum_combined_CPU_seconds=18,absolute_deadline_UTC=plan['expires_UTC'],
    peer_callback=lambda owned:{'scope':'private_administrative_observers_only','owned':len(owned)},bootstrap_exec_allowlist=allowed,
    require_science_handshake=False,scope='R157_METADATA_PRIORITY_DRAIN',interval_seconds=.02)
 guard.immutable(out/(role+'.observer_guard_receipt.json'),receipt)
 require(receipt['status']=='EXITED' and receipt['returncode']==0 and all(receipt[k] is True for k in ('reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled')),'metadata observer failed/undrained')
 return read(pin(out/(role+'.stdout.json')))

def observe(plan_pin,out):
 plan,pool=validate_plan(plan_pin);out=safe(out);require(not out.exists(),'fresh capture output required');out.mkdir(parents=True);success=False
 guard.immutable(out/'capture_plan_pin.json',plan_pin);rows={}
 try:
  with (out/'private_metadata.lock').open('x+') as lock:
   fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
   for role in ('EE','LV','successor'):rows[role]=run_observer(role,plan['observers'][role],plan,out,lock.fileno())
  result=validate_observations(rows,plan,time.time());proof=probe_original_lock(pool,plan['original_lock_identity'])
  require(sum(guard.cpu())<19 and time.monotonic()-START<59,'combined metadata capture/finalization reserve exhausted')
  result.update(schema='r157_fresh_priority_drain_v1',status='EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED',observed_epoch=time.time(),
    shared_permit_physically_free=True,original_lock_probe=proof,source_bindings=plan['source_bindings'],capture_plan_pin=plan_pin,
    observer_pins={k:pin(out/(k+'.stdout.json')) for k in rows},maximum_combined_CPU_seconds=20,maximum_wall_seconds=60,
    observer_guard_receipt_pins={k:pin(out/(k+'.observer_guard_receipt.json')) for k in rows},requires_capture_accounting_review=True,
    whole_combined_CPU_seconds=sum(guard.cpu()),whole_wall_seconds=time.monotonic()-START,new_forecasts=0,new_fits=0,signals_to_existing_processes=0)
  guard.immutable(out/'priority_drain.json',result);success=True;return pin(out/'priority_drain.json')
 finally:
  guard.immutable(out/'capture_accounting.json',{'status':'COMPLETE' if success and sum(guard.cpu())<20 and time.monotonic()-START<60 else 'FAILED_COST_RETAINED','whole_combined_CPU_seconds':sum(guard.cpu()),
    'whole_wall_seconds':time.monotonic()-START,'old_costs_refunded':False,'actual_target_inputs':False,'optimizer_invocations':0})

if __name__=='__main__':
 resource.setrlimit(resource.RLIMIT_CPU,(20,20))
 def expired(signum,frame):raise TimeoutError('whole metadata producer60wall elapsed')
 signal.signal(signal.SIGALRM,expired);signal.setitimer(signal.ITIMER_REAL,max(.001,60-(time.monotonic()-START)))
 p=argparse.ArgumentParser();p.add_argument('--plan',required=True);p.add_argument('--plan-sha256',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 print(json.dumps(observe({'path':str(Path(a.plan).absolute()),'sha256':a.plan_sha256},a.output),sort_keys=True))
