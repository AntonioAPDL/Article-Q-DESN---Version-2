"""Private metadata fixtures: source-derived factories, gate and wrapper order."""
import ast,copy,inspect,json,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
import future_cost_startup as h

class StartupTests(unittest.TestCase):
 def fixture(self,study='FI'):
  sources={'module'+str(i)+'.py':str(i)*64 for i in range(17)}
  release=dict(study=study,purpose='COST_ONLY',task_key='future-'+study,scope_id='future-'+study,
   source_hashes=sources,policy_pin={'path':'/policy','sha256':'p'},resources=dict(cpus=1,cpu_seconds=1200,wall_seconds=1200,memory_MiB=4096),control_cpu_scope={'scope_id':'future-control'})
  ticket=dict(schema=h.SCHEMA,status='ROOT_ADMITTED_FUTURE_COST_STARTUP',controller=h.a.OWNER,
   study=study,task_key=release['task_key'],scope_id=release['scope_id'],job_id='999999',created_epoch=10,expires_epoch=100,
   budget=dict(science_CPU=1200,science_wall=1200,control_CPU=230,priced_maximum_CPU=217,parent_CPU=60,
    parent_slice_CPU=8,lifetimes=7,parent_reservations_CPU=56,transfers=6,metadata=20,refreshes=1,ready_watches=1))
  decision=dict(schema='r160_future_cost_replacement_decision_v1',status=h.DECISION,controller=h.a.OWNER,
   study=study,replacement_task_key=release['task_key'],scope_id=release['scope_id'],new_intents_maximum=1,
   old_charges_refunded=False,real_FI_overrun_cleared=False,old_spent_regions_preserved=True,
   scientific_protocol_unchanged=True,expires_epoch=100)
  protocol=dict(status=h.PROTOCOL,controller=h.a.OWNER,study=study,replacement_task_key=release['task_key'],
   authoritative_routes=sorted(h.ROUTES),preserves_all_old_claims_charges_and_violations=True,source17=sources)
  return ticket,decision,protocol,release
 def test_future_gate_exact_both_studies(self):
  for study in ('FI','DK2'):
   f=self.fixture(study);self.assertIs(h.validate_future_ticket(*f,now=20),f[0])
 def test_all_current_keys_scopes_job_and_closed03_reject(self):
  for old in h.OLD_KEYS:
   t,d,p,r=self.fixture();t['task_key']=r['task_key']=d['replacement_task_key']=p['replacement_task_key']=old
   with self.assertRaises(ValueError):h.validate_future_ticket(t,d,p,r,now=20)
  for old in h.OLD_SCOPES:
   t,d,p,r=self.fixture();t['scope_id']=r['scope_id']=d['scope_id']=old
   with self.assertRaises(ValueError):h.validate_future_ticket(t,d,p,r,now=20)
  t,d,p,r=self.fixture();t['job_id']='869420'
  with self.assertRaises(ValueError):h.validate_future_ticket(t,d,p,r,now=20)
  t,d,p,r=self.fixture();r['control_cpu_scope']['scope_id']='r158_initial_recovery_20261028_03'
  with self.assertRaises(ValueError):h.validate_future_ticket(t,d,p,r,now=20)
 def test_decision_protocol_source_caps_and_expiry_are_not_funding_shortcuts(self):
  for change in ('cleared','refund','routes','source','study','expiry','slice','transfers','memory'):
   t,d,p,r=self.fixture()
   if change=='cleared':d['real_FI_overrun_cleared']=True
   if change=='refund':d['old_charges_refunded']=True
   if change=='routes':p['authoritative_routes']=['reserve']
   if change=='source':p['source17']={}
   if change=='study':p['study']='DK2'
   if change=='expiry':t['expires_epoch']=19
   if change=='slice':t['budget']['parent_slice_CPU']=9
   if change=='transfers':t['budget']['transfers']=7
   if change=='memory':r['resources']['memory_MiB']=2048
   with self.subTest(change=change),self.assertRaises(ValueError):h.validate_future_ticket(t,d,p,r,now=20)
 def test_factory_exact_role_before_seal_both_studies_and_queue_never_extended(self):
  original=h.l.issue_authority
  for study in ('FI','DK2'):
   events=[];written={};ledger=types.SimpleNamespace(transition=lambda *args,**kw:events.append(('transition',args)) or dict(state='AUTHORIZED'))
   release=dict(purpose='COST_ONLY',study=study,scope_id='future',task_key='future',plan_sha256='plan',
    scientific_exclusion_key='intent',node='node-13',resources=dict(wall_seconds=1200,cpu_seconds=1200,cpus=1,memory_MiB=4096),
    source_hashes={},proof_manifest={},policy_pin={},backend=None,remote_root='/private/remote')
   claim=dict(state='HELD',job_id='999999',release_sha256='release',release_path='/private/release',remote_root='/private/remote')
   config={};request={};gate={'site':{'calendar_expires_epoch':10000}}
   fn=h.role_complete_authority_factory();ns=dict(fn.__globals__)
   def bound(*args):events.append(('bound',args));return ledger,claim,release,config
   def write(path,value):
    if path.name=='authority.json':
     self.assertEqual(value['role'],study+'_COST_ONLY_BENCHMARK');self.assertEqual(value['max_queue_seconds'],180)
     self.assertEqual(value['calendar_expires_epoch'],10000);events.append(('sealed-role',value['role']))
    written[str(path)]=value;return dict(path=str(path),sha256='packet')
   ns.update(_bound_claim=bound,r=types.SimpleNamespace(read=lambda p:request,identity=lambda v:'id'),
    validate_request=lambda *args:gate,time=types.SimpleNamespace(time=lambda:100),
    a=types.SimpleNamespace(AUTHORITY_SCHEMA='authority',OWNER=h.a.OWNER,ActivationError=ValueError,
      validate_authority=lambda authority,*args:events.append(('validated-role',authority['role']))),
    write_new=write,transfer=lambda *args:events.append(('transfer',None)),remote=lambda *args:'packet',
    _cost_transition=lambda *args,**kw:events.append(('legacy-transition',args)),REFERENCE_NUMERICAL_ENV={})
   fn=types.FunctionType(fn.__code__,ns);fn('future','config',{'path':'/ticket','sha256':'ticket'},{'path':'/factory','sha256':'factory'})
   self.assertEqual(sum(x[0]=='bound' for x in events),1)
   self.assertLess(next(i for i,x in enumerate(events) if x[0]=='validated-role'),next(i for i,x in enumerate(events) if x[0]=='sealed-role'))
  self.assertIs(h.l.issue_authority,original)
 def test_queue_clamp_ast_preserves_stock_expression(self):
  stock=ast.parse(inspect.getsource(h.l.issue_authority));factory=h.role_complete_authority_factory()
  self.assertIn(180,factory.__code__.co_consts)
  self.assertIs(factory.__globals__['validate_request'],h.l.validate_request)
  self.assertIs(factory.__globals__['transfer'],h.l.transfer)
  self.assertEqual(len([n for n in ast.walk(stock) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='queue' for t in n.targets)]),1)
 def test_post_authority_proof_age_queue_and_old_clock(self):
  auth=dict(issued_epoch=100,max_queue_seconds=180,calendar_expires_epoch=2000)
  proof={'observed_epoch':101};request={k:dict(proof) for k in ('handoff_receipt','all_hosts_observation','site_admission')}
  with patch.object(h.a,'read_pin',side_effect=lambda v:v):self.assertEqual(h.require_fresh_after_authority(request,auth,now=120),101)
  for bad in (dict(auth,max_queue_seconds=181),dict(auth,max_queue_seconds=0)):
   with patch.object(h.a,'read_pin',side_effect=lambda v:v),self.assertRaises(ValueError):h.require_fresh_after_authority(request,bad,now=120)
  request['site_admission']['observed_epoch']=99
  with patch.object(h.a,'read_pin',side_effect=lambda v:v),self.assertRaises(ValueError):h.require_fresh_after_authority(request,auth,now=120)
 def test_wrappers_have_no_outer_bound_no_release_and_activate_or_post_READY_observer(self):
  for name in ('release_only','watch_and_activate','authorize_and_observe'):
   tree=ast.parse(inspect.getsource(getattr(h,name)))
   calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call)]
   self.assertFalse(any(isinstance(n.func,ast.Attribute) and n.func.attr in {'_bound_claim','release_and_activate'} for n in calls))
  watch=inspect.getsource(h.watch_and_activate)
  self.assertEqual(watch.count("stock_api_factory('watch_ready'"),1);self.assertEqual(watch.count("stock_api_factory('activate'"),1)
  self.assertNotIn('refresh_authorized_request(',watch);self.assertNotIn('admission_refresh',watch)
  self.assertEqual(inspect.getsource(h.authorize_and_observe).count('refresh_authorized_request('),1)
 def test_stock_bodies_are_unmodified_in_isolated_namespace(self):
  for name in ('release_job','watch_ready','activate'):
   original=getattr(h.l,name);fn=h.stock_api_factory(name)
   self.assertIsNot(fn,original);self.assertIsNot(fn.__globals__,original.__globals__)
   self.assertEqual(fn.stock_source_AST,ast.dump(ast.parse(inspect.getsource(original)),include_attributes=False))
   self.assertEqual(set(fn.__code__.co_names),set(original.__code__.co_names))
   self.assertIs(getattr(h.l,name),original)
 def test_arithmetic_seven_lifetimes_and_unchanged217(self):
  self.assertEqual(len(h.LIFETIMES),7);self.assertEqual(7*8,56);self.assertLessEqual(56,60)
  self.assertEqual(h.ob.priced_maximum(h.ob.INITIAL_LIMITS,60),217)
  self.assertEqual(h.ob.INITIAL_LIMITS,dict(metadata=20,transfer=6,ready_watch=1,admission_refresh=1))
 def test_release_and_watch_activate_call_order_without_extra_observer_or_bound(self):
  t,d,p,release=self.fixture();events=[];proof_pin={'path':'/proof','sha256':'x'};fresh_pin={'path':'/fresh','sha256':'y'}
  record={'ticket':{'path':'/ticket','sha256':'t'},'fresh_request':fresh_pin,'no_second_refresh':True};request={}
  protocol=types.SimpleNamespace(current_claim=lambda ticket:dict(state='AUTHORIZED',job_id='999999'),read_authority=lambda claim:{},routing={'_bound_claim':None,'_cost_transition':None})
  def rd(value):return record if value==proof_pin else request
  def api(name,**kw):return lambda *args:events.append(name) or dict(state='done')
  with tempfile.TemporaryDirectory() as tmp,patch.object(h,'_context',return_value=(t,release)),patch.object(h,'pin',return_value=record['ticket']),patch.object(h.a,'read_pin',side_effect=rd),patch.object(h,'require_fresh_after_authority',side_effect=lambda *x:events.append('fresh')),patch.object(h,'stock_api_factory',side_effect=api),patch.object(h.l,'finish_parent_contexts',side_effect=lambda:events.append('finish')):
   h.release_only('/ticket','config',proof_pin,protocol=protocol)
   self.assertEqual(events,['fresh','release_job','finish']);events.clear()
   protocol.current_claim=lambda ticket:dict(state='SUBMITTED',job_id='999999')
   h.watch_and_activate('/ticket','config',proof_pin,Path(tmp)/'ready',protocol=protocol)
   self.assertEqual(events,['fresh','watch_ready','activate','finish'])
 def test_authority_and_observer_share_parent_and_only_one_refresh(self):
  t,d,p,release=self.fixture();events=[];claim=dict(state='AUTHORIZED',task_key=t['task_key'],job_id='999999');legacy=dict(state='AUTHORIZED')
  config={};fresh_pin={'path':'/fresh','sha256':'f'};budget=types.SimpleNamespace(start_operation=lambda *x:events.append('start-refresh') or 'token',finish_operation=lambda *x,**kw:events.append('finish-refresh'))
  protocol=types.SimpleNamespace(read_authorized_pair=lambda *x:events.append('read-pair') or (claim,legacy,config),routing={'_bound_claim':None,'_cost_transition':None},legacy_snapshot=lambda:{},admission=object(),read_authority=lambda c:events.append('read-authority') or {'issued_epoch':100,'max_queue_seconds':180})
  def factory(**kw):return lambda *x:events.append('factory-one-bound') or claim
  fresh={'status':'READY_FOR_PREPARE_ONLY_NOT_ADMITTED','request':fresh_pin,'observer_budget':{'remote_CPU_seconds':.1}}
  with tempfile.TemporaryDirectory() as tmp,patch.object(h,'_context',return_value=(t,release)),patch.object(h,'pin',return_value={'path':'/ticket','sha256':'t'}),patch.object(h,'role_complete_authority_factory',side_effect=factory),patch.object(h.l,'bind_control',side_effect=lambda *x:events.append('reuse-parent') or budget),patch.object(h,'refresh_authorized_request',side_effect=lambda *x,**kw:events.append('observer') or fresh),patch.object(h.a,'read_pin',return_value={}),patch.object(h.l,'validate_request',side_effect=lambda *x:events.append('validate-request')),patch.object(h,'require_fresh_after_authority',side_effect=lambda *x:events.append('fresh')),patch.object(h.l,'write_new',side_effect=lambda *x:events.append('write-proof')),patch.object(h.l,'finish_parent_contexts',side_effect=lambda:events.append('finish-parent')):
   result=h.authorize_and_observe('/ticket','config','operator','plan',Path(tmp)/'audit',protocol=protocol)
  self.assertEqual(events,['factory-one-bound','read-pair','reuse-parent','start-refresh','observer','finish-refresh','validate-request','read-authority','fresh','write-proof','finish-parent'])
  self.assertTrue(result['no_second_refresh'])

if __name__=='__main__':unittest.main()
