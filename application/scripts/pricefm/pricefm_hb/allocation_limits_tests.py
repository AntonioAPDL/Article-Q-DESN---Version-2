"""Metadata regressions for propagation repair and one explicit requalification."""
import copy
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import time
import unittest
from unittest import mock
from . import activation as a, lifecycle as l, operation_budget as b, policy, registry as r

PY='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'


class AllocationLimitsTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.now=time.time();self.central=self.root/'canonical';self.central.mkdir()
        for obj,key,value in ((l,'owner',lambda:None),(b,'owner',lambda:None),(l,'CENTRAL',self.central),
                (l,'policy_document',lambda pin:{'expires_epoch':self.now+3500}),(l,'hb_concurrency',lambda packet:1)):
            patch=mock.patch.object(obj,key,value);patch.start();self.addCleanup(patch.stop)
        self.resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=120,wall_seconds=120)
        self.config={'fixture':'site'}
        initial=dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=a.OWNER,scope_id='original-control',
            kind='INITIAL',CPU_ceiling=720,nonrenewing=True,expires_epoch=self.now+3600)
        self.initial_pin=self.write('initial-authority.json',initial)
        self.budget=b.OperationBudget.create(self.central/'original-control.control_cpu.json',scope_id='original-control',
            authorization_pin=self.initial_pin,expires_epoch=initial['expires_epoch'])
        self.old_key='old-failed-key';self.new_key='new-replacement-key'
        self.old_scope=dict(path=str(self.budget.path),authorization_pin=self.initial_pin,scope_id='original-control')
        old=dict(purpose='CONTROL_TEST',task_key=self.old_key,resources=self.resources,source_hashes={'old':'a'*64},control_cpu_scope=self.old_scope)
        self.old_release_pin=self.write('old-release/release.json',old)
        self.old_pub=self.root/'old-publication';self.old_pub.mkdir()
        (self.old_pub/'release.json').write_bytes(Path(self.old_release_pin['path']).read_bytes())
        failure={'type':'MemoryError','message':'inherited512MiBAS fixture'}
        fail_pin=self.write('old-publication/outputs/worker-failure.json',failure)
        worker=dict(schema=l.SCHEMA,task_key=self.old_key,job_id='868958',release_sha256=self.old_release_pin['sha256'],
            application_passed=False,error=failure,files={'worker-failure.json':fail_pin['sha256']})
        worker_pin=self.write('old-publication/outputs/worker_evidence.json',worker)
        rows=[]
        for suffix in ('','.batch','.0'):
            rows.append('868958'+suffix+'|FAILED|1:0|37|1|00:00:06|375240K|node-13|2026-10-28T07:41:34|2026-10-28T07:42:11')
        accounting=dict(task_key=self.old_key,job_id='868958',release_sha256=self.old_release_pin['sha256'],
            terminal=True,complete=False,squeue='',sacct_with_times='\n'.join(rows)+'\n')
        account_pin=self.write('old-publication/accounting.json',accounting)
        collection=self.write('old-publication/collection.json',dict(schema=l.SCHEMA,task_key=self.old_key,
            application_accepted=False,no_refund=True,reserved_CPU_seconds=120))
        self.reference=dict(prior_failed_claim_key=self.old_key,prior_failed_job_id='868958',prior_publication=collection,
            prior_evidence=dict(accounting=account_pin,worker_evidence=worker_pin,worker_failure=fail_pin))
        self.old_claim=dict(task_key=self.old_key,task=dict(purpose='CONTROL_TEST',study='TEST'),state='FAILED_RECONCILED',
            application_accepted=False,job_id='868958',scope_id='r157_control_placement_01',publication=str(self.old_pub),
            release_path=str(self.root/'old-release'),release_sha256=self.old_release_pin['sha256'],created=self.now-10)
        self.state=dict(schema=l.SCHEMA,owner=a.OWNER,claims={self.old_key:self.old_claim},spent_tests=[self.old_key])
        r.write(self.central/'activation_registry.json',self.state)
        self.ledger=l.Ledger()
        self.q=dict(self.reference,schema=l.REQUALIFICATION_SCHEMA,status='ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST',
            controller=a.OWNER,scope_id='r157_control_placement_02',new_executed_sources=a.executed_sources('CONTROL_TEST'),
            max_new_attempts=1,old_charges_refunded=False,all_prior_failed_terminal=True,
            created_epoch=self.now-1,expires_epoch=self.now+3400)
        self.new_release=dict(purpose='CONTROL_TEST',study='TEST',task_key=self.new_key,scope_id=self.q['scope_id'],
            scientific_exclusion_key='TEST|same-fixed-fixture',plan_sha256='b'*64,resources=self.resources,
            source_hashes=self.q['new_executed_sources'],policy_pin={'path':'/policy.json','sha256':'c'*64},
            remote_root='/mnt/beegfs/home/jaguir26/test/new-release',backend=None)

    def write(self,name,value):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value);return policy.pin(path)

    def replacement(self,value=None):
        release=dict(self.new_release,control_test_requalification=self.write('requalification.json',self.q if value is None else value))
        self.write('new-release/release.json',release)
        return release

    def test_compute_rejects_metadata512MiB_and_wrong_CPU_before_numerical_work(self):
        for cpu,as_limit in (((120,120),(512*1024**2,resource.RLIM_INFINITY)),((8,8),(4096*1024**2,resource.RLIM_INFINITY))):
            with self.subTest(cpu=cpu),self.assertRaises(a.ActivationError):
                l.validate_compute_limits(self.resources,getter=lambda kind:cpu if kind==resource.RLIMIT_CPU else as_limit)
        actual=l.validate_compute_limits(self.resources,getter=lambda kind:(120,120) if kind==resource.RLIMIT_CPU else (4096*1024**2,resource.RLIM_INFINITY))
        self.assertEqual(actual['status'],'VERIFIED_BEFORE_NUMERICAL_IMPORTS');self.assertEqual(actual['AS_soft_bytes'],4294967296)

    def test_actual_private_child_reproduces_512MiB_propagation_rejection_without_arrays(self):
        script="import resource;from pricefm_hb import lifecycle as l,activation as a;resource.setrlimit(resource.RLIMIT_CPU,(120,120));resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,)*2)\ntry:l.validate_compute_limits(dict(cpu_seconds=120,memory_MiB=4096))\nexcept a.ActivationError:print('REJECTED_METADATA_LIMIT')\nelse:raise SystemExit(42)"
        result=subprocess.run([PY,'-B','-c',script],text=True,capture_output=True,timeout=10,
            env=dict(os.environ,PYTHONPATH=str(Path(__file__).resolve().parents[1])))
        self.assertEqual(result.returncode,0,result.stderr);self.assertIn('REJECTED_METADATA_LIMIT',result.stdout)

    def test_job_script_declares_exact_CPU_AS_without_increasing_scheduler_resources(self):
        script=l.job_script(self.resources)
        self.assertIn('ulimit -t 120\n',script);self.assertIn('ulimit -S -v 4194304\n',script)
        self.assertIn('--cpu-bind=cores',script)
        for mib in (2048,8192):self.assertIn('ulimit -S -v '+str(mib*1024)+'\n',l.job_script(dict(self.resources,memory_MiB=mib)))

    def test_submission_explicitly_disables_submitter_limit_propagation(self):
        release=dict(self.new_release,release_id='r157-'+'a'*32,node='node-13')
        claim=dict(task_key=self.new_key,release_sha256='d'*64)
        ledger=mock.Mock();ledger.reserve.return_value=claim;ledger.transition.side_effect=lambda *args,**kw:dict(claim,**kw)
        remote_calls=[]
        def remote(config,argv):
            remote_calls.append(argv)
            if argv[0]=='sha256sum':return 'd'*64+' release.json'
            return '868959' if argv[0]=='sbatch' else ''
        self.write('new-release/launch-request.json',{})
        with mock.patch.object(l,'verify_release',return_value=release),mock.patch.object(l,'validate_request'),\
                mock.patch.object(l,'Ledger',return_value=ledger),mock.patch.object(l.ctl,'config',return_value={'user':'jaguir26','remote_root':'/remote'}),\
                mock.patch.object(l,'bind_control'),mock.patch.object(l,'_cost_transition'),\
                mock.patch.object(l,'remote',side_effect=remote),mock.patch.object(l,'transfer'):
            l.submit_component(self.root/'new-release','config')
        argv=next(v for v in remote_calls if v[0]=='sbatch')
        self.assertIn('--propagate=NONE',argv);self.assertIn('--mem=4096M',argv);self.assertIn('--time=00:02:00',argv)

    def test_replacement_requires_explicit_packet_and_preserves_both_spent_entries(self):
        release=dict(self.new_release);self.write('new-release/release.json',release)
        with self.assertRaises(a.ActivationError):self.ledger.reserve(release,self.root/'new-release',self.config)
        release=self.replacement();claim=self.ledger.reserve(release,self.root/'new-release',self.config)
        self.assertEqual(claim['scope_id'],'r157_control_placement_02')
        self.assertEqual(self.ledger.snapshot()['spent_tests'],[self.old_key,self.new_key])
        self.assertEqual(self.ledger.snapshot()['claims'][self.old_key],self.old_claim)
        with self.assertRaises(a.ActivationError):self.ledger.reserve(dict(release,task_key='third-attempt'),self.root/'new-release',self.config)

    def test_prepare_uses_root_requalification_scope02_and_seals_its_pin(self):
        qp=self.write('requalification.json',self.q)
        fixture=self.write('fixed-fixture/manifest.json',{'fixed_fixture':True})
        plan=self.write('original-resource-plan.json',{'study':'FI','claim':{'planned_attempt_id':'cost01'}})
        request=dict(purpose='CONTROL_TEST',accepted_parity_fixture_manifest_sha256=fixture['sha256'],
            runtime_python='/qualified/python',environment_bundle='/qualified/env',control_test_requalification=qp,
            control_cpu_scope=self.old_scope,execution_plan_sha256=plan['sha256'],
            policy_pin=self.write('current-policy.json',{'expires_epoch':self.now+3500}))
        rp=self.write('replacement-request.json',request)
        gate={'site':{'node':'node-13','memory_mib':4096},'policy':{'expires_epoch':self.now+3500}}
        with mock.patch.object(l,'validate_request',return_value=gate),\
                mock.patch('pricefm_hb.cost_control.load_plan',return_value={'study':'FI'}),\
                mock.patch('pricefm_hb.fixture.load_fixture',return_value={}),\
                mock.patch.object(l.ctl,'config',return_value={'remote_root':'/mnt/beegfs/home/jaguir26/requalification'}):
            sealed=l.prepare(plan['path'],rp['path'],'site',self.root/'prepared02',purpose='CONTROL_TEST',fixture=fixture['path'])
        self.assertEqual(sealed['scope_id'],'r157_control_placement_02')
        self.assertEqual(sealed['control_test_requalification'],qp)
        self.assertNotEqual(sealed['task_key'],self.old_key)
        self.assertIn('ulimit -S -v 4194304',(self.root/'prepared02/job.sh').read_text())

    def test_wrong_source_clock_publication_and_nonterminal_prior_all_block(self):
        for change in ({'new_executed_sources':{'wrong':'f'*64}}, {'expires_epoch':self.now+3601},
                       {'scope_id':'r157_control_placement_01'}, {'max_new_attempts':2}, {'old_charges_refunded':True},
                       {'prior_publication':dict(self.reference['prior_publication'],sha256='f'*64)}):
            release=self.replacement(dict(self.q,**change))
            with self.subTest(change=change),self.assertRaises((ValueError,OSError)):
                self.ledger.reserve(release,self.root/'new-release',self.config)
        state=copy.deepcopy(self.state);state['claims'][self.old_key]['state']='AMBIGUOUS';r.write(self.ledger.path,state)
        release=self.replacement()
        with self.assertRaises(a.ActivationError):self.ledger.reserve(release,self.root/'new-release',self.config)

    def test_cost_gate_accepts_one_new_same_source_TEST_and_validates_failed_lineage(self):
        release=self.replacement();self.ledger.reserve(release,self.root/'new-release',self.config)
        state=self.ledger.snapshot();state['claims'][self.new_key].update(state='COLLECTED',application_accepted=True)
        r.write(self.ledger.path,state)
        cost=dict(release,purpose='COST_ONLY',study='FI',task_key='FI-cost',scope_id='FI-cost-01')
        with mock.patch.object(l,'verify_release',return_value=release):
            self.ledger.reserve(cost,self.root/'new-release',self.config)
        state=self.ledger.snapshot();del state['claims']['FI-cost'];state['claims'][self.old_key]['application_accepted']=True;r.write(self.ledger.path,state)
        with mock.patch.object(l,'verify_release',return_value=release),self.assertRaises(a.ActivationError):
            self.ledger.reserve(cost,self.root/'new-release',self.config)

    def test_supplement_exact230_one_DK2_claim_without_reset_or_refund(self):
        auth=dict(self.reference,status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=a.OWNER,scope_id='supplement-230',
            kind='INITIAL_SUPPLEMENT',CPU_ceiling=230,nonrenewing=True,expires_epoch=self.now+3600,
            old_initial_authorization_pin=self.initial_pin,permitted_claim_key='DK2-cost',permitted_claim_purpose='COST_ONLY',
            permitted_claim_study='DK2',max_new_claims=1,old_charges_refunded=False)
        ap=self.write('supplement.json',auth);old_bytes=self.budget.path.read_bytes()
        store=b.OperationBudget.create(self.central/'supplement-230.control_cpu.json',scope_id='supplement-230',
            authorization_pin=ap,expires_epoch=auth['expires_epoch'],kind='INITIAL_SUPPLEMENT')
        with self.assertRaises(b.BudgetError):store.reserve_claim('FI-cost')
        claim=store.reserve_claim('DK2-cost');self.assertEqual(claim['reserved_CPU'],230)
        self.assertEqual(claim['priced_command_and_parent_maximum_CPU'],217)
        self.assertEqual(self.budget.path.read_bytes(),old_bytes)
        with self.assertRaises(b.BudgetError):store.reserve_claim('another-cost')
        with self.assertRaises(b.BudgetError):store.reserve_publication()
        auth['expires_epoch']+=1;bad=self.write('supplement-extension.json',auth)
        with self.assertRaises(b.BudgetError):
            b.OperationBudget.create(self.central/'other.control_cpu.json',scope_id='supplement-230',authorization_pin=bad,
                expires_epoch=auth['expires_epoch'],kind='INITIAL_SUPPLEMENT')

    def recovered(self):
        """A separate new authority starts only after the old INITIAL expires."""
        when=self.now+3601;expires=self.now+4100
        self.budget.reserve_claim(self.old_key)
        snapshot=self.root/'immutable-old-snapshot.json';snapshot.write_bytes(self.budget.path.read_bytes())
        restrictions={self.new_key:dict(purpose='CONTROL_TEST',study='TEST',scope_id=self.q['scope_id']),
            'FI-cost':dict(purpose='COST_ONLY',study='FI',scope_id='FI-cost-01'),
            'DK2-cost':dict(purpose='COST_ONLY',study='DK2',scope_id='DK2-cost-01')}
        auth=dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=a.OWNER,scope_id='new-recovery-control',
            kind='INITIAL',CPU_ceiling=720,nonrenewing=True,expires_epoch=expires,
            recovery_claims=restrictions,max_new_claims=3)
        ap=self.write('new-control-authority.json',auth)
        store=b.OperationBudget.create(self.central/'new-recovery-control.control_cpu.json',
            scope_id=auth['scope_id'],authorization_pin=ap,expires_epoch=expires,now=when)
        spec=dict(path=str(store.path),authorization_pin=ap,scope_id=auth['scope_id'])
        recovery=dict(schema=l.CONTROL_RECOVERY_SCHEMA,
            status='ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_EXPIRED_HISTORY',controller=a.OWNER,
            created_epoch=when,expires_epoch=expires,old_control_cpu_scope=self.old_scope,
            old_snapshot=policy.pin(snapshot),new_control_cpu_scope=spec,max_new_claims=3,
            kind='INITIAL',CPU_ceiling=720,old_charges_refunded=False,old_clocks_mutated=False,automatic_retry=False)
        self.q.update(created_epoch=when,expires_epoch=expires,control_recovery=self.write('control-recovery.json',recovery))
        self.new_release['control_cpu_scope']=spec
        return when,store,recovery

    def test_expired_INITIAL_requires_distinct_prospective_recovery_and_preserves_history(self):
        when,store,recovery=self.recovered();release=self.replacement();old_bytes=self.budget.path.read_bytes()
        packet={'expires_epoch':self.now+4500}
        with self.assertRaises(b.BudgetError):self.budget.snapshot(when)
        no_recovery=dict(self.q);del no_recovery['control_recovery']
        with self.assertRaises(b.BudgetError):
            l.validate_control_test_requalification(no_recovery,release,self.state,now=when,packet=packet)
        l.validate_control_test_requalification(self.q,release,self.state,now=when,packet=packet)
        self.assertEqual(self.budget.path.read_bytes(),old_bytes)
        self.assertEqual(r.read(self.budget.path)['claim_reserved_CPU'],230)
        with self.assertRaises(b.BudgetError):self.budget.reserve_claim('forbidden-old-reuse',now=when)
        for key,role in store.snapshot(when)['recovery_claims'].items():
            with self.assertRaises(b.BudgetError):store.reserve_claim(key,now=when,**dict(role,study='wrong'))
            store.reserve_claim(key,now=when,**role)
        self.assertEqual(store.snapshot(when)['claim_reserved_CPU'],690)
        self.assertEqual(store.reserve_publication(now=when)['reserved_CPU'],30)
        with self.assertRaises(b.BudgetError):store.reserve_claim('fourth',now=when)
        with self.assertRaises(b.BudgetError):store.snapshot(self.now+4101)

    def test_recovery_rejects_changed_old_snapshot_role_clock_and_policy(self):
        when,store,recovery=self.recovered();release=self.replacement();packet={'expires_epoch':self.now+4500}
        for change in ({'old_charges_refunded':True},{'old_clocks_mutated':True},{'automatic_retry':True},
                {'max_new_claims':4},{'created_epoch':self.now},{'expires_epoch':self.now+4600},
                {'old_snapshot':dict(recovery['old_snapshot'],sha256='f'*64)},
                {'new_control_cpu_scope':self.old_scope}):
            with self.subTest(change=change),self.assertRaises((ValueError,OSError)):
                l.validate_control_recovery(dict(recovery,**change),r.read(self.old_release_pin['path']),release,
                    now=when,packet=packet)
        changed=r.read(self.budget.path);changed['claim_reserved_CPU']=0;r.write(self.budget.path,changed)
        with self.assertRaises(b.BudgetError):
            l.validate_control_test_requalification(self.q,release,self.state,now=when,packet=packet)

    def test_cost_checks_recovery_at_accepted_TEST_created_epoch_after_scope_expiry(self):
        when,store,recovery=self.recovered();release=self.replacement()
        with mock.patch.object(l.time,'time',return_value=when),\
                mock.patch.object(l,'policy_document',return_value={'expires_epoch':self.now+4500}):
            self.ledger.reserve(release,self.root/'new-release',self.config)
        state=self.ledger.snapshot();state['claims'][self.new_key].update(state='COLLECTED',application_accepted=True)
        r.write(self.ledger.path,state)
        cost=dict(release,purpose='COST_ONLY',study='FI',task_key='FI-cost',scope_id='FI-cost-01')
        with mock.patch.object(l.time,'time',return_value=self.now+4200),\
                mock.patch.object(l,'policy_document',return_value={'expires_epoch':self.now+4500}),\
                mock.patch.object(l,'verify_release',return_value=release):
            for changed in (dict(cost,task_key='unadmitted-FI'),dict(cost,study='DK2'),
                    dict(cost,control_cpu_scope=self.old_scope)):
                with self.assertRaises(a.ActivationError):
                    self.ledger.reserve(changed,self.root/'new-release',self.config)
            self.ledger.reserve(cost,self.root/'new-release',self.config)
        self.assertEqual(self.ledger.snapshot()['spent_tests'],[self.old_key,self.new_key])
        # Historical acceptance never reactivates the expired new control budget.
        with self.assertRaises(b.BudgetError):store.snapshot(self.now+4200)


if __name__=='__main__':unittest.main()
