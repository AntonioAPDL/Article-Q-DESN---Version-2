"""Private metadata/lifecycle proofs; no numerical/model library or forecast."""
import importlib.util,os,signal,subprocess,sys,tempfile,types,unittest
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import pricefm_r155_seed_contract as c
def module(name,path):
 s=importlib.util.spec_from_file_location(name,HERE/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=module('private_seed_prepare','528_prepare_pricefm_stage_r155_qualified_seeds.py')
r=module('private_seed_runner','529_run_pricefm_stage_r155_qualified_seeds.py')

class ScientificBoundary(unittest.TestCase):
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
      {'schema':'r155_ee_qualified_seed_authority_v1','status':'ADMITTED','scope_id':'1'*32,'independent_analysis_seal':None,'initial_root_closing_proof':None}):
   with self.assertRaises(RuntimeError):c.validate_authority(authority,{},'unused',{},1,'muscat')
  authority={'schema':'r155_ee_qualified_seed_authority_v1','status':'ADMITTED','scope_id':'1'*32,'independent_analysis_seal':None,'initial_root_closing_proof':None}
  with self.assertRaisesRegex(RuntimeError,'explicit full87'):c.validate_authority(authority,{},'unused',{},1,'muscat')
 def test_final_metrics_use_frozen_light_api(self):
  arrays=object();light=object();seen=[]
  def metrics(value):
   self.assertIs(value,light);return {'AQL':1.25}
  public=types.SimpleNamespace(light=lambda a:light if a is arrays else None,
   validate_arrays=lambda task,a,scaler:seen.append(a is light),metrics=metrics)
  r.revalidate_saved_component(public,{},arrays,{},dict(AQL=1.25));self.assertEqual(seen,[True])
  with self.assertRaises(RuntimeError):r.revalidate_saved_component(public,{},arrays,{},dict(AQL=1.3))

class PriceAndLifecycle(unittest.TestCase):
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

if __name__=='__main__':unittest.main()
