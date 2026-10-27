"""Private metadata/lifecycle proofs; no numerical/model library or forecast."""
import importlib.util,json,os,signal,subprocess,sys,tempfile,types,unittest
from unittest.mock import patch
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_seed_contract as c
def module(name,path):
 s=importlib.util.spec_from_file_location(name,HERE/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=module('private_seed_prepare','528_prepare_pricefm_stage_r155_qualified_seeds.py')
r=module('private_seed_runner','529_run_pricefm_stage_r155_qualified_seeds.py')
canonical=module('private_scalar_acceptance_contract','pricefm_r150_contract.py')

class ScientificBoundary(unittest.TestCase):
 def test_metadata_imports_do_not_load_numerical_models(self):
  self.assertFalse(any(name in sys.modules for name in ('numpy','scipy','pandas')))
 def test_exact_half_margin_and_complete_cases(self):
  for a,b,wanted,count in [(10.,10.,[],0),(9.9,10.,[c.A],12),(10.,9.9,[c.B],12),(9.9,9.9,[c.A,c.B],18)]:
   value=c.qualified_from_s0({'C0':10.,c.A:a,c.B:b});self.assertEqual(value['qualified'],wanted);self.assertEqual(value['components'],count)
  for bad in ({'C0':10.,c.A:9.},{'C0':0.,c.A:9.,c.B:8.},{'C0':10.,c.A:float('nan'),c.B:8.}):
   with self.assertRaises(RuntimeError):c.qualified_from_s0(bad)
 def test_exact_matched_sets_no_seed0_duplicates_or_new_nominees(self):
  self.assertEqual(c.names_for([]),[])
  for q,count in [([c.A],12),([c.B],12),([c.A,c.B],18)]:
   names=c.names_for(q);self.assertEqual(len(names),count);self.assertEqual(len(set(names)),count)
   for package in ['C0']+q:self.assertEqual(sum(n.startswith('EE_'+package+'_') for n in names),6)
   self.assertTrue(all(n.endswith(('seed1','seed2')) for n in names))
  for bad in ([c.B,c.A],['other'],['C0'],[c.A,c.A]):
   with self.assertRaises(RuntimeError):c.names_for(bad)
 def test_failure_stops_fullset_without_retry_or_subset(self):
  called=[]
  def one(name):
   called.append(name)
   if len(called)==2:raise RuntimeError('private failure')
   return {}
  with self.assertRaises(RuntimeError):r.run_exact_set(['one','two','three'],one)
  self.assertEqual(called,['one','two'])
 def test_admission_and_full_analysis_required_before_any_claim(self):
  for authority in ({'schema':'r155_ee_qualified_seed_authority_v1','status':'PROPOSED'},
      {'schema':'r155_ee_qualified_seed_authority_v1','status':'ADMITTED','scope_id':'1'*32,'unit':'pricefm-r155-ee-qualified-seeds-'+('1'*32)+'.service','independent_analysis_seal':None,'initial_root_closing_proof':None}):
   with self.assertRaises(RuntimeError):c.validate_authority(authority,{},'unused',{},1,'muscat')
  authority={'schema':'r155_ee_qualified_seed_authority_v1','status':'ADMITTED','scope_id':'1'*32,'unit':'pricefm-r155-ee-qualified-seeds-'+('1'*32)+'.service','independent_analysis_seal':None,'initial_root_closing_proof':None}
  with self.assertRaisesRegex(RuntimeError,'explicit full87'):c.validate_authority(authority,{},'unused',{},1,'muscat')
 def test_final_metrics_use_frozen_light_api(self):
  arrays=object();light=object();seen=[]
  def metrics(value):
   self.assertIs(value,light);return {'AQL':1.25}
  public=types.SimpleNamespace(light=lambda a:light if a is arrays else None,
   validate_arrays=lambda task,a,scaler:seen.append(a is light),metrics=metrics)
  r.revalidate_saved_component(public,{},arrays,{},dict(AQL=1.25));self.assertEqual(seen,[True])
  with self.assertRaises(RuntimeError):r.revalidate_saved_component(public,{},arrays,{},dict(AQL=1.3))
 def test_canonical_three_seed_stability_practical_gain_and_strongest_ties(self):
  def split(values):return {str(k):{str(s):{'AQL':v} for s in (1,2,3)} for k,v in enumerate(values)}
  cases=[([9.7]*3,'ONE_CONDITIONAL_AL_PROPOSAL_NOT_ADMITTED',c.A),
         ([9.4,10.1,9.7],'HOLD_ALGORITHMIC_STABILITY_UNRESOLVED',None),
         ([9.98]*3,'STOP_NO_QUALIFYING_CONFIRMED_LEAD',None)]
  for values,status,lead in cases:
   result=r.final_decision(canonical,{'C0':split([10.]*3),c.A:split(values)},[c.A])
   self.assertEqual(result['disposition'],status);self.assertEqual(result['lead_for_separate_AL_proposal'],lead)
  result=r.final_decision(canonical,{'C0':split([10.]*3),c.A:split([9.7]*3),c.B:split([9.7]*3)},[c.A,c.B])
  self.assertEqual(result['lead_for_separate_AL_proposal'],min(c.A,c.B))
  boundary=r.final_decision(canonical,{'C0':split([8.]*3),c.A:split([8.,7.75,7.875])},[c.A])
  self.assertTrue(boundary['matched_three_seed_results'][c.A]['algorithmic_stability_unresolved'])
  self.assertIsNone(boundary['lead_for_separate_AL_proposal'])
 def test_original_select_branch_replay_no_new_branch_selection(self):
  old={'pricing':dict(estimated_B1_max_cpu_seconds=100.,estimated_B2_max_cpu_seconds=151.,benchmark_adjusted_available_CPU_seconds=200.,branch='B1',budget_disposition='ADMITTED_B1'),'prefix_contract':dict(branch='B1')}
  self.assertEqual(r.replay_original_branch(canonical,old)['branch'],'B1')
  old['pricing']['estimated_B2_max_cpu_seconds']=150.
  with self.assertRaises(RuntimeError):r.replay_original_branch(canonical,old)

class PriceAndLifecycle(unittest.TestCase):
 def test_readonly_prepared_health_has_no_claim_or_model_call(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);source=dict(branch='work/private',head='1'*40)
   def save(name,value):
    path=root/name;path.write_text(json.dumps(value));return c.pin(path)
   original=save('original.json',{});lock=root/'muscat_cpu30.lock';lock.touch()
   glob=save('global.json',dict(lock_dir=str(root),expires_epoch=9999999999))
   pp=save('prep.json',dict(source=source,execution_source_sha256={},tasks=[],original_preparation=original))
   ap=save('authority.json',dict(schema='r155_ee_qualified_seed_authority_v1',status='PROPOSED',source=source,
    preparation=pp,output_dir=str(root/'not_created'),unit='future.service',required_task_names=c.names_for([c.A]),max_new_tasks=12,
    global_contract=glob,original_global_lock_identity=dict(device=lock.stat().st_dev,inode=lock.stat().st_ino),start_epoch=None,expires_epoch=None))
   unit='Id=future.service\nMainPID=0\nInvocationID=\nActiveState=inactive\nSubState=dead'
   with patch.object(c,'source_identity',return_value=source),patch.object(c.subprocess,'check_output',return_value=unit):
    result=r.inspect(pp['path'],ap['path'],ap['sha256'])
   self.assertEqual(result['phase'],'PREPARED_NO_SCIENTIFIC_CLAIM');self.assertEqual(result['remaining_components'],12)
   self.assertEqual(result['runtime_writes'],0);self.assertFalse((root/'not_created').exists())
 def fixture(self):
  tasks=[];historic={}
  for name in c.names_for([c.A,c.B]):
   tasks.append(dict(name=name,daily_origin_positions=list(range(24)),clock_offsets_steps=[0,24,48,72],origin_timestamps={str(o):['2023-01-01T00:00:00+00:00']*24 for o in (0,24,48,72)}))
   historic[name]=dict(setup_cpu_seconds_once=2.,estimated_cpu_seconds=100.,estimated_max_chunk_cpu_seconds=10.)
  timing=[dict(complete=True,normalized_CPU_per_window=1.,measured_CPU_seconds=100.) for _ in range(6)]
  timing += [dict(complete=True,normalized_CPU_per_window=None,measured_CPU_seconds=None) for _ in range(3)]
  return tasks,historic,timing,dict(upper_scan_CPU=.5)
 def test_undiscounted_full12_and18_prices_no_old_credit(self):
  tasks,hist,timing,scan=self.fixture();value=p.prices(tasks,hist,timing,scan)
  self.assertEqual(value['status'],'COMPLETE_INITIAL_S0_TIMING_PRICE_NOT_ADMISSION')
  for q in ([c.A],[c.B],[c.A,c.B]):
   case=value['scenarios']['+'.join(q)];self.assertEqual(case['max_new_tasks'],len(c.names_for(q)))
   self.assertEqual(case['required_task_names'],c.names_for(q));self.assertTrue(case['no_old_credit']);self.assertFalse(case['automatic_retry'])
   self.assertGreater(case['full_prefix_CPU'],sum(hist[n]['estimated_cpu_seconds'] for n in case['required_task_names']))
   self.assertGreater(case['admin_drain_CPU'],case['guardian_CPU_reserve'])
  timing[-1]['complete']=False
  self.assertEqual(p.prices(tasks,hist,timing,scan)['status'],'PROVISIONAL_INITIAL_S0_INCOMPLETE_NOT_ADMISSIBLE')
 def test_unfundable_guard_rate_rejected(self):
  tasks,hist,timing,scan=self.fixture();scan['upper_scan_CPU']=3.
  with self.assertRaisesRegex(RuntimeError,'guard cost'):p.prices(tasks,hist,timing,scan)
 def test_original_flock_busy_and_inode_replacement(self):
  import fcntl
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'muscat_cpu30.lock';path.touch();identity=dict(device=path.stat().st_dev,inode=path.stat().st_ino);glob=dict(lock_dir=d)
   self.assertTrue(c.same_lock_free(glob,identity))
   with path.open('r+') as stream:
    fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB);self.assertFalse(c.same_lock_free(glob,identity))
   with path.open('r+'):
    path.unlink();path.touch()
    with self.assertRaisesRegex(RuntimeError,'replaced'):c.same_lock_free(glob,identity)
 def test_inherited_guard_unchanged_and_hard_limit_funded(self):
  for name in ('_start_guardian','scan_peers','check','close'):self.assertIs(getattr(c.SeedLease,name),getattr(c.BaseLease,name))
  with self.assertRaises(RuntimeError):c.funded_payload_CPU_limit(.1,20000,200,600,120)
  self.assertGreater(c.funded_payload_CPU_limit(.1,20000,200,600,30000),18000)
 def test_private_held_child_identity_and_only_direct_signal(self):
  from pricefm_r155_completion_contract import signal_unreaped_direct_child
  child=subprocess.Popen([sys.executable,'-B','-c','import time;time.sleep(10)']);identity=c.process_identity(child.pid)
  try:
   with self.assertRaises(RuntimeError):signal_unreaped_direct_child(child.pid,dict(identity,start_ticks=identity['start_ticks']+1))
   self.assertIsNone(child.poll());signal_unreaped_direct_child(child.pid,identity);self.assertEqual(child.wait(),-signal.SIGKILL)
  finally:
   if child.poll() is None:child.kill();child.wait()

