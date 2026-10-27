"""Private metadata/lifecycle proofs; no numerical/model library or forecast."""
import copy,importlib.util,json,os,signal,subprocess,sys,tempfile,types,unittest
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
import pricefm_r155_metadata_waiter as waiter

class MetadataWaiterRole(unittest.TestCase):
 def fixture(self):
  rule=json.loads((c.R155/'review/legacy_490_waiter_audit_03/LEGACY_490_ROLE_PROPOSAL_01.json').read_text())
  process=dict(boot_id='boot',pid=123,start_ticks=456,cmdline_sha256='command',argv=rule['argv_exact'])
  current=dict(process,state='S',ppid=rule['parent']['pid'],uid=[rule['owner_uid']]*4,cwd=rule['cwd_exact'],
   executable=rule['resolved_executable'],threads=[dict(tid=123,cpus=rule['thread_mask_exact'])])
  parent={k:rule['parent'][k] for k in ('pid','start_ticks','boot_id','cmdline_sha256','executable')};parent['uid']=[rule['parent']['uid']]*4
  contract=rule['unit'];unit=dict(Id=contract['Id'],LoadState='loaded',ActiveState='active',SubState='running',
   MainPID='123',ExecMainPID='123',WorkingDirectory=contract['WorkingDirectory'],FragmentPath=contract['FragmentPath'],
   Restart=contract['Restart'],KillMode=contract['KillMode'],InvocationID='exact',
   ExecStart='{ path='+rule['interpreter']['path']+' ; argv[]='+' '.join(rule['argv_exact'])+' ; ignore_errors=no ; pid=123 ; status=0/0 }')
  pins=[rule['script'],rule['interpreter'],rule['parent']['executable_pin'],contract['fragment_pin'],*rule['configuration_pins']]
  observation=dict(observed=True,candidate_lifetime=list(waiter.lifetime(process)),current=current,closing_identity=dict(current),
   parent=parent,environment=rule['expected_thread_environment'].copy(),environment_absent={k:True for k in rule['environment_must_be_absent']},
   hashes={p['path']:p['sha256'] for p in pins},source=rule['source'].copy(),unit=unit,unit_by_PID=contract['Id'],unit_proof_epoch=1.)
  return process,rule,observation
 def test_exact_role_and_new_verified_lifetime_positive(self):
  process,rule,obs=self.fixture();self.assertTrue(waiter.match_legacy_490(process,rule,obs))
  process['pid']=124;obs['candidate_lifetime']=list(waiter.lifetime(process))
  for key in ('current','closing_identity'):obs[key]['pid']=124
  obs['current']['threads']=[dict(tid=124,cpus=rule['thread_mask_exact'])]
  obs['unit']['MainPID']=obs['unit']['ExecMainPID']='124'
  self.assertTrue(waiter.match_legacy_490(process,rule,obs))
 def test_all_narrow_role_negative_boundaries(self):
  mutations=[lambda p,r,o:o.update(observed=False),lambda p,r,o:o['source'].update(clean=False),
   lambda p,r,o:o['source'].update(head='other'),lambda p,r,o:o['hashes'].update({r['script']['path']:'other'}),
   lambda p,r,o:o['hashes'].update({r['configuration_pins'][0]['path']:'other'}),
   lambda p,r,o:o['hashes'].update({r['interpreter']['path']:'other'}),lambda p,r,o:o['current'].update(cwd='other'),
   lambda p,r,o:p.update(argv=[*p['argv'],'--extra']),lambda p,r,o:o['current'].update(argv=[*r['argv_exact'][:3],'controller']),
   lambda p,r,o:o['unit'].update(Id='other'),lambda p,r,o:o['unit'].update(MainPID='other'),
   lambda p,r,o:o['unit'].update(ExecMainPID='other'),lambda p,r,o:o['unit'].update(ExecStart=o['unit']['ExecStart'].replace(' 300',' 301')),
   lambda p,r,o:o['parent'].update(start_ticks=0),lambda p,r,o:o['parent'].update(boot_id='other'),
   lambda p,r,o:o['parent'].update(uid=[0]*4),lambda p,r,o:o['parent'].update(executable='other'),
   lambda p,r,o:o['current']['threads'].append(dict(tid=125,cpus=r['thread_mask_exact'])),
   lambda p,r,o:o['current']['threads'][0].update(cpus=[31]),lambda p,r,o:o['environment'].update(OMP_NUM_THREADS='2'),
   lambda p,r,o:o['environment_absent'].update(PYTHONPATH=False),lambda p,r,o:o.update(unit_by_PID='other'),
   lambda p,r,o:o['unit'].update(InvocationID=''),lambda p,r,o:r.update(expires_epoch=1),
   lambda p,r,o:o['closing_identity'].update(start_ticks=0)]
  for i,mutate in enumerate(mutations):
   with self.subTest(case=i):
    process,rule,obs=self.fixture();mutate(process,rule,obs);self.assertFalse(waiter.match_legacy_490(process,rule,obs))
 def test_missing_observation_fails_closed_and_irrelevant_peers_do_not_probe(self):
  process,rule,obs=self.fixture()
  with patch.object(waiter,'_static',side_effect=AssertionError('unrelated peer must not probe')):
   other=dict(process,argv=['python','unrelated.py']);self.assertFalse(waiter.observe_legacy_490(other,rule)['observed'])
  with patch.object(waiter,'_static',return_value={}),patch.object(waiter,'_identity',side_effect=FileNotFoundError()):
   failed=waiter.observe_legacy_490(process,rule);self.assertFalse(waiter.match_legacy_490(process,rule,failed))
 def test_adapter_preserves_known_state_conflicts_and_unrelated_unknowns(self):
  process,rule,obs=self.fixture();known=dict(process,classifier_reason='known_lifetime_state_changed')
  other=dict(process,pid=999,classifier_reason='unreviewed_numerical_process_intersects_physical_permit')
  unknown=dict(process,classifier_reason='unreviewed_numerical_process_intersects_physical_permit')
  with patch.object(c,'peer_conflicts',return_value=[known,other,unknown]),patch.object(c,'observe_legacy_490',return_value=obs):
   remaining,accepted=c.reviewed_peer_conflicts(30,{},set(),[process],{},[30,62],rule,{})
  self.assertEqual(remaining,[known,other]);self.assertEqual(len(accepted),1);self.assertTrue(accepted[0]['positive_match'])
 def test_new_rejection_receipt_declares_policy_addition_truthfully(self):
  with tempfile.TemporaryDirectory() as d:
   lease=c.SeedLease.__new__(c.SeedLease);lease.out=Path(d)
   lease.a=dict(physical_sibling_cpus=[30,62],legacy_metadata_role={'path':'role','sha256':'1'*64},legacy_metadata_role_helper={'path':'helper','sha256':'2'*64})
   with self.assertRaises(RuntimeError):lease.reject_peers([dict(pid=999)],'private')
   receipt=json.loads(next((Path(d)/'peer_rejections').glob('*.json')).read_text())
   self.assertTrue(receipt['base_numerical_detection_unchanged']);self.assertTrue(receipt['reviewed_admin_role_added'])
   self.assertNotIn('classifier_unchanged',receipt);self.assertFalse(receipt['retry_authorized'])

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
 def test_partial_cpu_uses_new_plus_included_proof_not_full_cohort(self):
  descriptors=[dict(name='clock00_part000',origin_positions=list(range(8))),
   dict(name='clock00_part001',origin_positions=list(range(8,16))),
   dict(name='clock00_part002',origin_positions=list(range(16,20)))]
  with patch.object(c,'chunks',return_value=descriptors):
   self.assertEqual(p.partial_public_windows({},set(['clock00_part000'])),20)
   self.assertEqual(p.partial_public_windows({},set(['clock00_part000','clock00_part001'])),12)
   for retained in (set(),{'unknown'},{'clock00_part001'},set(d['name'] for d in descriptors)):
    with self.assertRaises(RuntimeError):p.partial_public_windows({},retained)
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
  for name in ('_start_guardian','check','close'):self.assertIs(getattr(c.SeedLease,name),getattr(c.BaseLease,name))
  self.assertIsNot(c.SeedLease.scan_peers,c.BaseLease.scan_peers)
  self.assertIsNot(c.SeedLease.reject_peers,c.BaseLease.reject_peers)
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
  def save(path,value):
   path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value));return c.pin(path)
  source=dict(branch='work/final',head='b'*40);source_root=root/'final_source'
  helper=source_root/'application/scripts/pricefm/pricefm_r155_final_contract.py';helper.parent.mkdir(parents=True)
  helper.write_text('def verify_final_initial_closure(manifest_pin):\n raise RuntimeError("private fixture must supply explicit closure helper")\n')
  empty=save(root/'empty.json',{});out=root/'final_science'
  losses={'C0':10.,c.A:9.9 if qualifies else 10.,c.B:10.};decision=c.qualified_from_s0(losses)
  assessment=dict(full_D_components=78,full_S0_components=9,new_D=0,new_S0=1,new_component_names=[c.MISSING[1]],new_chunks=73,
   extra_seed_admitted=False,new_fits=0,official_origins=0,nominees={'A':c.A,'B':c.B},matched_S0_AQL=losses,
   extra_seed_qualified=decision['qualified'],conditional_extra_components=decision['components'],
   practical_margin=decision['practical_margin'],matched_S0_gains=decision['gains'],
   status='COMPLETE_INITIAL_PREFIX_SEED_STABILITY_DEFERRED' if qualifies else 'COMPLETE_INITIAL_PREFIX_NO_S0_QUALIFIER')
  apin=save(out/'assessment.json',assessment);sealp=save(out/'assessment_seal.json',dict(assessment=apin))
  closing=save(root/'closing.json',dict(assessment_seal=sealp,supervisor_exit=empty,launch_receipt=empty))
  finalprep=save(root/'finalprep.json',{})
  manifest=dict(schema='r155_root_final_EE_execution_v1',status='ROOT_ADMITTED_ONCE',source=source,source_root=str(source_root),
   preparation=finalprep,root_closing_proof_path=closing['path'],authority=empty)
  manifestpin=save(root/'final_manifest.json',manifest)
  closure=dict(status='PASS_COMPLETE_INITIAL_METADATA_CLOSURE',source=source,execution_manifest=manifestpin,closing=closing,
   assessment_pin=apin,assessment=assessment,execution={'source':source},paid_scope_chain={'scopes':['R154_INCOMPLETE','ce9_INCOMPLETE']},
   physical_drain=dict(exact_lifetimes_gone=True,same_global_flock_free=True))
  analysis=dict(status='PASS_COMPLETE_EE_SAVED_ARRAY_ANALYSIS',independent_all78D_and9S0_array_arithmetic=True,
   equal_three_split_macro=True,completed_assessment=apin,unchanged_rule_qualified=decision['qualified'],
   prospective_extra_seed_components=decision['components'],algorithmic_three_seed_stability_established=False,
   input_pins=[],analysis_source=c.pin(helper),matched_macro={'S':{p:{'AQL':v} for p,v in losses.items()}})
  analysispin=save(root/'analysis.json',analysis);aseal=save(root/'analysis_seal.json',dict(status='PASS',analysis=analysispin))
  prep=dict(initial_final_execution_manifest=manifestpin,initial_final_contract=c.pin(helper),initial_final_source=source,
   initial_final_source_root=str(source_root),initial_final_preparation=finalprep,
   nominees=save(root/'nominees.json',dict(A=c.A,B=c.B,full_D_complete=78)))
  return prep,aseal,closing,closure,out
 def test_complete_final_route_preserves_both_incomplete_predecessors(self):
  with tempfile.TemporaryDirectory() as d:
   prep,analysis,closing,closure,out=self.fixture(Path(d))
   helper=types.SimpleNamespace(verify_final_initial_closure=lambda pin:closure)
   with patch.object(c,'load_module',return_value=helper) as loaded:
    gate=c.complete_initial(prep,analysis,closing)
   loaded.assert_called_once_with('r155_pinned_final_initial_closure',prep['initial_final_contract']['path'],prep['initial_final_contract']['sha256'])
   self.assertEqual(gate['decision']['qualified'],[c.A]);self.assertTrue(gate['physical_drain'])
   self.assertEqual(gate['all_prior_paid_scopes_retained']['scopes'],['R154_INCOMPLETE','ce9_INCOMPLETE'])
 def test_old_failed_direct_route_missing_analysis_or_final_pin_denied(self):
  for prep,analysis,closing in [({},None,None),({'initial_direct_execution_manifest':{}},{},{}),({'initial_final_execution_manifest':None},{},{})]:
   with self.assertRaises(RuntimeError):c.complete_initial(prep,analysis,closing)
 def test_pinned_final_helper_real_loader_signature_and_source_bytes(self):
  with tempfile.TemporaryDirectory() as d:
   prep,analysis,closing,closure,out=self.fixture(Path(d));helper=Path(prep['initial_final_contract']['path'])
   helper.write_text('import json\ndef verify_final_initial_closure(manifest_pin):\n return json.loads('+repr(json.dumps(closure))+')\n')
   prep['initial_final_contract']=c.pin(helper)
   seal=c.verify_pin(analysis);data=c.verify_pin(seal['analysis']);data['analysis_source']=c.pin(helper)
   Path(seal['analysis']['path']).write_text(json.dumps(data));seal['analysis']=c.pin(seal['analysis']['path'])
   Path(analysis['path']).write_text(json.dumps(seal));analysis=c.pin(analysis['path'])
   gate=c.complete_initial(prep,analysis,closing);self.assertEqual(gate['decision']['components'],12)
 def test_wrong_drain_closing_full_count_qualification_or_analysis_denied(self):
  for kind in ('live_lifetime','busy_lock','wrong_closing','only8S0','wrong_rule','wrong_analysis','replaced_helper'):
   with self.subTest(kind=kind),tempfile.TemporaryDirectory() as d:
    prep,analysis,closing,closure,out=self.fixture(Path(d))
    if kind=='live_lifetime':closure['physical_drain']['exact_lifetimes_gone']=False
    if kind=='busy_lock':closure['physical_drain']['same_global_flock_free']=False
    if kind=='wrong_closing':closure['closing']=dict(path='other',sha256='0'*64)
    if kind in ('only8S0','wrong_rule'):
     data=closure['assessment'];data['full_S0_components']=8 if kind=='only8S0' else 9
     if kind=='wrong_rule':data['conditional_extra_components']=18
     (out/'assessment.json').write_text(json.dumps(data));closure['assessment_pin']=c.pin(out/'assessment.json')
    if kind=='wrong_analysis':
     seal=c.verify_pin(analysis);data=c.verify_pin(seal['analysis']);data['matched_macro']['S']['C0']['AQL']+=1
     Path(seal['analysis']['path']).write_text(json.dumps(data));seal['analysis']=c.pin(seal['analysis']['path'])
     Path(analysis['path']).write_text(json.dumps(seal));analysis=c.pin(analysis['path'])
    if kind=='replaced_helper':Path(prep['initial_final_contract']['path']).write_text('replacement')
    helper=types.SimpleNamespace(verify_final_initial_closure=lambda pin:closure)
    with patch.object(c,'load_module',return_value=helper):
     with self.assertRaises(RuntimeError):c.complete_initial(prep,analysis,closing)
 def test_no_qualifier_creates_only_audit_disposition_no_science_claim(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d);prep,analysis,closing,closure,out=self.fixture(root,False)
   pp=root/'seedprep.json';pp.write_text(json.dumps(prep));destination=root/'NO_SCIENCE.json'
   with patch.object(c,'load_module',return_value=types.SimpleNamespace(verify_final_initial_closure=lambda pin:closure)):
    result=p.no_science_disposition(pp,analysis['path'],closing['path'],destination)
   self.assertEqual(result['status'],'NO_SCIENCE_NEEDED_NO_CLAIM_NO_DISPATCH');self.assertEqual(result['claims_created'],0)
   self.assertFalse((root/'seed_science_namespace').exists())

if __name__=='__main__':unittest.main()
