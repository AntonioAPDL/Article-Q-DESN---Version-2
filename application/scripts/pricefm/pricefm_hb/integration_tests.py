"""Final metadata-only integration boundaries; no network or model calls."""
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock
from . import activation as a, admission, lifecycle as l, metered_io
from . import operation_budget as ob, policy, prefix, prefix_control as pc, registry as r


class FinalIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.central=self.root/'canonical';self.central.mkdir()
        self.now=time.time();self.scope='control-integration';self.key='integration-task'
        self.config=dict(user='jaguir26',host='hb.ucsc.edu',remote_root='/mnt/beegfs/home/jaguir26/integration')
        for target,name,value in ((l,'CENTRAL',self.central),(ob,'owner',lambda:None),(l,'owner',lambda:None)):
            patch=mock.patch.object(target,name,value);patch.start();self.addCleanup(patch.stop)
        patch=mock.patch.dict(l.PARENT_SLICES,{},clear=True);patch.start();self.addCleanup(patch.stop)
        self.auth=dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=a.OWNER,
            scope_id=self.scope,kind='INITIAL',CPU_ceiling=720,nonrenewing=True,expires_epoch=self.now+3600)
        self.auth_pin=self.write('authorization.json',self.auth)
        self.budget=ob.OperationBudget.create(self.central/(self.scope+'.control_cpu.json'),
            scope_id=self.scope,authorization_pin=self.auth_pin,expires_epoch=self.auth['expires_epoch'])
        self.spec=dict(path=str(self.budget.path),authorization_pin=self.auth_pin,scope_id=self.scope)
        self.release_dir=self.root/'release';self.release_dir.mkdir()
        self.plan_pin=self.write('release/plan.json',{'metadata_fixture':True})
        self.release=dict(task_key=self.key,purpose='CACHED_NORMAL_COMPONENT',study='FI',
            scientific_exclusion_key='FI|fixed-original-component',plan_sha256=self.plan_pin['sha256'],
            policy_pin=dict(path='/pinned/policy.json',sha256='f'*64),control_cpu_scope=self.spec)
        self.claim=dict(task_key=self.key,state='SUBMITTED',release_path=str(self.release_dir),job_id='868999',
            task=dict(purpose=self.release['purpose'],study='FI',plan_sha256=self.release['plan_sha256'],
                scientific_exclusion_key=self.release['scientific_exclusion_key']))

    def write(self,name,value):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value);return policy.pin(path)

    def test_control_scope_requires_exact_canonical_authorization_and_path_before_IO(self):
        budget,state=l.control_scope(self.release)
        self.assertEqual(state['scope_id'],self.scope);self.assertEqual(budget.path,self.budget.path)
        for spec in (dict(self.spec,path=str(self.root/'elsewhere.control_cpu.json')),
                     dict(self.spec,scope_id='different'),dict(self.spec,authorization_pin=dict(self.auth_pin,sha256='e'*64))):
            with self.subTest(spec=spec),self.assertRaises(a.ActivationError):
                l.control_scope(dict(self.release,control_cpu_scope=spec))

    def test_bind_control_reserves_claim_and_parent_slice_before_transport(self):
        config=copy.deepcopy(self.config);events=[]
        actual=self.budget.reserve_parent_slice
        def reserve(*args,**kw):events.append('reserved-parent');return actual(*args,**kw)
        with mock.patch.object(ob.OperationBudget,'reserve_parent_slice',autospec=True,
                side_effect=lambda store,*args,**kw:reserve(*args,**kw)),\
                mock.patch.object(l.resource,'setrlimit',side_effect=lambda *args:events.append('kernel-limit')),\
                mock.patch.object(l.atexit,'register'),mock.patch.object(metered_io,'remote',return_value='') as remote:
            l.bind_control(config,self.release,reserve=True)
            self.assertEqual(events,['reserved-parent','kernel-limit'])
            state=self.budget.snapshot();self.assertEqual(state['claims'][self.key]['parent_reserved_CPU'],8)
            l.remote(config,['squeue'])
            remote.assert_called_once_with(config,['squeue'],mock.ANY,self.key,timeout=30)
            l.bind_control(config,self.release)
            self.assertEqual(self.budget.snapshot()['claims'][self.key]['parent_reserved_CPU'],8)
        l.PARENT_SLICES.clear()

    def test_missing_precharged_claim_cannot_bind_parent_or_transport(self):
        with mock.patch.object(l.resource,'setrlimit') as limit,mock.patch.object(metered_io,'remote') as remote:
            with self.assertRaises(a.ActivationError):l.bind_control(copy.deepcopy(self.config),self.release)
        limit.assert_not_called();remote.assert_not_called()

    def test_bound_claim_hashes_pure_config_before_adding_runtime_objects(self):
        release_pin=self.write('release/release.json',self.release)
        claim=dict(self.claim,config_sha256=r.identity(self.config),release_sha256=release_pin['sha256'])
        ledger=mock.Mock();ledger.snapshot.return_value={'claims':{self.key:claim}}
        config=copy.deepcopy(self.config)
        def bind(value,release):value['_r157_control_budget']=object();value['_r157_task_key']=self.key
        with mock.patch.object(l,'Ledger',return_value=ledger),mock.patch.object(l.ctl,'config',return_value=config),\
                mock.patch.object(l,'bind_control',side_effect=bind),mock.patch.object(l,'verify_release',return_value=self.release):
            result=l._bound_claim(self.key,'config.json')
        self.assertIs(result[3],config)
        self.assertEqual({k:v for k,v in config.items() if not k.startswith('_r157')},self.config)
        self.assertEqual(r.identity(self.config),claim['config_sha256'])

    def combined(self,result=None,error=None):
        self.budget.reserve_claim(self.key)
        config=dict(self.config,_r157_control_budget=self.budget)
        ledger=mock.Mock();ledger.snapshot.return_value={'claims':{self.key:self.claim}}
        stack=__import__('contextlib').ExitStack();self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(l,'_bound_claim',return_value=(ledger,self.claim,self.release,config)))
        self.release_job=stack.enter_context(mock.patch.object(l,'release_job'))
        self.watch=stack.enter_context(mock.patch.object(l,'watch_ready'))
        self.refresh=stack.enter_context(mock.patch.object(admission,'refresh_request',return_value=result,side_effect=error))
        self.activate=stack.enter_context(mock.patch.object(l,'activate',return_value={'state':'ACTIVATED'}))
        return l.release_and_activate(self.key,'site.json','operator.json','/original/FI-plan.json',self.root/'fresh-activation')

    def test_combined_release_propagates_exact_canonical_self_plan_purpose_and_key(self):
        result=dict(status='READY_FOR_PREPARE_ONLY_NOT_ADMITTED',request={'path':'/fresh/request.json'},
            observer_budget={'remote_CPU_seconds':.1})
        self.assertEqual(self.combined(result),{'state':'ACTIVATED'})
        call=self.refresh.call_args
        self.assertIs(call.kwargs['self_claim'],self.claim)
        self.assertEqual(call.args[:3],('/original/FI-plan.json','operator.json',self.release['policy_pin']))
        self.assertEqual(call.kwargs['purpose'],self.release['purpose'])
        self.assertEqual(call.kwargs['execution_plan_pin'],self.plan_pin)
        self.assertEqual(call.kwargs['execution_plan_sha256'],self.release['plan_sha256'])
        self.assertEqual(call.kwargs['scientific_exclusion_key'],self.release['scientific_exclusion_key'])
        self.activate.assert_called_once_with(self.key,'site.json','/fresh/request.json')
        self.assertEqual(self.budget.snapshot()['claims'][self.key]['counts']['admission_refresh'],1)

    def test_blocked_fresh_observer_never_activates_and_retains_charge(self):
        with self.assertRaises(a.ActivationError):
            self.combined(dict(status='BLOCKED',observer_budget={'remote_CPU_seconds':.1}))
        self.activate.assert_not_called()
        claim=self.budget.snapshot()['claims'][self.key]
        self.assertEqual(claim['counts']['admission_refresh'],1)
        self.assertEqual(next(iter(claim['operations'].values()))['outcome'],'REFRESH_FAILED')

    def test_missing_observer_CPU_blocks_activation_without_assuming_zero(self):
        with self.assertRaises(ob.BudgetError):
            self.combined(dict(status='READY_FOR_PREPARE_ONLY_NOT_ADMITTED',request={'path':'/fresh/request.json'}))
        self.activate.assert_not_called();self.assertTrue(self.budget.snapshot()['claims'][self.key]['violations'])

    def test_raised_observer_failure_persists_unknown_CPU_and_never_activates(self):
        with self.assertRaises(ob.BudgetError):self.combined(error=RuntimeError('observer unavailable'))
        self.activate.assert_not_called();self.assertTrue(self.budget.snapshot()['claims'][self.key]['violations'])

    def cache_control(self,**changes):
        value=dict(status='ROOT_ADMITTED_EXACT_PREFIX_CACHE_CONTROL',controller=a.OWNER,plan=self.plan_pin,
            config_sha256=r.identity(self.config),executed_sources=prefix.executed_sources(),model_calls=0,
            automatic_retry=False,task_key='cache-task',control_cpu_scope=self.spec,operation_price_pin=self.auth_pin)
        value.update(changes);return self.write('cache-control.json',value)

    def test_cache_missing_changed_source_or_INITIAL_scope_rejects_before_any_IO(self):
        with mock.patch.object(pc,'owner'),mock.patch.object(prefix,'validate_plan'),\
                mock.patch.object(pc.ctl,'config',side_effect=lambda path:copy.deepcopy(self.config)),\
                mock.patch.object(l,'bind_control') as bind,mock.patch.object(l,'remote') as remote,\
                mock.patch.object(l,'transfer') as transfer,mock.patch.object(metered_io,'watch') as watch,\
                mock.patch.object(pc,'stage_original_inputs') as stage:
            with self.assertRaises(prefix.PrefixError):pc.stage_cache(self.plan_pin['path'],'site',self.root/'missing')
            changed=dict(prefix.executed_sources());changed['science.py']='e'*64
            bad=self.cache_control(executed_sources=changed)
            with self.assertRaises(prefix.PrefixError):pc.stage_cache(self.plan_pin['path'],'site',self.root/'changed',control_path=bad['path'])
            exact=self.cache_control()
            with self.assertRaises(prefix.PrefixError):pc.stage_cache(self.plan_pin['path'],'site',self.root/'initial',control_path=exact['path'])
        for call in (bind,remote,transfer,watch,stage):call.assert_not_called()

    def test_cache_valid_control_binds_meter_before_stage_and_transport(self):
        control=self.cache_control();events=[]
        def stage(plan,destination):events.append('stage');r.write(destination/'fixed.json',{'fixture':True})
        with mock.patch.object(pc,'owner'),mock.patch.object(prefix,'validate_plan'),\
                mock.patch.object(pc.ctl,'config',return_value=copy.deepcopy(self.config)),\
                mock.patch.object(l,'control_scope',return_value=(mock.Mock(),{'kind':'PREFIX'})),\
                mock.patch.object(l,'bind_control',side_effect=lambda *args,**kw:(events.append('bind') or self.budget)),\
                mock.patch.object(pc,'stage_original_inputs',side_effect=stage),\
                mock.patch.object(l,'remote',side_effect=lambda *args,**kw:(events.append('remote') or '')),\
                mock.patch.object(l,'transfer',side_effect=lambda *args,**kw:events.append('transfer')),\
                mock.patch.object(metered_io,'watch',return_value='{"status":"VERIFIED","files":1,"CPU_seconds":0.1}'):
            receipt=pc.stage_cache(self.plan_pin['path'],'site',self.root/'valid-cache',control_path=control['path'])
        self.assertEqual(events[0:2],['bind','stage']);self.assertEqual(receipt['status'],'VERIFIED_SHARED_PREFIX_CACHE')
        self.assertEqual(receipt['model_calls'],0);self.assertFalse(receipt['automatic_retry'])

    def test_explicit_proof_roles_preserve_historical_missing_provenance_opaque(self):
        pin=self.write('historical.json',{'old':{'path':'/obsolete/not-accessed.npz','sha256':'b'*64}})
        manifest=l.pack_proofs(self.root/'proofs',{'observed_historical_closure':pin})
        self.assertEqual(list(manifest),[pin['path']])
        self.assertEqual(a.read_pin(pin,{'proof_manifest':manifest},self.root/'proofs')['old']['path'],'/obsolete/not-accessed.npz')

    def test_prefix_source_closure_equals_actual19_module_worker_closure(self):
        actual=a.executed_sources('CACHED_NORMAL_COMPONENT')
        self.assertEqual(len(actual),19);self.assertEqual(prefix.executed_sources(),actual)


if __name__=='__main__':unittest.main()
