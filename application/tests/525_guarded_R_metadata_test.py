#!/usr/bin/env python3
"""Run NO-FIT R source/AST/checkpoint metadata fixture under real owned guard.

CPU31 and a private fixture lock are mandatory. This never borrows the global
numerical permit and does not claim new-source numerical parity.
"""
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'application/scripts/pricefm'
spec=importlib.util.spec_from_file_location('guard',HERE/'525_owned_stage_guard.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
spec=importlib.util.spec_from_file_location('control',HERE/'525_run_project_stage.py')
control=importlib.util.module_from_spec(spec);spec.loader.exec_module(control)
if __name__=='__main__':
 if len(sys.argv)!=2 or os.sched_getaffinity(0)!={31}:raise ValueError('fresh output and administrative CPU31 required')
 output=Path(sys.argv[1]).resolve();output.mkdir(parents=True,exist_ok=False)
 fd=os.open(output/'metadata_fixture.lock',os.O_CREAT|os.O_RDWR,0o600);fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
 env=dict(os.environ,TZ='UTC')
 for key in ['OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS']:env[key]='1'
 cfg=json.loads((ROOT/'application/config/pricefm/525_conditional_pilot_plan.json').read_text())
 runtime=control.pinned(cfg['actual_R_runtime_binding'])
 env=control.native_R_environment(env,runtime)
 def peer(identity):
  if identity and os.sched_getaffinity(identity['pid'])!={31}:raise ValueError('fixture left administrative CPU31')
  return dict(private_fixture=True,claims_global_numerical_permit=False)
 own,reaped=g._cpu_usage()
 try:
  with open(output/'stdout.log','x') as stdout,open(output/'stderr.log','x') as stderr:
   command=control.native_R_command(runtime,ROOT/'application/tests/525_source_metadata_test.R',[ROOT,output])
   receipt=g.run_owned(command,env=env,stdout=stdout,stderr=stderr,preexec_fn=lambda:os.sched_setaffinity(0,{31}),pass_fds=(fd,),lock_fd=fd,wall_seconds=60,maximum_combined_CPU_seconds=own+reaped+30,maximum_administrative_CPU_seconds=own+reaped+10,absolute_deadline_UTC=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=65)).isoformat(),peer_check_callback=peer,expected_child_affinity={31},interval_seconds=.05,peer_interval_seconds=1)
  receipt.update(command=command,R_environment={k:env[k] for k in ['R_HOME','R_SHARE_DIR','R_INCLUDE_DIR','R_DOC_DIR','R_ARCH','LD_LIBRARY_PATH']},launcher='pinned_native_ELF_no_Rscript_shell_wrapper')
  receipt.update(actual_R_runtime_binding=cfg['actual_R_runtime_binding'],scope='ADMINISTRATIVE_SOURCE_AST_OPAQUE_CHECKPOINT_NO_OPTIMIZER',production_data_used=False,optimizer_invocations=0,numerical_parity_proved=False)
  (output/'owned_guard_receipt.json').write_text(json.dumps(receipt,sort_keys=True,indent=2)+'\n')
  if receipt['status']!='EXITED' or receipt['returncode']!=0 or not all(receipt.get(k) is True for k in ['reaped','drained','CPU_accounting_complete','preexec_kernel_boundary_proved','subprocess_creation_kernel_denied']):raise SystemExit('guarded R metadata fixture failed; retained')
  proof=json.loads((output/'metadata_proof.json').read_text())
  if proof['optimizer_invocations']!=0 or proof['numerical_parity_proved'] is not False:raise ValueError('metadata fixture overstated proof')
  print(json.dumps(dict(status='PASS',child_CPU_seconds=receipt['child_CPU_seconds'],actual_pinned_native_R_ELF_seccomp_startup=True,AST_and_opaque_checkpoint_IO=True,numerical_parity=False,optimizer_invocations=0)))
 finally:os.close(fd)
