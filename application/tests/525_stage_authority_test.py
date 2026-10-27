#!/usr/bin/env python3
"""Synthetic metadata only: actual authority logic, never target bytes/optimizer."""
import copy
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
spec=importlib.util.spec_from_file_location('control',HERE/'525_run_project_stage.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)

class AuthorityTests(unittest.TestCase):
 def setUp(self):
  self.assertEqual(os.sched_getaffinity(0),{31})
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.i=0
  self.source=dict(kind=c.registry.SOURCE_KIND,branch='work/pricefm-r154-fullstate-pilot-adapter-test',head='1'*40)
  self.cfg=json.loads((c.ROOT/'application/config/pricefm/525_conditional_pilot_plan.json').read_text())
  # Future positive admission path uses a synthetic metadata-only compatibility
  # fixture; the actual prepared production configuration stays hard-closed.
  self.cfg['production_runtime_compatible']=True
  executable=self.root/'ELF_fixture';executable.write_text('not executable; metadata only')
  package=self.root/'package';package.mkdir();(package/'DESCRIPTION').write_text('fixture')
  runtime=dict(actual_executable=str(executable),actual_executable_sha256=c.ref.sha256(executable),Rscript=str(executable),Rscript_sha256=c.ref.sha256(executable),package_path=str(package),package_files_sha256={'DESCRIPTION':c.ref.sha256(package/'DESCRIPTION')},loaded_shared_object_sha256={})
  self.cfg['actual_R_runtime_binding']=self.write(runtime)
  self.config=self.root/'config.json';self.config.write_text(json.dumps(self.cfg))
  self.pool=c.base.global_permit(dict(global_contract=self.cfg['global_contract'],permit_id='muscat_cpu30',affinity=[30],host='muscat',expires_UTC=self.expiry()))
  observed=time.time()-1
  priority=self.write(dict(status='EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED',EE_exit=self.write(dict(status='COMPLETE_INITIAL_PREFIX')),LV_exit=self.write(dict(status='COMPLETE_DIAGNOSTIC')),no_live_owned_numerical_lifetimes=True,no_pending_refill=True,shared_permit_physically_free=True,observed_epoch=observed))
  scope=dict(status='ROOT_ADMITTED_NEW_PROJECT_STAGE_ON_EXISTING_PHYSICAL_PERMIT',mode='bridge',target_name=c.registry.NO3,source=self.source,science='REAL_ZERO_OPTIMIZER_BRIDGE',global_created_epoch=self.pool['created_epoch'],global_expires_epoch=self.pool['expires_epoch'],permit_id='muscat_cpu30',physical_guard_cpus=[30,62],own_science_affinity=[30],new_core_or_global_clock_reset=False,authorizes_only_owned_new_child_guard_abort=True)
  clock=dict(status='ROOT_ADMITTED_NEW_STAGE_CLOCK_WITHOUT_GLOBAL_RESET',mode='bridge',target_name=c.registry.NO3,global_created_epoch=self.pool['created_epoch'],global_expires_epoch=self.pool['expires_epoch'],not_old_diagnostic_clock_reset=True,not_before_epoch=observed,not_after_epoch=self.pool['expires_epoch'])
  funding=dict(status='ROOT_FUNDED_WHOLE_TARGET_ATTEMPT',target_name=c.registry.NO3,source=self.source,reservation_CPU_seconds=11321.738,all_parent_lineage_costs_paid=True,original_failed_costs_refunded=False,historical_parent_lineage_pins=[self.write({'fixture':'historical paid evidence'})],reserved_parent_and_finalize_CPU_seconds=600,charged_before_child_CPU_seconds=600)
  launch=self.write(dict(actual_R_runtime_binding=self.cfg['actual_R_runtime_binding'],source=self.source,status='EXITED',returncode=0,launcher='pinned_native_ELF_no_Rscript_shell_wrapper',reaped=True,drained=True,CPU_accounting_complete=True,preexec_kernel_boundary_proved=True,subprocess_creation_kernel_denied=True))
  project=self.write(dict(schema='r154_project_adapter_validation_v1',source=self.source,toy_default_and_import_parity_pass=True,checkpoint_all_factors_schedules_RNG_IO_verified=True,stock_AST_exactly_preserved=True,no_production_data_used=True,actual_R_runtime_binding=self.cfg['actual_R_runtime_binding'],native_R_ELF_seccomp_startup_pass=True,owned_guard_receipt_pin=launch))
  price=self.write(dict(status='ROOT_REVIEWED_MEASURED_SOURCE_CONTEXT_PRICE',source=self.source,target_name=c.registry.NO3,mode='bridge',project_validation_pin=project,full_peer_resource_interval_seconds=10,owned_lifetime_CPU_wall_interval_seconds=1,measured_full_census_CPU_seconds=.1,conservative_full_census_CPU_seconds=.2,priced_maximum_wall_seconds=600,required_parent_and_finalize_CPU_seconds=312))
  paths=['application/R/525_project_fullstate_consumer.R']+['application/scripts/pricefm/'+v for v in ['525_project_bridge_or_pilot.R','525_run_project_stage.py','525_candidate_registry.py','525_owned_stage_guard.py','524_run_toy_validation.py','522_fixed_state_control.py','522_certificate_reference.py']]
  self.g=dict(mode='bridge',target_name=c.registry.NO3,status='ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY',manifest_sha256=c.ref.sha256(self.config),source=self.source,max_iter=0,new_attempt_index=1,maximum_new_attempts=1,seed=c.registry.target_record(c.registry.load_original_manifest(),c.registry.NO3)['seed'],authorizes_production_acceptance=False,host='muscat',affinity=[30],cores=1,global_contract=self.cfg['global_contract'],memory_GiB=8,disk_GiB=2,permit_id='muscat_cpu30',priority_drain_pin=priority,resource_scope_pin=self.write(scope),clock_authority_pin=self.write(clock),expires_UTC=self.expiry(),funding_pin=self.write(funding),maximum_CPU_seconds=300,maximum_wall_seconds=600,source_bindings=[c.pin(c.ROOT/p) for p in paths],actual_R_runtime_binding=self.cfg['actual_R_runtime_binding'],NO3_candidate_registration_pin=None,project_validation_pin=project,production_price_proof_pin=price)
  self.g['expected_stock_body_sha256']=self.cfg['expected_stock_body_sha256']
  self.g['source_bindings'].append(self.cfg['fixedpoint_helper_source'])
 def expiry(self):return (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=3600)).isoformat()
 def write(self,value):
  self.i+=1;p=self.root/(str(self.i)+'.json');p.write_text(json.dumps(value));return c.pin(p)
 def tearDown(self):self.temp.cleanup()
 def validate(self,g=None):
  gp=self.write(self.g if g is None else g)
  # Only emulate an immutable clean feature checkout. Authority, all file-pin,
  # target, prior, scope, clock, runtime, resource, funding and proof checks run.
  def git(args,**kwargs):
   self.assertEqual(args[0],'git')
   return '1'*40+'\n' if args[1:] == ['rev-parse','HEAD'] else ''
  with patch.object(c.subprocess,'check_output',side_effect=git):
   return c.authority(str(self.config),gp['path'],gp['sha256'])
 def test_valid_metadata31_explicit30_grant_no_move_claim_or_target_open(self):
  with patch.object(c.os,'sched_setaffinity',side_effect=AssertionError('authority must stay31')),patch.object(c,'locked_run',side_effect=AssertionError('no target launch')):
   cfg,original,g,_,_=self.validate()
  self.assertEqual(g['affinity'],[30]);self.assertEqual(os.sched_getaffinity(0),{31})
  self.assertFalse(c.AUDIT.joinpath('claims').exists())
 def test_both_modes_require_exact_source_numeric_proof(self):
  for mode in ('bridge','pilot'):
   g=copy.deepcopy(self.g);g['mode']=mode
   if mode=='pilot':
    # Reach the same mandatory proof gate without requiring a real bridge.
    g['status']='ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY';g['max_iter']=300
    for key in ('resource_scope_pin','clock_authority_pin','production_price_proof_pin'):
     value=c.pinned(g[key]);value['mode']=mode
     if key=='resource_scope_pin':value['science']='NEW_PRODUCTION_INITIALIZATION_PILOT'
     g[key]=self.write(value)
   g['project_validation_pin']=self.write(dict(schema='r154_project_adapter_validation_v1',source=self.source,toy_default_and_import_parity_pass=False))
   with self.subTest(mode=mode),self.assertRaisesRegex(ValueError,'numerical/checkpoint proof absent'):self.validate(g)
 def test_prepared_runtime_false_hard_closes_both_stages(self):
  self.cfg['production_runtime_compatible']=False;self.config.write_text(json.dumps(self.cfg))
  for mode in ('bridge','pilot'):
   g=copy.deepcopy(self.g);g['mode']=mode
   with self.subTest(mode=mode),self.assertRaisesRegex(ValueError,'production stages closed'):self.validate(g)
 def test_scope_clock_cap_source_guard_and_underfunding_negatives(self):
  mutations=[]
  g=copy.deepcopy(self.g);g['max_iter']=600;mutations.append((g,'cap contract'))
  g=copy.deepcopy(self.g);g['source_bindings']=[v for v in g['source_bindings'] if not v['path'].endswith('525_owned_stage_guard.py')];mutations.append((g,'missing source'))
  for key,field,value,pattern in [('resource_scope_pin','science','CERTIFICATE_REFERENCE','science type'),('clock_authority_pin','not_old_diagnostic_clock_reset',False,'clock reset'),('funding_pin','charged_before_child_CPU_seconds',12000,'reservation exceeded'),('production_price_proof_pin','required_parent_and_finalize_CPU_seconds',301,'extrapolation')]:
   g=copy.deepcopy(self.g);obj=c.pinned(g[key]);obj[field]=value;g[key]=self.write(obj);mutations.append((g,pattern))
  for g,pattern in mutations:
   with self.subTest(pattern=pattern),self.assertRaisesRegex(ValueError,pattern):self.validate(g)
 def test_shared_lock_busy_prevents_affinity_move_target_open_or_claim(self):
  # Actual flock contention on private inode, no global science permit touched.
  lockdir=self.root/'locks';lockdir.mkdir();held=open(lockdir/'muscat_cpu30.lock','a+')
  fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
  argv=['control','--config','metadata','--root-grant','metadata','--root-grant-sha256','0'*64]
  with held,patch.object(sys,'argv',argv),patch.object(c,'authority',return_value=(self.cfg,{},self.g,{},{})),patch.object(c.base,'global_permit',return_value={'lock_dir':str(lockdir)}),patch.object(c.os,'sched_setaffinity',side_effect=AssertionError('must not move')),patch.object(c,'locked_run',side_effect=AssertionError('must not open target/claim')):
   with self.assertRaises(BlockingIOError):c.main()

if __name__=='__main__':unittest.main(verbosity=2)
