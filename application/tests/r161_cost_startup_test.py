"""Finite COST startup orchestration, using private JSON and fake I/O only."""
import copy
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/pricefm'))
from pricefm_hb import activation as a,admission as ad,cost_control as cost,lifecycle as l,registry as r
from pricefm_hb.environment import REFERENCE_NUMERICAL_ENV


class StartupTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name)
        self.now=2000.;self.key='a'*64;self.events=[]
        self.resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=1200,wall_seconds=1200)
        self.config={'host':'private-host'}
        self.release=dict(purpose='COST_ONLY',study='DK2',scope_id='r161_DK2_replacement_01',task_key=self.key,
            plan_sha256='b'*64,scientific_exclusion_key='fixed-science',resources=self.resources,node='node-13',
            remote_root='/private/release',source_hashes=a.executed_sources('COST_ONLY'),proof_manifest={},
            policy_pin={'path':'/private/policy.json','sha256':'c'*64})
        self.rp=self.write('release/release.json',self.release)
        self.claim=dict(task_key=self.key,task=dict(purpose='COST_ONLY',study='DK2'),state='HELD',job_id='900004',
            release_path=str(self.root/'release'),release_sha256=self.rp['sha256'],remote_root='/private/release',
            legacy_cost_key='d'*64,config_sha256=r.identity(self.config))
        parent=self
        class Ledger:
            def snapshot(inner):return {'claims':{parent.key:copy.deepcopy(parent.claim)}}
            def transition(inner,key,expected,target,**fields):
                parent.assertEqual(key,parent.key);parent.assertEqual(parent.claim['state'],expected)
                parent.events.append(target);parent.claim.update(state=target,**fields)
                return copy.deepcopy(parent.claim)
        self.ledger=Ledger()
        for obj,name,new in ((l.time,'time',lambda:self.now),(l,'finish_parent_contexts',lambda:self.events.append('finish')),
                (l,'Ledger',lambda:self.ledger)):
            self.enter(obj,name,new)

    def enter(self,obj,name,new):
        manager=patch.object(obj,name,new);result=manager.start();self.addCleanup(manager.stop);return result

    def write(self,name,value):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value);return l.pin(path)

    def issue(self,*,replacement=False):
        if replacement:
            self.release['cost_replacement']=self.write('permit.json',{'expires_epoch':self.now+1600})
            self.release['control_cpu_scope']={'scope_id':'new-original-control'}
        self.rp=self.write('release/release.json',self.release);self.claim['release_sha256']=self.rp['sha256']
        self.write('release/launch-request.json',{})
        self.enter(l,'_bound_claim',lambda *args:(self.ledger,copy.deepcopy(self.claim),copy.deepcopy(self.release),self.config))
        self.enter(l,'validate_request',lambda *args:{'site':{'calendar_expires_epoch':self.now+5000}})
        self.enter(l,'_cost_transition',lambda key,old,new,**kw:self.events.append('legacy:'+new))
        self.enter(l,'transfer',lambda *args:self.events.append('transfer'))
        self.enter(l,'remote',lambda *args:l.pin(self.root/'release/authorization/packet.json')['sha256']+' packet.json')
        return l.issue_authority(self.key,'private-config')

    def test_stock_factory_seals_exact_role_queue_and_original_permit_expiry(self):
        result=self.issue(replacement=True)
        authority=r.read(self.root/'release/authorization/authority.json')
        self.assertEqual(result['state'],'AUTHORIZED')
        self.assertEqual(authority['role'],'DK2_COST_ONLY_BENCHMARK')
        self.assertEqual(authority['max_queue_seconds'],180)
        self.assertEqual(authority['calendar_expires_epoch'],self.now+1600)
        self.assertEqual(authority['cost_replacement'],self.release['cost_replacement'])
        self.assertEqual(authority['protocol_version'],l.REPLACEMENT_PROTOCOL)
        self.assertEqual(result['authority_sha256'],l.pin(self.root/'release/authorization/authority.json')['sha256'])
        self.assertLess(self.events.index('AUTHORITY_INTENT'),self.events.index('transfer'))
        self.assertEqual(self.events[-2:],['AUTHORIZED','legacy:AUTHORIZED'])

    def test_factory_validates_original_request_before_mutation(self):
        self.enter(l,'validate_request',lambda *args:(_ for _ in ()).throw(a.ActivationError('stale original')))
        # Install the normal issue edges, then replace its request gate.
        self.write('release/launch-request.json',{})
        self.enter(l,'_bound_claim',lambda *args:(self.ledger,self.claim,self.release,self.config))
        with self.assertRaisesRegex(a.ActivationError,'stale original'):l.issue_authority(self.key,'private-config')
        self.assertEqual(self.claim['state'],'HELD');self.assertEqual(self.events,[])
        self.assertFalse((self.root/'release/authorization').exists())

    def test_release_only_rejects_expired_original_queue_before_scheduler_mutation(self):
        self.issue();self.now+=181
        self.events.clear()
        with self.assertRaisesRegex(a.ActivationError,'original cost authority/job/queue'):
            l.release_job(self.key,'private-config')
        self.assertEqual(self.claim['state'],'AUTHORIZED');self.assertEqual(self.events,[])

    def test_combined_cost_path_rejects_before_any_bound_or_release(self):
        for name in ('_bound_claim','release_job','watch_ready','activate'):
            self.enter(l,name,lambda *args:(_ for _ in ()).throw(AssertionError('unexpected old combined path')))
        with self.assertRaisesRegex(a.ActivationError,'authority-and-observe'):
            l.release_and_activate(self.key,'config','operator','plan',self.root/'unused')
        self.assertFalse((self.root/'unused').exists())

    def test_authority_observer_reuses_one_parent_without_second_bound(self):
        authorized=dict(self.claim,state='AUTHORIZED',authority_sha256='e'*64)
        authority={'calendar_expires_epoch':self.now+3500}
        self.write('release/authorization/authority.json',authority)
        proof=self.write('fresh-request.json',{'fresh':'held'})
        self.enter(l,'issue_authority',lambda *args:self.events.append('issue') or authorized)
        self.enter(cost,'Ledger',lambda:types.SimpleNamespace(snapshot=lambda:{'claims':{self.claim['legacy_cost_key']:{'retained':'paid'}}}))
        self.enter(ad,'authorized_cost_pair',lambda *args:self.events.append('paid-pair'))
        budget=types.SimpleNamespace(start_operation=lambda *args:self.events.append('start-refresh') or 'token',
            finish_operation=lambda *args,**kw:self.events.append(('finish-refresh',kw)))
        self.enter(l,'bind_control',lambda *args:self.events.append('reuse-parent') or budget)
        self.enter(l.ctl,'config',lambda *args:self.config)
        def refresh(*args,**kw):
            self.events.append('observer');self.assertEqual(kw['self_claim'],authorized)
            self.assertEqual(kw['execution_plan_sha256'],self.release['plan_sha256'])
            return {'status':'READY_FOR_PREPARE_ONLY_NOT_ADMITTED','request':proof,'observer_budget':{'remote_CPU_seconds':.25}}
        self.enter(ad,'refresh_request',refresh)
        self.enter(l,'_cost_proof_fresh',lambda *args:self.events.append('proof-fresh'))
        self.enter(l,'_bound_claim',lambda *args:(_ for _ in ()).throw(AssertionError('extra cold outer bind')))
        result=l.authority_and_observe(self.key,'config','operator','plan',self.root/'authority-observer')
        doc=a.read_pin(result);self.assertEqual(doc['request'],proof)
        self.assertEqual(self.events.count('issue'),1);self.assertEqual(self.events.count('observer'),1)
        self.assertEqual(self.events.count('reuse-parent'),1)
        self.assertEqual(self.events[-2:],['proof-fresh','finish'])
        finish=[event for event in self.events if isinstance(event,tuple)][0][1]
        self.assertEqual(finish['remote_CPU'],.25);self.assertGreaterEqual(finish['local_CPU'],0)

    def test_watch_activate_calls_only_two_stock_bounds_and_existing_proof(self):
        self.claim.update(state='SUBMITTED')
        authority=self.write('release/authorization/authority.json',{'original':True})
        self.claim['authority_sha256']=authority['sha256'];proof=self.write('held.json',{'fresh':'already-observed'})
        def existing_proof(*args, **kwargs):
            self.assertEqual(kwargs, {'startup_observation': True})
            self.events.append('existing-proof')
        self.enter(l,'_cost_proof_fresh',existing_proof)
        self.enter(l,'watch_ready',lambda *args:self.events.append('watch-bound'))
        self.enter(l,'activate',lambda *args:self.events.append('activate-bound') or {'state':'ACTIVATED'})
        self.enter(l,'_bound_claim',lambda *args:(_ for _ in ()).throw(AssertionError('extra outer full hash')))
        self.enter(ad,'refresh_request',lambda *args,**kw:(_ for _ in ()).throw(AssertionError('postREADY observer')))
        result=l.watch_and_activate(self.key,'config',proof['path'],self.root/'watch')
        self.assertEqual(result['state'],'ACTIVATED')
        self.assertEqual(self.events,['existing-proof','watch-bound','activate-bound','finish'])

    def fresh_proof(self):
        authority=dict(schema=a.AUTHORITY_SCHEMA,purpose='COST_ONLY',study='DK2',role='DK2_COST_ONLY_BENCHMARK',
            scope_id=self.release['scope_id'],issuer=a.OWNER,controller=a.OWNER,plan_sha256=self.release['plan_sha256'],
            executed_sources=self.release['source_hashes'],reference_numerical_environment=REFERENCE_NUMERICAL_ENV,
            automatic_retry=False,new_model_fits=0,official_origins=0,promotion=False,issued_epoch=self.now-10,
            calendar_expires_epoch=self.now+3500,max_queue_seconds=180,resources=self.resources,slurm_job_id='900004',
            node='node-13',release_sha256=self.rp['sha256'])
        request={name:self.write(name+'.json',{'observed_epoch':self.now-5})
            for name in ('handoff_receipt','all_hosts_observation','site_admission')}
        return authority,request

    def test_original_queue_and_postauthority_allhost_proof_must_remain_fresh(self):
        authority,request=self.fresh_proof();self.enter(l,'validate_request',lambda *args:None)
        self.assertEqual(l._cost_proof_fresh(request,authority,self.release,now=self.now),self.now-5)
        for bad in ('before-authority','queue-expired','stale-host'):
            value=copy.deepcopy(request);clock=self.now
            if bad=='before-authority':value['site_admission']=self.write('before.json',{'observed_epoch':self.now-20})
            if bad=='queue-expired':clock=authority['issued_epoch']+180
            if bad=='stale-host':value['all_hosts_observation']=self.write('stale.json',{'observed_epoch':self.now-301})
            with self.subTest(bad=bad),self.assertRaises(a.ActivationError):l._cost_proof_fresh(value,authority,self.release,now=clock)

    def terminal_driver(self,receipts,*,failed_start=False,deadline=None):
        self.claim.update(state='SUBMITTED' if failed_start else 'ACTIVATED')
        if failed_start:
            self.claim['startup_failure_pin']=self.write('failure.json',{'event':'FAILED','evidence':{
                'task_key':self.key,'job_id':self.claim['job_id'],'release_sha256':self.rp['sha256']}})
        else:self.claim['allocation_start_epoch']=self.now
        self.enter(l.ctl,'config',lambda *args:self.config)
        self.enter(l,'bind_control',lambda *args:self.events.append('one-parent'))
        self.enter(l,'control_scope',lambda *args:(None,{'expires_epoch':deadline or self.now+3600}))
        def wait(target,end):
            self.events.append(('wait',target));
            if target>=end:raise a.ActivationError('original clock')
            self.now=target
        self.enter(l,'_wait_cost_status_epoch',wait)
        def status(key,config,path):
            self.events.append('status-bound')
            result=dict(receipts.pop(0),checked=self.now);self.write(str(Path(path).relative_to(self.root)),result);return result
        self.enter(l,'status',status)
        self.enter(l,'_bound_claim',lambda *args:(_ for _ in ()).throw(AssertionError('outer status hash')))
        self.enter(l,'collect',lambda *args:(_ for _ in ()).throw(AssertionError('automatic collect')))
        return l.terminal_status_cost(self.key,'config',self.root/'status')

    def test_terminal_driver_two_status_bounds_no_third_or_auto_collect(self):
        start=self.now;result=self.terminal_driver([{'terminal':False},{'terminal':False}])
        self.assertEqual(result['status'],'COST_STATUS_LIMIT_REACHED_NOT_TERMINAL')
        self.assertEqual(result['ordinary_status_calls'],2);self.assertFalse(result['automatic_collect'])
        self.assertEqual([event for event in self.events if isinstance(event,tuple)],[('wait',start+305),('wait',start+1265)])
        self.assertEqual(self.events.count('one-parent'),1);self.assertEqual(self.events.count('status-bound'),2)

    def test_terminal_driver_stops_after_first_terminal_receipt(self):
        result=self.terminal_driver([{'terminal':True}]);self.assertTrue(result['terminal'])
        self.assertEqual(result['ordinary_status_calls'],1);self.assertEqual(self.events.count('status-bound'),1)

    def test_terminal_driver_negative_start_requires_exact_failure_and_never_waits_beyond_clock(self):
        start=self.now;result=self.terminal_driver([{'terminal':True}],failed_start=True)
        self.assertTrue(result['terminal']);self.assertIn(('wait',start),self.events)

    def test_terminal_driver_original_expiry_blocks_second_status(self):
        with self.assertRaisesRegex(a.ActivationError,'original clock'):
            self.terminal_driver([{'terminal':False}],deadline=self.now+1000)
        self.assertEqual(self.events.count('status-bound'),1);self.assertEqual(self.events[-1],'finish')

    def test_submitted_without_bound_failure_evidence_cannot_start_status_driver(self):
        self.claim.update(state='SUBMITTED')
        self.enter(l.ctl,'config',lambda *args:self.config)
        self.enter(l,'bind_control',lambda *args:(_ for _ in ()).throw(AssertionError('unproved worker start')))
        with self.assertRaises(a.ActivationError):l.terminal_status_cost(self.key,'config',self.root/'unproved')
        self.assertFalse((self.root/'unproved').exists())

    def test_explicit_permit_bundle_does_not_walk_controller_history(self):
        pointer=self.write('permit.json',{'prior_release':{'path':'/opaque/absent/prior-array.npy','sha256':'f'*64},'old_clock':1})
        manifest=l.pack_proofs(self.root/'staged',[pointer])
        self.assertEqual(set(manifest),{pointer['path']})
        self.assertEqual(a.read_pin(pointer,{'proof_manifest':manifest},root=self.root/'staged')['old_clock'],1)

    def test_pending_held_capacity_never_adds_back_unallocated_resources(self):
        release=dict(self.release);claim=dict(self.claim,state='AUTHORIZED',resources=self.resources)
        self.enter(ad,'_release',lambda own:release)
        def snapshot(cpu_alloc=1,memory_alloc=4096,free=4096,state='PENDING'):
            job='JobId=900004 JobState='+state+' Reason=JobHeldUser ReqNodeList=node-13 NumCPUs=1 ReqTRES=cpu=1,mem=4G MinMemoryNode=4G'
            return {'slurm':{'partition':'State=UP MaxTime=1-00:00:00','self_job':job,
                'nodes':'NodeName=node-13 Partitions=128x24 State=MIXED CPUTot=2 CPUAlloc='+str(cpu_alloc)+
                ' RealMemory=8192 AllocMem='+str(memory_alloc)+' FreeMem='+str(free)}}
        selected=ad.select_node(snapshot(),4096,1200,claim)
        self.assertFalse(selected['self_allocation_added_back']);self.assertEqual(selected['available_cpus'],1)
        with self.assertRaises(ad.AdmissionError):ad.select_node(snapshot(cpu_alloc=2),4096,1200,claim)
        with self.assertRaises(ad.AdmissionError):ad.select_node(snapshot(memory_alloc=8192,free=0),4096,1200,claim)
        with self.assertRaises(ad.AdmissionError):ad.select_node(snapshot(state='RUNNING'),4096,1200,claim)

    def test_running_prefix_allocation_keeps_original_addback(self):
        release=dict(self.release,purpose='PREFIX_ASSESSMENT');claim=dict(self.claim,state='ACTIVATED',resources=self.resources)
        self.enter(ad,'_release',lambda own:release)
        snapshot={'slurm':{'partition':'State=UP MaxTime=1-00:00:00',
            'self_job':'JobId=900004 JobState=RUNNING NodeList=node-13 NumCPUs=1 AllocTRES=cpu=1,mem=4G',
            'nodes':'NodeName=node-13 Partitions=128x24 State=ALLOCATED CPUTot=2 CPUAlloc=2 RealMemory=8192 AllocMem=8192 FreeMem=4096'}}
        selected=ad.select_node(snapshot,4096,1200,claim)
        self.assertTrue(selected['self_allocation_added_back']);self.assertEqual(selected['available_cpus'],1)


if __name__=='__main__':unittest.main()
