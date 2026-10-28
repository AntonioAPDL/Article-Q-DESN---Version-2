#!/usr/bin/env python3
"""One source-bound root-admitted <=300CPU synthetic proof on originalCPU30."""
import argparse
import ast
import datetime as dt
import fcntl
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import time
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
def module(name):
 s=importlib.util.spec_from_file_location(name,HERE/(name+'.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
nr=module('527_native_runtime');g=nr.traced
PY='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
STARTED=time.monotonic()

def verify_files(values):
 for v in values:
  if nr.pin(v['path'])!=v:raise ValueError('source/runtime pin changed: '+v['path'])

def original_metadata_function(filename,name,namespace):
 """Unchanged pure admission AST; no numerical module import or monkeypatch."""
 path=HERE/filename;tree=ast.parse(path.read_text());nodes=[v for v in tree.body if isinstance(v,ast.FunctionDef) and v.name==name]
 if len(nodes)!=1:raise ValueError('metadata function surface differs')
 exec(compile(ast.Module(body=nodes,type_ignores=[]),str(path),'exec'),namespace);return namespace[name]

def pool(grant):
 n={'ref':SimpleNamespace(verify_files=verify_files),'Path':Path,'json':json,'datetime':dt,'time':time}
 return original_metadata_function('522_fixed_state_control.py','global_permit',n)(grant)

def priority(value):
 n={'pinned':nr.read,'time':time}
 return original_metadata_function('525_run_project_stage.py','priority_ready',n)(value)

def authority(path,sha,output):
 if os.path.realpath('/proc/self/exe')!=os.path.realpath(PY) or os.sched_getaffinity(0)!={31}:raise ValueError('pinned administrative31 required')
 grant=nr.read({'path':str(Path(path).resolve()),'sha256':sha})
 if grant.get('schema')!='r157_projection_toy_grant_v1' or grant.get('status')!='ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY':raise ValueError('not a new root synthetic proof grant')
 source=grant['source']
 branch=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip();head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 if source!={'kind':'R154_project_fullstate_consumer_pinned_CRAN111','branch':branch,'head':head} or not branch.startswith('work/pricefm-r157-native-bootstrap-') or subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip():raise ValueError('exact clean frozen R157 source required')
 if grant.get('authorizes_toy_optimizer') is not True or grant.get('authorizes_production_fits') is not False or grant.get('authorizes_production_acceptance') is not False:raise ValueError('unsupported target/production authority')
 if tuple(grant[k] for k in ('maximum_optimizer_invocations','maximum_total_optimizer_iterations','maximum_n','maximum_p'))!=(8,30,128,32):raise ValueError('synthetic call/shape limits differ')
 if grant['host']!='muscat' or grant['affinity']!=[30] or grant['cores']!=1 or grant['memory_GiB']!=8:raise ValueError('original oneCPU30/8GiB permit required')
 for k in ('maximum_CPU_seconds','maximum_combined_CPU_seconds','maximum_wall_seconds'):
  if isinstance(grant[k],bool) or not math.isfinite(grant[k]) or grant[k]<=0:raise ValueError('finite stage bounds required')
 if not grant['maximum_CPU_seconds']<=grant['maximum_combined_CPU_seconds']-10<=290:raise ValueError('whole proof exceeds300CPU or lacks10CPU finalizer reserve')
 if not 0<grant['maximum_wall_seconds']<=1800:raise ValueError('whole proof wall bound differs')
 p=pool(grant);expiry=dt.datetime.fromisoformat(grant['expires_UTC']).timestamp()
 if not time.time()+grant['maximum_wall_seconds']<=expiry<=grant['stage_deadline_epoch']<=p['expires_epoch']:raise ValueError('whole proof cannot fit original nonrenewing calendar')
 if grant.get('maximum_new_attempts')!=1 or grant.get('attempt_index')!=1 or grant.get('old_costs_refunded') is not False:raise ValueError('one new attempt/no refund required')
 if not grant.get('paid_history_pins'):raise ValueError('paid history evidence required')
 verify_files(grant['paid_history_pins']);verify_files(grant['source_bindings'])
 config=ROOT/'application/config/pricefm/525_conditional_pilot_plan.json'
 cfg=json.loads(config.read_text());original=nr.read(cfg['original_manifest'])
 verify_files([cfg['fixedpoint_helper_source']])
 if original['targets'][0]['contract']['fixedpoint_helper']!=cfg['fixedpoint_helper_source']['path']:raise ValueError('actual bootstrap helper differs from frozen config')
 if grant['actual_R_runtime_binding']!=cfg['actual_R_runtime_binding'] or grant['expected_stock_body_sha256']!=cfg['expected_stock_body_sha256']:raise ValueError('native runtime or stock body differs from frozen config')
 needed={str(HERE/n) for n in ('527_run_projection_toy.py','527_native_runtime.py','526_traced_bootstrap_guard.py','525_owned_stage_guard.py','522_fixed_state_control.py','525_run_project_stage.py','527_project_bootstrap.R')}
 needed|={str(ROOT/n) for n in ('application/R/526_scientific_boundary.c','application/tests/526_native_metadata_wrapper.R','application/tests/525_source_metadata_test.R','application/tests/525_project_projection_toy_validation.R','application/tests/525_finalize_projection_validation.py','application/R/524_toy_fullstate_consumer.R','application/R/525_project_fullstate_consumer.R','application/R/pricefm_r129_al_fixedpoint_certificate.R')}
 needed|={str(config),cfg['original_manifest']['path'],cfg['fixedpoint_helper_source']['path']}
 if not needed<={v['path'] for v in grant['source_bindings']}:raise ValueError('complete execution/source closure required')
 nr.grant_compatibility(grant)
 runtime=nr.read(grant['actual_R_runtime_binding']);verify_files([{'path':runtime['actual_executable'],'sha256':runtime['actual_executable_sha256']}])
 verify_files([{'path':str(Path(runtime['package_path'])/k),'sha256':v} for k,v in runtime['package_files_sha256'].items()])
 verify_files([{'path':k,'sha256':v} for k,v in runtime['loaded_shared_object_sha256'].items()])
 if grant['cran_library']!=str(Path(runtime['package_path']).parent):raise ValueError('scientific library differs')
 if grant['bootstrap_exec_allowlist']!=nr.exec_allowlist(runtime):raise ValueError('bootstrap executable allowlist differs')
 if 'owner_handoff' not in grant:raise ValueError('actual approved-owner handoff authority required')
 nr.resolve_owner_admission(grant,{'path':str(Path(path).resolve()),'sha256':sha})
 priority(grant['priority_drain_pin'])
 out=Path(output).absolute()
 if out.exists() or any(q.is_symlink() for q in (out,*out.parents)):raise ValueError('new nonsymlink output required')
 return grant,p,runtime,out

def main():
 p=argparse.ArgumentParser();p.add_argument('--root-grant',required=True);p.add_argument('--root-grant-sha256',required=True);p.add_argument('--output',required=True);p.add_argument('--check-authority',action='store_true');a=p.parse_args()
 grant,contract,runtime,out=authority(a.root_grant,a.root_grant_sha256,a.output)
 if a.check_authority:print('PASS R157 synthetic authority only; no lock/claim/optimizer');return
 root_pin={'path':str(Path(a.root_grant).resolve()),'sha256':a.root_grant_sha256};out.mkdir(parents=True)
 g.immutable(out/'claim.json',{'source':grant['source'],'root_grant_pin':root_pin,'attempt':1,'old_costs_refunded':False})
 lockpath=Path(contract['lock_dir'])/'muscat_cpu30.lock'
 with lockpath.open('a+') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);priority(grant['priority_drain_pin'])
  os.sched_setaffinity(0,{30});os.sched_setscheduler(0,os.SCHED_OTHER,os.sched_param(0));os.setpriority(os.PRIO_PROCESS,0,10)
  subprocess.run(['ionice','-c','3','-p',str(os.getpid())],check=True,capture_output=True)
  census=nr.read(contract['evidence']['peer_census']);peer=lambda owned:nr.physical_peer_guard(census,out,owned)
  peer([])
  env=nr.native_environment(dict(os.environ,R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED='1',R154_GLOBAL_PERMIT_LOCK_FD=str(lock.fileno()),R157_PROJECT_ROOT=str(ROOT),R157_PROJECT_KIND='toy'),runtime,grant['boundary_library_pin'])
  target=out/'projection';command=nr.native_command(runtime,ROOT,'toy',[ROOT,Path(a.root_grant).resolve(),a.root_grant_sha256,target])
  def child_limits():
   resource.setrlimit(resource.RLIMIT_AS,(8*1024**3,)*2);resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,)*2)
   limit=int(grant['maximum_CPU_seconds']);resource.setrlimit(resource.RLIMIT_CPU,(limit,limit))
  with (out/'stdout.log').open('x') as stdout,(out/'stderr.log').open('x') as stderr:
   r=g.run_traced(command,env=env,stdout=stdout,stderr=stderr,lock_fd=lock.fileno(),affinity={30},wall_seconds=grant['maximum_wall_seconds']-(time.monotonic()-STARTED)-5,maximum_combined_CPU_seconds=grant['maximum_combined_CPU_seconds']-10,absolute_deadline_UTC=grant['expires_UTC'],peer_callback=peer,bootstrap_exec_allowlist=grant['bootstrap_exec_allowlist'],owner_path=out/'owner.json',scope=grant['scope_id'],source=grant['source'],authority_pin=root_pin,preexec_fn=child_limits,interval_seconds=.05,owner_capture_callback=nr.owner_callback(grant,out,root_pin))
  r.update(source=grant['source'],root_grant_sha256=a.root_grant_sha256,actual_R_runtime_binding=grant['actual_R_runtime_binding'],launcher='pinned_native_ELF_no_Rscript_shell_wrapper',validation_kind='synthetic_project_projection_only',entrypoint_pin=nr.pin(ROOT/'application/tests/525_project_projection_toy_validation.R'),wrapper_entrypoint_pin=nr.pin(HERE/'527_project_bootstrap.R'),validation_core_pin=nr.pin(target/'validation_core.json') if (target/'validation_core.json').exists() else None,child_CPU_seconds=r['child_tree_CPU_seconds'])
  g.immutable(out/'owned_guard_receipt.json',r)
  if not nr.completed(r):raise SystemExit('R157 numerical proof failed; claim/cost retained')
 os.sched_setaffinity(0,{31})
 spec=importlib.util.spec_from_file_location('finalizer',ROOT/'application/tests/525_finalize_projection_validation.py');final=importlib.util.module_from_spec(spec);spec.loader.exec_module(final)
 if sum(g.cpu())+5>grant['maximum_combined_CPU_seconds'] or time.time()>=dt.datetime.fromisoformat(grant['expires_UTC']).timestamp():raise SystemExit('finalizer reserve/clock unavailable; paid receipt retained')
 result=final.finalize(nr.pin(target/'validation_core.json'),root_pin,nr.pin(out/'owned_guard_receipt.json'),out/'validation.json')
 whole=sum(g.cpu());wall=time.monotonic()-STARTED;accepted=whole<=grant['maximum_combined_CPU_seconds'] and wall<=grant['maximum_wall_seconds'] and time.time()<dt.datetime.fromisoformat(grant['expires_UTC']).timestamp()
 g.immutable(out/'resource_accounting.json',{'status':'COMPLETE' if accepted else 'OVERRUN_RETAINED_NOT_ACCEPTED','source':grant['source'],'whole_process_CPU_seconds':whole,'maximum_combined_CPU_seconds':grant['maximum_combined_CPU_seconds'],'whole_wall_seconds':wall,'maximum_wall_seconds':grant['maximum_wall_seconds'],'root_grant_pin':root_pin,'optimizer_invocations':8,'real_target_inputs':False,'old_costs_refunded':False,'validation_pin':result})
 if not accepted:raise SystemExit('whole proof accounting/clock overrun; validation not production-eligible')
 print(json.dumps({'status':'PASS_SYNTHETIC_PROJECTION_ONLY','validation':result,'whole_CPU_seconds':whole},sort_keys=True))

if __name__=='__main__':
 try:main()
 except BaseException as error:
  # Preserve paid administrative/helper costs even when no R child was launched.
  import sys
  if '--output' in sys.argv:
   failure=Path(sys.argv[sys.argv.index('--output')+1])
   if failure.is_dir() and (failure/'claim.json').is_file() and not (failure/'resource_accounting.json').exists():
    g.immutable(failure/'failure_accounting.json',{'status':'FAILED_COST_RETAINED_NO_RETRY','whole_process_CPU_seconds':sum(g.cpu()),'whole_wall_seconds':time.monotonic()-STARTED,'old_costs_refunded':False,'error_type':type(error).__name__,'error':str(error)})
  raise
