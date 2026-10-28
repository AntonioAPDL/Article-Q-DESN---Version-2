"""Explicit third qualification preserves both paid failed predecessors."""
import copy
from pathlib import Path
import unittest
from unittest import mock
from . import activation as a, lifecycle as l, operation_budget as b, policy, registry as r
from . import allocation_limits_tests as fixtures


class ThirdQualificationTests(unittest.TestCase):
    write=fixtures.AllocationLimitsTests.write
    replacement=fixtures.AllocationLimitsTests.replacement

    def setUp(self):
        fixtures.AllocationLimitsTests.setUp(self)
        self.when=self.now+1;self.packet={'expires_epoch':self.now+3500}
        auth=dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=a.OWNER,scope_id='paid-scope02',
            kind='INITIAL',CPU_ceiling=720,nonrenewing=True,expires_epoch=self.now+3600)
        ap=self.write('paid02-authority.json',auth)
        self.old02=b.OperationBudget.create(self.central/'paid-scope02.control_cpu.json',
            scope_id=auth['scope_id'],authorization_pin=ap,expires_epoch=auth['expires_epoch'])
        self.second_key='paid-failed-second';self.old02.reserve_claim(self.second_key)
        spec=dict(path=str(self.old02.path),authorization_pin=ap,scope_id=auth['scope_id'])
        second_old=dict(purpose='CONTROL_TEST',task_key=self.second_key,resources=self.resources,
            source_hashes={'retained-second-source':'e'*64},control_cpu_scope=spec)
        release_pin=self.write('second-release/release.json',second_old)
        pub=self.root/'second-publication';pub.mkdir();(pub/'release.json').write_bytes(Path(release_pin['path']).read_bytes())
        failure=dict(type='ActivationError',message='retained second limit attestation failure')
        fp=self.write('second-publication/outputs/worker-failure.json',failure)
        wp=self.write('second-publication/outputs/worker_evidence.json',dict(schema=l.SCHEMA,task_key=self.second_key,
            job_id='869313',release_sha256=release_pin['sha256'],application_passed=False,error=failure,
            files={'worker-failure.json':fp['sha256']}))
        rows='\n'.join('869313'+suffix+'|FAILED|1:0|4|1|00:00:00.847|375240K|node-13|2026-10-28T18:55:13|2026-10-28T18:55:17'
            for suffix in ('','.batch','.0'))+'\n'
        account=self.write('second-publication/accounting.json',dict(task_key=self.second_key,job_id='869313',
            release_sha256=release_pin['sha256'],terminal=True,complete=False,squeue='',sacct_with_times=rows))
        collection=self.write('second-publication/collection.json',dict(schema=l.SCHEMA,task_key=self.second_key,
            application_accepted=False,no_refund=True,reserved_CPU_seconds=120))
        self.second_reference=dict(prior_failed_claim_key=self.second_key,prior_failed_job_id='869313',
            prior_publication=collection,prior_evidence=dict(accounting=account,worker_evidence=wp,worker_failure=fp))
        second=dict(task_key=self.second_key,task=dict(purpose='CONTROL_TEST',study='TEST'),state='FAILED_RECONCILED',
            application_accepted=False,job_id='869313',scope_id='r157_control_placement_02',publication=str(pub),
            release_path=str(self.root/'second-release'),release_sha256=release_pin['sha256'],created=self.now-1)
        self.state['claims'][self.second_key]=second;self.state['spent_tests'].append(self.second_key)
        r.write(self.ledger.path,self.state)
        self.new_key='explicit-third-key';scope='r157_control_placement_03'
        roles={self.new_key:dict(purpose='CONTROL_TEST',study='TEST',scope_id=scope),
            'FI-cost':dict(purpose='COST_ONLY',study='FI',scope_id='FI-cost-01'),
            'DK2-cost':dict(purpose='COST_ONLY',study='DK2',scope_id='DK2-cost-01')}
        new_auth=dict(auth,scope_id='new-scope03',expires_epoch=self.now+3400,recovery_claims=roles,max_new_claims=3)
        np=self.write('new03-authority.json',new_auth)
        self.new_budget=b.OperationBudget.create(self.central/'new-scope03.control_cpu.json',scope_id=new_auth['scope_id'],
            authorization_pin=np,expires_epoch=new_auth['expires_epoch'],now=self.when)
        new_spec=dict(path=str(self.new_budget.path),authorization_pin=np,scope_id=new_auth['scope_id'])
        snap=self.root/'immutable-paid02.json';snap.write_bytes(self.old02.path.read_bytes())
        self.recovery=dict(schema=l.CONTROL_RECOVERY_SCHEMA,
            status='ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_PAID_HISTORY',controller=a.OWNER,
            created_epoch=self.when,expires_epoch=new_auth['expires_epoch'],old_control_cpu_scope=spec,
            old_snapshot=policy.pin(snap),new_control_cpu_scope=new_spec,max_new_claims=3,kind='INITIAL',CPU_ceiling=720,
            old_charges_refunded=False,old_clocks_mutated=False,automatic_retry=False)
        self.q=dict(self.q,**self.second_reference,scope_id=scope,created_epoch=self.when,
            expires_epoch=new_auth['expires_epoch'],prior_failed_tests=[self.reference,self.second_reference],
            control_recovery=self.write('recovery03.json',self.recovery))
        self.new_release.update(task_key=self.new_key,scope_id=scope,control_cpu_scope=new_spec)
        self.patches=[mock.patch.object(l.time,'time',return_value=self.when),
            mock.patch.object(l,'policy_document',return_value=self.packet)]
        for patch in self.patches:patch.start();self.addCleanup(patch.stop)

    def test_third_requires_both_terminal_failures_and_preserves_every_spent_key(self):
        release=self.replacement();old_bytes=self.old02.path.read_bytes();old_state=copy.deepcopy(self.state)
        self.ledger.reserve(release,self.root/'new-release',self.config)
        state=self.ledger.snapshot();self.assertEqual(state['spent_tests'],[self.old_key,self.second_key,self.new_key])
        self.assertEqual({key:state['claims'][key] for key in old_state['claims']},old_state['claims'])
        self.assertEqual(self.old02.path.read_bytes(),old_bytes)
        self.assertEqual(r.read(self.old02.path)['claim_reserved_CPU'],230)
        state['claims'][self.new_key].update(state='FAILED_RECONCILED',application_accepted=False);r.write(self.ledger.path,state)
        with self.assertRaises(a.ActivationError):
            self.ledger.reserve(dict(release,task_key='fourth-key',scope_id='r157_control_placement_04'),self.root/'new-release',self.config)

    def test_missing_reversed_changed_or_active_predecessor_and_unreviewed_source_reject(self):
        changes=({'prior_failed_tests':[self.second_reference]},
            {'prior_failed_tests':[self.second_reference,self.reference]},
            {'prior_failed_claim_key':self.old_key},{'new_executed_sources':{'wrong':'f'*64}},
            {'scope_id':'r157_control_placement_04'},{'max_new_attempts':2})
        for change in changes:
            value=dict(self.q,**change);release=self.replacement(value)
            with self.subTest(change=change),self.assertRaises((ValueError,OSError)):
                l.validate_control_test_requalification(value,release,self.state,now=self.when,packet=self.packet)
        for changed in (dict(state='SUBMITTED'),dict(application_accepted=True)):
            state=copy.deepcopy(self.state);state['claims'][self.second_key].update(changed)
            with self.assertRaises(a.ActivationError):
                l.validate_control_test_requalification(self.q,self.replacement(),state,now=self.when,packet=self.packet)

    def test_paid_history_all_old_claims_must_be_failed_and_default_expired_status_stays_strict(self):
        release=self.replacement();old=r.read(self.root/'second-release/release.json')
        expired=dict(self.recovery,status='ROOT_ADMITTED_NEW_FINITE_CONTROL_RECOVERY_PRESERVING_EXPIRED_HISTORY')
        with self.assertRaises(a.ActivationError):
            l.validate_control_recovery(expired,old,release,now=self.when,packet=self.packet,state=self.state)
        self.old02.reserve_claim('unreconciled-cost',now=self.when)
        snap=Path(self.recovery['old_snapshot']['path']);snap.write_bytes(self.old02.path.read_bytes())
        value=dict(self.recovery,old_snapshot=policy.pin(snap))
        with self.assertRaises(a.ActivationError):
            l.validate_control_recovery(value,old,release,now=self.when,packet=self.packet,state=self.state)
        self.assertEqual(r.read(self.old02.path)['claim_reserved_CPU'],460)

    def test_COST_requires_one_accepted03_and_revalidates_both_failed_predecessors(self):
        release=self.replacement();self.ledger.reserve(release,self.root/'new-release',self.config)
        state=self.ledger.snapshot();state['claims'][self.new_key].update(state='COLLECTED',application_accepted=True)
        r.write(self.ledger.path,state)
        cost=dict(release,purpose='COST_ONLY',study='FI',task_key='FI-cost',scope_id='FI-cost-01')
        with mock.patch.object(l,'verify_release',return_value=release):
            self.ledger.reserve(cost,self.root/'new-release',self.config)
            state=self.ledger.snapshot();del state['claims']['FI-cost'];state['claims'][self.old_key]['application_accepted']=True
            r.write(self.ledger.path,state)
            with self.assertRaises(a.ActivationError):self.ledger.reserve(cost,self.root/'new-release',self.config)


if __name__=='__main__':unittest.main()
