#!/usr/bin/env python3
"""Synthetic byte/JSON fixtures only; never invoke observers or probe a lock."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
s=importlib.util.spec_from_file_location('priority_drain',HERE/'527_observe_priority_drain.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

class PriorityDrain(unittest.TestCase):
 def fixture(self,root):
  self.root=root;self.index=0
  def write(value):
   self.index+=1;p=root/('fixture_%03d.json'%self.index);p.write_text(json.dumps(value));return m.pin(p)
  self.write=write
  def record(value):return {'pin':write(value),'value':value}
  self.record=record
  identity=lambda n:{'pid':n,'start_ticks':n*2,'boot_id':'synthetic-boot'}
  owned=lambda n,key:{key:False,('expected' if key=='exact_lifetime_live' else 'recorded'):identity(n)}
  unit={'MainPID':'0','Restart':'no','NRestarts':'0','ActiveState':'active','SubState':'exited','Result':'success','ExecMainStatus':'0'}
  authority={k:write({'fixture':'root authority '+k}) for k in ('EE','successor')}
  lvscience=root/'lvscience';lvscience.mkdir();(lvscience/'exit_receipt.json').write_text(json.dumps({'status':'COMPLETE_DIAGNOSTIC'}))
  science=write({'output_dir':str(lvscience)});authority['LV']=write({'stage':{'authority':science}})
  plan={'observers':{k:{'authority_pin':v} for k,v in authority.items()}}
  ee_a=record({'fixture':'completed original EE assessment'});ee_seal=record({'assessment':ee_a['pin']})
  ee={'schema':'r155_final_actual_caller_inspection_v1','status':'READ_ONLY_ACTUAL_SOURCE_METADATA','epoch':time.time(),
   'authority':authority['EE'],'new_forecasts':0,'new_fits':0,'claims_created':0,'signals_sent':0,'services_changed':0,
   'numerical_modules_imported':False,'owned_processes':[owned(1,'exact_lifetime_live'),owned(2,'exact_lifetime_live')],
   'unit_show':dict(unit),'records':{'exit_receipt.json':record({'status':'COMPLETE_INITIAL_PREFIX'}),
    'supervisor_exit_receipt.json':record({'status':'PAYLOAD_EXITED','child_exit_code':0}),
    'assessment.json':ee_a,'assessment_seal.json':ee_seal}}
  lv_a=record({'fixture':'complete LV assessment'})
  lv={'status':'READ_ONLY_EXACT_R155_ADMIN_AND_ORIGINAL_R154_LV_HEALTH','epoch':time.time(),'administrative_authority':authority['LV'],
   'complete_calls':12,'calls_remaining':0,'same_original_permit_free':True,'runtime_mutations':0,'scientific_dispatches':0,'signals':0,
   'actual_processes':[owned(n,'live_exact_lifetime') for n in (3,4,5)],'unit':dict(unit),
   'administrative_records':{'exit_receipt.json':record({'status':'COMPLETE_LV_TRAINING_DIAGNOSTIC_NOT_PROMOTED'})},
   'LV_records':{'supervisor_exit_receipt.json':record({'status':'PAYLOAD_EXITED','child_exit_code':0}),
    'assessment.json':lv_a,'assessment_seal.json':record({'assessment':lv_a['pin']})}}
  qualified=['r134_5c42f007409acfb3'];names=['EE_{}_s{}_S_seed{}'.format(p,s,k) for p in ['C0']+qualified for k in (1,2) for s in (1,2,3)]
  assessment=record({'status':'COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED','required_task_names':names,
   'qualified_from_unchanged_initial_S0':qualified,'automatic_followon':False,'AL_proposal_admitted':False,'all_new_components_independently_revalidated':True})
  successor={'status':'READ_ONLY_SOURCE_BOUND_MATCHED_SEED_OBSERVATION','epoch':time.time(),'authority':authority['successor'],
   'complete_components':12,'required_components':12,'remaining_components':0,'scientifically_complete_and_physically_drained':True,
   'same_original_flock_free':True,'new_fits':0,'new_forecasts':0,'runtime_writes':0,'signals':0,'model_helpers_imported':False,
   'processes':[owned(n,'live_exact_lifetime') for n in (6,7)],'actual_unit':dict(unit),
   'records':{'assessment.json':assessment,'assessment_seal.json':record({'assessment':assessment['pin']}),
    'exit_receipt.json':record({'status':'COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT'}),
    'supervisor_exit_receipt.json':record({'status':'PAYLOAD_EXITED','child_exit_code':0}),
    'full_matched_set.json':record({'required_task_names':names,'components':12}),
    'claim.json':record({'required_tasks':names})}}
  return {'EE':ee,'LV':lv,'successor':successor},plan
 def test_exact_historical_and_current_metadata_yields_priority_contract(self):
  with tempfile.TemporaryDirectory() as d:
   rows,plan=self.fixture(Path(d));result=m.validate_observations(rows,plan,time.time())
   self.assertTrue(result['no_pending_refill']);self.assertTrue(result['no_live_owned_numerical_lifetimes'])
   self.assertEqual(m.read(result['EE_exit'])['status'],'COMPLETE_INITIAL_PREFIX')
   self.assertEqual(m.read(result['LV_exit'])['status'],'COMPLETE_DIAGNOSTIC')
 def test_stale_future_or_wrong_authority_rejected(self):
  for role in m.NAMES:
   for field,value in [('epoch',time.time()-61),('epoch',time.time()+60),('authority',{'path':'/wrong','sha256':'0'*64})]:
    with self.subTest(role=role,field=field),tempfile.TemporaryDirectory() as d:
     rows,plan=self.fixture(Path(d));key='administrative_authority' if role=='LV' and field=='authority' else field;rows[role][key]=value
     with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
 def test_any_live_missing_or_unknown_lifetime_rejected(self):
  for role,key,field in [('EE','owned_processes','exact_lifetime_live'),('LV','actual_processes','live_exact_lifetime'),('successor','processes','live_exact_lifetime')]:
   for value in (True,None):
    with self.subTest(role=role,value=value),tempfile.TemporaryDirectory() as d:
     rows,plan=self.fixture(Path(d));rows[role][key][0][field]=value
     with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
 def test_partial_successor_held_permit_or_restart_rejected(self):
  for key,value in [('remaining_components',1),('complete_components',11),('same_original_flock_free',False),('scientifically_complete_and_physically_drained',False)]:
   with self.subTest(key=key),tempfile.TemporaryDirectory() as d:
    rows,plan=self.fixture(Path(d));rows['successor'][key]=value
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
  for key,value in [('MainPID','12'),('Restart','always'),('NRestarts','1'),('SubState','running')]:
   with self.subTest(unit=key),tempfile.TemporaryDirectory() as d:
    rows,plan=self.fixture(Path(d));rows['successor']['actual_unit'][key]=value
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
 def test_accepted_followon_or_AL_refill_rejected(self):
  for key in ('automatic_followon','AL_proposal_admitted'):
   with self.subTest(key=key),tempfile.TemporaryDirectory() as d:
    rows,plan=self.fixture(Path(d));record=rows['successor']['records']['assessment.json'];value=dict(record['value'],**{key:True});rows['successor']['records']['assessment.json']=self.record(value)
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
 def test_changed_captured_bytes_or_missing_seal_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   rows,plan=self.fixture(Path(d));record=rows['EE']['records']['exit_receipt.json'];Path(record['pin']['path']).write_text('{}')
   with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
  with tempfile.TemporaryDirectory() as d:
   rows,plan=self.fixture(Path(d));del rows['LV']['LV_records']['assessment_seal.json']
   with self.assertRaises(ValueError):m.validate_observations(rows,plan,time.time())
 def test_no_observer_dispatch_or_lock_probe_in_metadata_validator(self):
  with tempfile.TemporaryDirectory() as d:
   rows,plan=self.fixture(Path(d))
   with patch.object(m,'run_observer',side_effect=AssertionError('no actual observer')),patch.object(m,'probe_original_lock',side_effect=AssertionError('no actual lock')):
    m.validate_observations(rows,plan,time.time())
 def test_static_actual_observer_import_closures_are_metadata_only(self):
  paths=[
   '/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r155_ee_final_component_20261027/application/scripts/pricefm/528_run_pricefm_stage_r155_final_component.py',
   '/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r155_lv_handoff_20261027/application/scripts/pricefm/526_run_pricefm_stage_r155_lv_handoff.py',
   '/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r157_hb_parallel_execution_20261028/application/scripts/pricefm/529_run_pricefm_stage_r155_qualified_seeds.py']
  for p in paths:
   values=m.metadata_import_closure(p);self.assertTrue(values);self.assertIn(m.pin(p),values)
  self.assertNotIn('numpy',sys.modules);self.assertNotIn('pandas',sys.modules)
 def test_actual_historical_completion_metadata_read_without_observers(self):
  base=Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns')
  for folder,status in [('pricefm_stage_r155_final_component_818cba5e8e8447489f5c4881620bb30d','COMPLETE_INITIAL_PREFIX'),
                        ('pricefm_stage_r154_lv_361753cd84a64ae69892b8bdcef32a04','COMPLETE_DIAGNOSTIC')]:
   with self.subTest(folder=folder):
    self.assertEqual(m.read(m.pin(base/folder/'exit_receipt.json'))['status'],status)
    supervisor=m.read(m.pin(base/folder/'supervisor_exit_receipt.json'))
    self.assertEqual(supervisor['status'],'PAYLOAD_EXITED');self.assertEqual(supervisor['child_exit_code'],0)
 def test_only_inspect_argv_and_finite_private_guard_are_dispatched(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);authority=root/'authority.json';authority.write_text('{}')
   value={'entry_pin':{'path':'/synthetic/529_run_pricefm_stage_r155_qualified_seeds.py','sha256':'0'*64},
          'authority_pin':m.pin(authority),'preparation_pin':m.pin(authority)}
   deadline='2099-01-01T00:00:00+00:00';captured={}
   def private_guard(command,**kwargs):
    captured.update(command=command,kwargs=kwargs);json.dump({'synthetic_observer':True},kwargs['stdout']);kwargs['stdout'].flush()
    return {'status':'EXITED','returncode':0,**{k:True for k in ('reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled')}}
   with patch.object(m.guard,'run_traced',side_effect=private_guard):result=m.run_observer('successor',value,{'expires_UTC':deadline},root,123)
   self.assertTrue(result['synthetic_observer']);self.assertIn('--inspect',captured['command']);self.assertIn('--preparation',captured['command'])
   self.assertEqual(captured['kwargs']['affinity'],{31});self.assertFalse(captured['kwargs']['require_science_handshake'])
   self.assertEqual(captured['kwargs']['maximum_combined_CPU_seconds'],18);self.assertLessEqual(captured['kwargs']['wall_seconds'],58)
   self.assertFalse(any('/R/' in x for x in captured['kwargs']['bootstrap_exec_allowlist']))
 def test_bad_plan_scope_rejected_before_any_observer_or_probe(self):
  for key,value in [('maximum_combined_CPU_seconds',21),('maximum_wall_seconds',61),('affinity',[30]),('actual_target_inputs',True),('optimizer_invocations',1),('status','ADMITTED_NUMERICAL_WORK')]:
   with self.subTest(key=key),tempfile.TemporaryDirectory() as d:
    plan={'schema':'r157_priority_drain_observation_plan_v1','status':'ROOT_ADMITTED_METADATA_PRIORITY_DRAIN_CAPTURE_ONLY',
      'maximum_combined_CPU_seconds':20,'maximum_wall_seconds':60,'affinity':[31],'actual_target_inputs':False,'optimizer_invocations':0};plan[key]=value
    p=Path(d)/'plan.json';p.write_text(json.dumps(plan))
    with patch.object(m,'run_observer',side_effect=AssertionError('no observer')),patch.object(m,'probe_original_lock',side_effect=AssertionError('no probe')),self.assertRaises(ValueError):m.validate_plan(m.pin(p))

class ActualLVSchema(unittest.TestCase):
 def fixture(self):
  root=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r157_parallel_implementation_20261028/local/ROOT_SYNTHETIC_EXECUTION_01')
  plan=m.read(m.pin(root/'priority_capture_plan.json'))
  rows={k:m.read(m.pin(root/'priority_capture'/(k+'.stdout.json'))) for k in m.NAMES}
  # Re-evaluate immutable historical metadata at its recorded capture clock.
  # This does not make it a fresh current drain proof or call an observer.
  return rows,plan,max(v['epoch'] for v in rows.values())+.01
 def test_actual_capture_unloaded_LV_uses_sealed_exit_not_systemd_defaults(self):
  rows,plan,now=self.fixture();self.assertNotIn('Result',rows['LV']['unit']);self.assertNotIn('ExecMainStatus',rows['LV']['unit'])
  result=m.validate_observations(rows,plan,now)
  self.assertEqual(result['LV_unit_evidence_class'],'UNLOADED_UNIT_DRAIN_ONLY_SCIENTIFIC_SUCCESS_FROM_SEALED_EXIT')
  self.assertEqual(m.read(result['LV_exit'])['status'],'COMPLETE_DIAGNOSTIC')
 def test_actual_LV_active_restarting_live_or_foreign_unit_rejected(self):
  for key,value in [('ActiveState','active'),('SubState','running'),('MainPID','123'),('Restart','always'),('NRestarts','1'),('Id','foreign.service'),('InvocationID','new-invocation'),('KillMode','process')]:
   with self.subTest(key=key):
    rows,plan,now=self.fixture();rows['LV']['unit'][key]=value
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,now)
  rows,plan,now=self.fixture();rows['LV']['actual_processes'][0]['live_exact_lifetime']=True
  with self.assertRaises(ValueError):m.validate_observations(rows,plan,now)
 def test_LV_fallback_never_reached_without_sealed_zero_exit(self):
  for missing in ('supervisor_exit_receipt.json','assessment_seal.json'):
   with self.subTest(missing=missing):
    rows,plan,now=self.fixture();del rows['LV']['LV_records'][missing]
    with patch.object(m,'lv_unit_after_sealed_completion',side_effect=AssertionError('cannot accept before sealed completion')),self.assertRaises(ValueError):m.validate_observations(rows,plan,now)
  rows,plan,now=self.fixture();del rows['LV']['administrative_records']['exit_receipt.json']
  with self.assertRaises(ValueError):m.validate_observations(rows,plan,now)
 def test_missing_unit_exit_status_is_LV_only_and_never_overrides_failure(self):
  for role,key in [('EE','unit_show'),('successor','actual_unit')]:
   with self.subTest(role=role):
    rows,plan,now=self.fixture();rows[role][key].pop('Result');rows[role][key].pop('ExecMainStatus')
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,now)
  for key,value in [('Result','failed'),('ExecMainStatus','1')]:
   with self.subTest(LV_status=key):
    rows,plan,now=self.fixture();rows['LV']['unit'].update(Result='success',ExecMainStatus='0');rows['LV']['unit'][key]=value
    with self.assertRaises(ValueError):m.validate_observations(rows,plan,now)

if __name__=='__main__':unittest.main(verbosity=2)