class CompleteInitialPrivateProof(unittest.TestCase):
 def fixture(self,root,qualifies=True):
  out=root/'science';out.mkdir();control=root/'old525';control.mkdir();source={'branch':'work/old','head':'b'*40}
  def save(path,value):
   path=Path(path);path.write_text(json.dumps(value));return c.pin(path)
  empty=save(root/'empty.json',{});entry=root/'524.py';entry.write_text('frozen scientific source')
  originalprep=save(root/'prep.json',{});nominees=dict(A=c.A,B=c.B,full_D_complete=78)
  template=dict(source=source,max_new_tasks=2,output_dir=str(out),scope_id='original',LV_completed_drain_proof=None)
  templatepin=save(root/'template.json',template);endowment=dict(source=source,child_authority_template=templatepin,output_dir=str(control))
  endowmentpin=save(root/'endowment.json',endowment);actual=dict(template,LV_completed_drain_proof=empty)
  grantpin=save(root/'root_actual_authority.json',actual);runtimepin=save(out/'authority.json',actual)
  argv=['python','-B',str(entry),'--preparation',originalprep['path'],'--authority',grantpin['path'],'--authority-sha256',grantpin['sha256']]
  life=dict(pid=10,start_ticks=100,boot_id='boot',argv=argv)
  save(out/'claim.json',dict(authority=grantpin,process=life));save(out/'exit_receipt.json',dict(status='COMPLETE_INITIAL_PREFIX'))
  save(out/'supervisor_exit_receipt.json',dict(child_exit_code=0,parent=life,payload=dict(life,pid=11)))
  execution=dict(source=source,scope_id='original',authority=runtimepin,composite_inventory=empty)
  losses={'C0':10.,c.A:9.9 if qualifies else 10.,c.B:10.};decision=c.qualified_from_s0(losses)
  assessment=dict(execution=execution,full_D_components=78,new_D=0,new_S0=2,new_component_names=c.MISSING,new_chunks=108,
   extra_seed_admitted=False,new_fits=0,official_origins=0,nominees={'A':c.A,'B':c.B},
   matched_S0_AQL=losses,extra_seed_qualified=decision['qualified'],conditional_extra_components=decision['components'],
   practical_margin=decision['practical_margin'],matched_S0_gains=decision['gains'],status='COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED' if qualifies else 'COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER')
  apin=save(out/'assessment.json',assessment);save(out/'assessment_seal.json',dict(assessment=apin,execution=execution))
  save(control/'claim.json',dict(authority=endowmentpin,process=dict(life,pid=12)))
  epin=save(control/'exit_receipt.json',dict(status='STOPPED_NO_RETRY',scientific_reaped_CPU_seconds=0,claims_and_failed_charges_retained=True,source=source,inclusive_own_and_reaped_CPU_seconds=.275))
  unit='direct.service';launch=dict(unit=dict(Id=unit,InvocationID='exact',MainPID='10'))
  launchpin=save(root/'launch.json',launch)
  direct=dict(schema='r155_root_direct_EE_execution_v1',status='ROOT_ADMITTED_ONCE',source=source,source_root=str(root),entry=c.pin(entry),
   preparation=originalprep,child_template=templatepin,authority=grantpin,automatic_retry=False,required_RemainAfterExit=True,
   explicit_manual_amendment=empty,prior_conditional_endowment=endowmentpin,prior_conditional_exit=epin,prior_conditional_CPU_retained=.275,
   root_launch_receipt_path=launchpin['path'],python='python',direct_unit=unit)
  directpin=save(root/'direct.json',direct)
  closing=dict(schema='r155_root_direct_EE_closeout_v1',status='PASS',evidence=[directpin,launchpin,grantpin,apin,c.pin(out/'assessment_seal.json'),c.pin(out/'exit_receipt.json'),c.pin(out/'supervisor_exit_receipt.json')])
  closingpin=save(root/'closing.json',closing)
  analysis=dict(status='PASS_COMPLETE_EE_SAVED_ARRAY_ANALYSIS',independent_all78D_and9S0_array_arithmetic=True,equal_three_split_macro=True,completed_assessment=apin,
   unchanged_rule_qualified=decision['qualified'],prospective_extra_seed_components=decision['components'],algorithmic_three_seed_stability_established=False,
   input_pins=[],analysis_source=c.pin(entry),matched_macro={'S':{p:{'AQL':v} for p,v in assessment['matched_S0_AQL'].items()}})
  analysispin=save(root/'analysis.json',analysis);aseal=save(root/'analysis_seal.json',dict(status='PASS',analysis=analysispin))
  lock=root/'muscat_cpu30.lock';lock.touch();glob=save(root/'global.json',dict(lock_dir=str(root)))
  prep=dict(initial_child_template=templatepin,initial_endowment=endowmentpin,initial_source=source,composite_inventory=empty,
   nominees=save(root/'nominees.json',nominees),initial_direct_execution_manifest=directpin,initial_source_root=str(root),
   initial_scientific_entry=str(entry),initial_preparation=originalprep,global_contract=glob,
   original_global_lock_identity=dict(device=lock.stat().st_dev,inode=lock.stat().st_ino))
  properties='\n'.join(k+'='+v for k,v in dict(Id=unit,MainPID='0',InvocationID='exact',ActiveState='active',SubState='exited',RemainAfterExit='yes',Restart='no',NRestarts='0',KillMode='process',Result='success',ExecMainStatus='0').items())
  return prep,aseal,closingpin,properties,out,root/'launch.json'
 def test_complete_manual_initial_retained_unit_and_external_authority_path(self):
  with tempfile.TemporaryDirectory() as d:
   prep,analysis,closing,properties,out,launch=self.fixture(Path(d))
   with patch.object(c,'process_identity',return_value=None),patch.object(c.subprocess,'check_output',return_value=properties):
    gate=c.complete_initial(prep,analysis,closing)
   self.assertEqual(gate['decision']['qualified'],[c.A]);self.assertTrue(gate['physical_drain'])
 def test_unloaded_wrong_invocation_live_lifetime_or_missing_closing_pins_denied(self):
  for kind in ('unloaded','wrong_invocation','live','missing_pin','wrong_initial_loss'):
   with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
    prep,analysis,closing,properties,out,launch=self.fixture(Path(d));live=None
    if kind=='unloaded':properties='Id=direct.service\nMainPID=0\nInvocationID=\nActiveState=inactive'
    if kind=='wrong_invocation':properties=properties.replace('InvocationID=exact','InvocationID=other')
    if kind=='live':live=json.loads((out/'claim.json').read_text())['process']
    if kind=='missing_pin':
     x=json.loads(Path(closing['path']).read_text());x['evidence'].pop();Path(closing['path']).write_text(json.dumps(x));closing=c.pin(closing['path'])
    if kind=='wrong_initial_loss':
     seal=json.loads(Path(analysis['path']).read_text());data=json.loads(Path(seal['analysis']['path']).read_text());data['matched_macro']['S']['C0']['AQL']+=1
     Path(seal['analysis']['path']).write_text(json.dumps(data));seal['analysis']=c.pin(seal['analysis']['path']);Path(analysis['path']).write_text(json.dumps(seal));analysis=c.pin(analysis['path'])
    with patch.object(c,'process_identity',return_value=live),patch.object(c.subprocess,'check_output',return_value=properties):
     with self.assertRaises(RuntimeError):c.complete_initial(prep,analysis,closing)
 def test_no_qualifier_creates_only_audit_disposition_no_science_claim(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);prep,analysis,closing,properties,out,launch=self.fixture(root,False)
   pp=root/'seedprep.json';pp.write_text(json.dumps(prep));destination=root/'NO_SCIENCE.json'
   with patch.object(c,'process_identity',return_value=None),patch.object(c.subprocess,'check_output',return_value=properties):
    result=p.no_science_disposition(pp,analysis['path'],closing['path'],destination)
   self.assertEqual(result['status'],'NO_SCIENCE_NEEDED_NO_CLAIM_NO_DISPATCH');self.assertEqual(result['claims_created'],0)
   self.assertFalse((root/'seed_science_namespace').exists())

if __name__=='__main__':unittest.main()
