"""Private metadata-only fixtures for a paid, explicitly authorized replacement."""
import copy
from pathlib import Path
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock

CODE=Path(__file__).resolve().parents[1]/'scripts/pricefm'
if str(CODE) not in sys.path:sys.path.insert(0,str(CODE))
from pricefm_hb import activation as a, cost_control as c, operation_budget as b, policy, registry as r
from pricefm_hb import benchmark_plan as plans
from pricefm_hb.benchmark_plan_tests import metadata


def build_replacement_fixture(root,now=None,qualification_augment=None,old_expires_epoch=None):
    """Build real-shaped private JSON; no current journal or array is read."""
    root=Path(root);root.mkdir(parents=True,exist_ok=True);now=time.time() if now is None else now
    old_end=now+1200 if old_expires_epoch is None else old_expires_epoch
    old_start=min(now-1000,old_end-1000);old_terminal=min(now-50,old_end-50)
    world=SimpleNamespace(root=root,now=now,central=root/'canonical',old_expires_epoch=old_end)
    world.central.mkdir(exist_ok=True)
    def write(name,value):
        path=root/name;path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value)
        return policy.pin(path)
    world.write=write
    world.sources=a.executed_sources('COST_ONLY')
    old_sources={name:'0'*64 for name in world.sources}
    world.old_plans={};world.plans={};world.plan_pins={};world.old_releases={};world.old_release_pins={}
    world.old_keys={study:{'operational':r.identity('old-'+study+'-op'),'legacy':r.identity('old-'+study+'-legacy')} for study in ('FI','DK2')}
    test_keys={name:r.identity('test-'+name) for name in ('01','02','03','04')};world.test_keys=test_keys
    resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=1200,wall_seconds=1200);world.resources=resources
    old_roles={test_keys['03']:dict(purpose='CONTROL_TEST',study='TEST',scope_id='r157_control_placement_03')}
    old_roles.update({world.old_keys[s]['operational']:dict(purpose='COST_ONLY',study=s,scope_id='old_'+s+'_scope') for s in ('FI','DK2')})
    old_auth=write('old/control-authority.json',dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=b.OWNER,
        kind='INITIAL',CPU_ceiling=720,nonrenewing=True,scope_id='old-control-03',expires_epoch=old_end,
        recovery_claims=old_roles,max_new_claims=3))
    world.old_control_spec=dict(path=str(world.central/'old-control-03.control_cpu.json'),authorization_pin=old_auth,scope_id='old-control-03')
    legacy_claims={};op_claims={}
    for study in ('FI','DK2'):
        config,prep=metadata(study)
        prep_pin=write('science/'+study+'/preparation.json',prep);config_pin=write('science/'+study+'/config.json',config)
        old_scope='old_'+study+'_scope'
        plan=dict(schema=plans.SCHEMA,status='METADATA_PLAN_COMPLETE_BENCHMARK_NOT_ADMITTED',study=study,region=prep['region'],
            canonical_preparation=dict(prep_pin,source=prep['source']),canonical_config=config_pin,
            canonical_dependency=dict(root='/opaque/dependency',head='fixed'),scientific_universe=plans.COUNTS[study],packages=prep['packages'],
            resources=plans.LIMITS,schedule=plans.make_schedule(study,config,prep),all_parent_preflight=plans.make_preflight(prep),
            input_allowlist={'/opaque/fit.rds':dict(sha256='f'*64,bytes=123,opaque_provenance=True)},inventory=dict(bytes=123),
            schedule_summary=dict(arithmetic_calls=18,timed_rows=16),dependency_scope=dict(original_parent_panel=True),
            future_full_prefix_pricing=dict(automatic_admission=False),adapter_feasibility=dict(adapter_sources={}),
            claim=dict(scientific_exclusion_key='same-science-'+study,planned_attempt_id=old_scope,
                execution_namespace='BENCHMARK_TEST/'+study+'/'+prep_pin['sha256'][:16]+'/'+old_scope,
                status='UNCLAIMED_NOT_ADMITTED',same_key_across_hosts=True,same_key_across_new_attempt_ids=True,
                prior_failure_requires_explicit_new_authority=True,no_automatic_retry=True))
        old_plan_pin=write('old/'+study+'/plan.json',plan);world.old_plans[study]=plan
        keys=world.old_keys[study]
        release=dict(purpose='COST_ONLY',study=study,scope_id=old_scope,task_key=keys['operational'],
            plan_sha256=old_plan_pin['sha256'],scientific_exclusion_key=plan['claim']['scientific_exclusion_key'],
            resources=resources,source_hashes=old_sources,control_cpu_scope=world.old_control_spec,
            remote_root='/remote/old-'+study,files={'plan.json':dict(sha256=old_plan_pin['sha256'],bytes=Path(old_plan_pin['path']).stat().st_size)})
        rp=write('old/'+study+'/release.json',release);world.old_releases[study]=release;world.old_release_pins[study]=rp
        legacy=dict(task_key=keys['legacy'],task=c.task_identity(plan,old_plan_pin['sha256']),scope_id=old_scope,
            state='FAILED_RECONCILED',application_accepted=False,release_sha256=rp['sha256'],config_sha256='d'*64,
            release_path=str(Path(rp['path']).parent),remote_root=release['remote_root'],reserved_CPU_seconds=1200,
            wall_seconds=1200,created=old_start,events=[dict(epoch=old_terminal,**{'from':'AMBIGUOUS','to':'FAILED_RECONCILED'})])
        operational=dict(task_key=keys['operational'],task=dict(purpose='COST_ONLY',study=study,
            plan_sha256=old_plan_pin['sha256'],scientific_exclusion_key=plan['claim']['scientific_exclusion_key']),
            scope_id=old_scope,state='FAILED_RECONCILED',application_accepted=False,release_path=legacy['release_path'],
            release_sha256=rp['sha256'],resources=resources,remote_root=release['remote_root'],created=old_start,
            legacy_cost_key=keys['legacy'],events=[dict(epoch=old_terminal,from_state='AMBIGUOUS',to_state='FAILED_RECONCILED')])
        if study=='DK2':
            legacy['job_id']=operational['job_id']='869420'
            operational['publication']=str(root/'proof/DK2/publication')
        legacy_claims[keys['legacy']]=legacy;op_claims[keys['operational']]=operational
        new=copy.deepcopy(plan);new['claim']['planned_attempt_id']='r161_'+study+'_replacement_01'
        new['claim']['execution_namespace']='BENCHMARK_TEST/'+study+'/'+prep_pin['sha256'][:16]+'/'+new['claim']['planned_attempt_id']
        world.plans[study]=new;world.plan_pins[study]=write('new/'+study+'/plan.json',new)
    failures=[]
    for number,job in (('01','868958'),('02','869313')):
        key=test_keys[number];op_claims[key]=dict(task_key=key,scope_id='r157_control_placement_'+number,
            state='FAILED_RECONCILED',application_accepted=False,job_id=job,
            task=dict(purpose='CONTROL_TEST',study='TEST'),events=[dict(epoch=now-70,from_state='ACTIVATED',to_state='FAILED_RECONCILED')])
        failures.append(dict(prior_failed_claim_key=key,prior_failed_job_id=job))
    test03_release=write('old/TEST03/release.json',dict(purpose='CONTROL_TEST',study='TEST',task_key=test_keys['03'],
        scope_id='r157_control_placement_03',source_hashes=old_sources,control_cpu_scope=world.old_control_spec))
    test03_collection=write('old/TEST03/publication/collection.json',dict(task_key=test_keys['03'],application_accepted=True,no_refund=True))
    op_claims[test_keys['03']]=dict(task_key=test_keys['03'],state='COLLECTED',application_accepted=True,
        scope_id='r157_control_placement_03',job_id='869381',task=dict(purpose='CONTROL_TEST',study='TEST'),
        release_sha256=test03_release['sha256'],release_path=str(Path(test03_release['path']).parent),
        publication=str(Path(test03_collection['path']).parent),events=[dict(epoch=min(now-60,old_end-60),from_state='ACTIVATED',to_state='COLLECTED')])
    accepted_reference=dict(claim_key=test_keys['03'],job_id='869381',release=test03_release,
        publication=test03_collection,source_hashes=old_sources)
    world.legacy_claims=legacy_claims
    if qualification_augment is not None:qualification_augment(world,op_claims,failures,accepted_reference)
    world.legacy_state=dict(schema=c.SCHEMA,owner=c.OWNER,claims=legacy_claims,
        spent_regions={s:world.old_keys[s]['legacy'] for s in ('FI','DK2')})
    world.old_operational_state=dict(schema='r157_hb_lifecycle_v1',owner=c.OWNER,claims=op_claims,
        spent_tests=[test_keys[n] for n in ('01','02','03')])
    legacy_snapshot=write('archive/legacy.json',world.legacy_state)
    op_snapshot=write('archive/operational.json',world.old_operational_state)
    paid_claims={key:dict(reserved_CPU=230,no_refund=True,violations=[]) for key in old_roles}
    paid_claims[world.old_keys['FI']['operational']].update(violations=[dict(reason='PARENT_CPU_CAP_EXCEEDED',lifetime='old-process')],
        parent_measured_CPU=8.502209,parent_slices={'old-process':dict(reserved_CPU=8)},
        parent_processes={'old-process':dict(CPU=8.502209)})
    world.paid_control=dict(schema=b.SCHEMA,owner=b.OWNER,scope_id='old-control-03',kind='INITIAL',CPU_ceiling=720,
        no_refund=True,authorization=old_auth,created_epoch=old_start,expires_epoch=old_end,
        claim_reserved_CPU=690,publication_reserved_CPU=30,claims=paid_claims,
        publication=dict(status='PAID_RETAINED_PUBLICATION',reserved_CPU=30,no_refund=True))
    r.write(world.old_control_spec['path'],world.paid_control)
    paid_pin=write('archive/paid03.json',world.paid_control)
    qualification=dict(protocol_version=c.REPLACEMENT_PROTOCOL,schema='r161_control_qualification_lineage_v1',
        status='ROOT_ADMITTED_TEST04_PRESERVING_OLD_ACCEPTED_TEST',controller=c.OWNER,created_epoch=now-20,
        expires_epoch=now+3600,max_new_attempts=1,old_charges_refunded=False,old_clocks_mutated=False,
        paid_control_snapshot=paid_pin,paid_control_authorization=old_auth,prior_failed_tests=failures,
        prior_accepted_test=accepted_reference)
    world.qualification_lineage=qualification;world.qualification_lineage_pin=write('new/qualification-lineage.json',qualification)
    world.lineages={study:dict(prior_legacy_claim_key=world.old_keys[study]['legacy'],
        prior_operational_claim_key=world.old_keys[study]['operational'],prior_legacy_snapshot=legacy_snapshot,
        prior_operational_snapshot=op_snapshot,prior_release=world.old_release_pins[study],paid_control_snapshot=paid_pin,
        paid_control_authorization=old_auth,old_charges_retained=True) for study in ('FI','DK2')}
    # A full private resource policy with source17 pins and conserved local lock.
    (root/'muscat_cpu30.lock').touch()
    resource=write('policy/legacy-resource.json',dict(schema='r154_resource_policy_v1',max_new_numerical_workers=1,
        nonrenewing=True,physical_CPU_allocation=dict(cpu=30,SMT62_additional_worker=False),created_epoch=now-2000,
        expires_epoch=now+5000,Jerez_new_predictive_or_repair_worker_admitted=False))
    contract=write('policy/legacy-contract.json',dict(schema='r154_global_permits_v1',max_new_numerical=1,
        new_numerical_concurrency_above_one_authorized=False,nonrenewing=True,jerez_numerical_allocation=None,
        SMT62_science_authorized=False,all_original_allocation_clocks_ceilings_and_lock_identity_preserved=True,
        evidence=dict(resource_policy=resource),created_epoch=now-2000,expires_epoch=now+5000,
        permits=[dict(cpu=30,host='muscat',id='muscat_cpu30',science=['EE','LV','CERTIFICATE_REFERENCE'],sequential=True)],lock_dir=str(root)))
    with mock.patch.object(policy,'owner'):
        draft=policy.build_policy(contract,resource,[policy.pin(CODE/'pricefm_hb'/name) for name in world.sources],[],
            scope_id='r161-private-policy',expires_epoch=now+6000,owner_admission_dir=root/'owners',now=now-15,
            historical_EE_release=write('policy/historical-ee.json',{'historical_metadata_only':True}))
        auth=write('policy/adoption.json',dict(status='ROOT_REVIEWED_CROSS_HOST_IMPLEMENTATION_AUTHORIZATION',controller=c.OWNER,
            policy_draft_sha256=r.identity(draft),user_requested_implementation=True,old_local_clock_and_charges_preserved=True))
        packet=policy.admit_policy(draft,auth,now=now-15)
    world.resource_policy_pin=write('policy/current-policy.json',packet)
    world.new_op_keys={study:r.identity(dict(purpose='COST_ONLY',scope_id=world.plans[study]['claim']['planned_attempt_id'],
        study=study,scientific_exclusion_key=world.plans[study]['claim']['scientific_exclusion_key'],
        plan_sha256=world.plan_pins[study]['sha256'])) for study in ('FI','DK2')}
    roles={test_keys['04']:dict(purpose='CONTROL_TEST',study='TEST',scope_id='r161_control_placement_04')}
    roles.update({world.new_op_keys[s]:dict(purpose='COST_ONLY',study=s,scope_id=world.plans[s]['claim']['planned_attempt_id']) for s in ('FI','DK2')})
    world.authorization=dict(status='ROOT_ADMITTED_R157_CONTROL_CPU_SCOPE',controller=c.OWNER,scope_id='r161-control-04',
        kind='INITIAL',CPU_ceiling=720,nonrenewing=True,created_epoch=now-10,expires_epoch=now+3600,
        protocol_version=c.REPLACEMENT_PROTOCOL,max_new_claims=3,recovery_claims=roles,
        resource_policy=world.resource_policy_pin,qualification_lineage=world.qualification_lineage_pin,
        cost_replacement_lineage=world.lineages,old_scope_renewed=False,old_charges_refunded=False)
    world.authorization_pin=write('new/control-authority.json',world.authorization)
    world.control_spec=dict(path=str(world.central/'r161-control-04.control_cpu.json'),authorization_pin=world.authorization_pin,scope_id='r161-control-04')
    world.control=dict(schema=b.SCHEMA,owner=b.OWNER,scope_id='r161-control-04',kind='INITIAL',CPU_ceiling=720,
        no_refund=True,authorization=world.authorization_pin,created_epoch=now-10,expires_epoch=now+3600,
        claim_reserved_CPU=230,publication_reserved_CPU=0,claims={test_keys['04']:dict(reserved_CPU=230,no_refund=True)},
        publication=None,recovery_claims=roles)
    r.write(world.control_spec['path'],world.control)
    test04_release=write('new/TEST04/release.json',dict(purpose='CONTROL_TEST',study='TEST',task_key=test_keys['04'],
        scope_id='r161_control_placement_04',source_hashes=world.sources,control_cpu_scope=world.control_spec))
    world.operational_state=copy.deepcopy(world.old_operational_state)
    world.operational_state['claims'][test_keys['04']]=dict(task_key=test_keys['04'],scope_id='r161_control_placement_04',
        task=dict(purpose='CONTROL_TEST',study='TEST'),state='COLLECTED',application_accepted=True,
        release_path=str(Path(test04_release['path']).parent),release_sha256=test04_release['sha256'],job_id='900004')
    world.operational_state['spent_tests'].append(test_keys['04'])
    world.permits={};world.permit_pins={};world.releases={}
    for study in ('FI','DK2'):
        plan=world.plans[study];lineage=world.lineages[study];old=world.old_releases[study];keys=world.old_keys[study]
        proof=dict(schema='r161_zero_arithmetic_evidence_v1',status='ROOT_VERIFIED_NO_COST_ARITHMETIC',controller=c.OWNER,
            prior_legacy_claim_key=keys['legacy'],prior_operational_claim_key=keys['operational'],
            release_sha256=world.old_release_pins[study]['sha256'],job_id=op_claims[keys['operational']].get('job_id'),
            arithmetic_calls=0,numerical_payload_started=False,benchmark_outputs_present=False,observed_epoch=now-30)
        failure=dict(zero_arithmetic=write('proof/'+study+'/zero-arithmetic.json',proof))
        base=dict(protocol_version=c.REPLACEMENT_PROTOCOL,schema=c.REPLACEMENT_SCHEMA,status=c.REPLACEMENT_STATUS,
            controller=c.OWNER,study=study,created_epoch=now-5,expires_epoch=now+3500,max_new_attempts=1,
            old_charges_refunded=False,old_clocks_mutated=False,automatic_retry=False,
            new_scope_id=plan['claim']['planned_attempt_id'],new_plan_sha256=world.plan_pins[study]['sha256'],
            new_operational_task_key=world.new_op_keys[study],new_legacy_task_key=r.identity(c.task_identity(plan,world.plan_pins[study]['sha256'])),
            new_executed_sources=world.sources,new_control_cpu_scope=world.control_spec,resource_policy=world.resource_policy_pin,
            resources=resources,scientific_CPU_seconds=1200,scientific_wall_seconds=1200,control_CPU_reservation=230,
            priced_maximum_CPU=217,parent_CPU_cap=60,parent_lifetimes=7,parent_slice_CPU=8,operation_limits=b.INITIAL_LIMITS,
            prior_plan=policy.pin(root/'old'/study/'plan.json'),**{name:item for name,item in lineage.items() if name!='old_charges_retained'})
        if study=='FI':
            audit=dict(schema='r161_terminal_cost_failure_audit_v1',status='ROOT_VERIFIED_TERMINAL_COST_FAILURE_NO_ARITHMETIC',
                controller=c.OWNER,study=study,**{name:base[name] for name in ('prior_legacy_claim_key','prior_operational_claim_key',
                    'prior_release','prior_plan','prior_legacy_snapshot','prior_operational_snapshot','paid_control_snapshot')},
                job_id=None,state='FAILED_RECONCILED',application_accepted=False,arithmetic_calls=0,no_active_jobs=True,
                scientific_CPU_reserved=1200,control_CPU_reserved=230,parent_control_violations=paid_claims[keys['operational']]['violations'],
                observed_epoch=now-30)
            failure.update(kind='root_terminal_audit',terminal_audit=write('proof/FI/terminal-audit.json',audit))
        else:
            error=dict(type='ActivationError',message='failed before qualified payload')
            error_pin=write('proof/DK2/publication/outputs/worker-failure.json',error)
            worker=dict(schema='r157_hb_lifecycle_v1',task_key=keys['operational'],job_id='869420',release_sha256=base['prior_release']['sha256'],
                source_hashes=old_sources,application_passed=False,error=error,files={'worker-failure.json':error_pin['sha256']},new_model_fits=0,official_origins=0)
            rows=['869420'+suffix+'|FAILED|1:0|4|1|00:00:01|375240K|node-13|2026-10-28T18:55:13|2026-10-28T18:55:17' for suffix in ('','.batch','.0')]
            accounting=dict(task_key=keys['operational'],job_id='869420',release_sha256=base['prior_release']['sha256'],terminal=True,
                complete=False,squeue='',sacct_with_times='\n'.join(rows)+'\n')
            failure.update(kind='worker',worker_failure=error_pin,worker_evidence=write('proof/DK2/publication/outputs/worker_evidence.json',worker),
                accounting=write('proof/DK2/publication/accounting.json',accounting),
                collection=write('proof/DK2/publication/collection.json',dict(schema='r157_hb_lifecycle_v1',task_key=keys['operational'],
                    application_accepted=False,no_refund=True,reserved_CPU_seconds=1200)))
        base['prior_failure']=failure;world.permits[study]=base;world.permit_pins[study]=write('new/'+study+'/replacement-permit.json',base)
        world.releases[study]=dict(purpose='COST_ONLY',study=study,task_key=world.new_op_keys[study],plan_sha256=world.plan_pins[study]['sha256'],
            scope_id=plan['claim']['planned_attempt_id'],resources=resources,source_hashes=world.sources,control_cpu_scope=world.control_spec,
            cost_replacement=world.permit_pins[study],scientific_exclusion_key=plan['claim']['scientific_exclusion_key'])
    return world


class ReplacementTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.world=build_replacement_fixture(Path(self.tmp.name))
        for module,key,value in ((c,'CENTRAL',self.world.central),(c,'owner',lambda:None),(b,'owner',lambda:None)):
            patch=mock.patch.object(module,key,value);patch.start();self.addCleanup(patch.stop)

    def validate(self,study='FI',**kwargs):
        w=self.world
        return c.validate_replacement(w.permit_pins[study],w.plans[study],w.plan_pins[study]['sha256'],
            state=w.legacy_state,operational_state=w.operational_state,now=w.now,**kwargs)

    def test_both_actual_shape_failure_proofs_accept_without_touching_old_history(self):
        w=self.world;before=copy.deepcopy((w.legacy_state,w.operational_state,w.paid_control))
        self.assertEqual(len(self.world.plans['FI']['all_parent_preflight']),60)
        self.assertEqual(len(self.world.plans['DK2']['all_parent_preflight']),63)
        self.assertEqual(len(self.world.plans['FI']['schedule']),18)
        for study in ('FI','DK2'):self.assertEqual(self.validate(study)['study'],study)
        self.assertEqual((w.legacy_state,w.operational_state,w.paid_control),before)

    def test_wrong_source_expiry_backdate_refund_memory_or_extra_attempt_is_rejected(self):
        w=self.world
        for changed in ({'new_executed_sources':{'wrong':'f'*64}}, {'expires_epoch':w.now-1},
                {'created_epoch':w.now-100}, {'old_charges_refunded':True},{'old_clocks_mutated':True},
                {'max_new_attempts':2},{'resources':dict(w.resources,memory_MiB=8192)},
                {'resources':dict(w.resources,cpus=True)}):
            with self.subTest(changed=changed):
                pin=w.write('wrong-permit.json',dict(w.permits['FI'],**changed))
                with self.assertRaises((ValueError,OSError)):
                    c.validate_replacement(pin,w.plans['FI'],w.plan_pins['FI']['sha256'],state=w.legacy_state,
                        operational_state=w.operational_state,now=w.now)

    def test_default_spent_region_stays_blocked_and_old_claims_cannot_be_reset(self):
        w=self.world;r.write(w.central/'cost_only_registry.json',w.legacy_state)
        with self.assertRaisesRegex(c.GateError,'already spent'):
            c.Ledger().reserve(w.plans['FI'],w.plan_pins['FI']['sha256'],'a'*64,'b'*64,'/new','/remote/new')
        for change in ('state','counter','violation'):
            with self.subTest(change=change):
                state=copy.deepcopy(w.legacy_state);op=copy.deepcopy(w.operational_state)
                if change=='state':state['claims'][w.old_keys['FI']['legacy']]['state']='RESERVED'
                if change=='counter':state['spent_regions'].pop('FI')
                if change=='violation':
                    paid=copy.deepcopy(w.paid_control);paid['claims'][w.old_keys['FI']['operational']]['violations']=[]
                    r.write(w.old_control_spec['path'],paid)
                with self.assertRaises((ValueError,OSError)):
                    c.validate_replacement(w.permit_pins['FI'],w.plans['FI'],w.plan_pins['FI']['sha256'],
                        state=state,operational_state=op,now=w.now)
                r.write(w.old_control_spec['path'],w.paid_control)

    def test_active_owner_or_unqualified04_blocks_even_with_new_grant(self):
        w=self.world
        for change in ('active','missing04','changed04'):
            with self.subTest(change=change):
                op=copy.deepcopy(w.operational_state)
                if change=='active':op['claims']['unknown']={'state':'SUBMITTED'}
                if change=='missing04':op['claims'].pop(w.test_keys['04'])
                if change=='changed04':op['claims'][w.test_keys['04']]['application_accepted']=False
                with self.assertRaises((ValueError,OSError)):
                    c.validate_replacement(w.permit_pins['FI'],w.plans['FI'],w.plan_pins['FI']['sha256'],
                        state=w.legacy_state,operational_state=op,now=w.now)

    def test_same_science_flags_parent_panel_and_RNG_are_immutable(self):
        w=self.world
        for change in ('parents','rng','flags','namespace'):
            with self.subTest(change=change):
                plan=copy.deepcopy(w.plans['FI'])
                if change=='parents':plan['all_parent_preflight'].pop()
                if change=='rng':plan['schedule'][0]['descriptor']['stable_rng_origin_keys'][0]+=1
                if change=='flags':plan['claim']['no_automatic_retry']=False
                if change=='namespace':plan['claim']['execution_namespace']='/different'
                with self.assertRaises((ValueError,OSError)):
                    c.validate_replacement(w.permit_pins['FI'],plan,w.plan_pins['FI']['sha256'],state=w.legacy_state,
                        operational_state=w.operational_state,now=w.now)

    def test_one_append_only_replacement_reservation_and_protected_lineage(self):
        w=self.world;study='FI';permit=w.permits[study];key=w.new_op_keys[study]
        op=dict(task_key=key,task=dict(purpose='COST_ONLY',study=study,plan_sha256=w.plan_pins[study]['sha256'],
            scientific_exclusion_key=w.plans[study]['claim']['scientific_exclusion_key']),resources=w.resources,
            cost_replacement=w.permit_pins[study],state='RESERVED',scope_id=w.plans[study]['claim']['planned_attempt_id'],
            release_sha256='a'*64,config_sha256='b'*64,release_path='/new',remote_root='/remote/new')
        w.operational_state['claims'][key]=op
        r.write(w.central/'activation_registry.json',w.operational_state)
        r.write(w.central/'cost_only_registry.json',w.legacy_state)
        before=copy.deepcopy(w.legacy_state);ledger=c.Ledger()
        claim=ledger.reserve(w.plans[study],w.plan_pins[study]['sha256'],'a'*64,'b'*64,'/new','/remote/new',
            replacement_pin=w.permit_pins[study])
        state=ledger.snapshot()
        self.assertEqual(state['spent_regions'],before['spent_regions'])
        self.assertEqual({k:state['claims'][k] for k in before['claims']},before['claims'])
        self.assertEqual(state['replacement_spent_regions'],{'FI':permit['new_legacy_task_key']})
        self.assertEqual(claim['replacement_for'],permit['prior_legacy_claim_key'])
        self.assertEqual(claim['cost_replacement'],w.permit_pins[study])
        with self.assertRaises(c.GateError):
            ledger.reserve(w.plans[study],w.plan_pins[study]['sha256'],'a'*64,'b'*64,'/new','/remote/new',replacement_pin=w.permit_pins[study])
        with self.assertRaises(c.GateError):
            ledger.transition(claim['task_key'],'RESERVED','STAGED',replacement_for='different')

    def test_new04_auth_cannot_be_backdated_forged_or_reuse03(self):
        w=self.world
        self.assertEqual(b.recovery_claims(w.authorization),w.authorization['recovery_claims'])
        for change in ('backdate','scope03','protocol-only','refund','missing-roles'):
            with self.subTest(change=change):
                authorization=copy.deepcopy(w.authorization)
                if change=='backdate':authorization['created_epoch']=w.now-100
                if change=='scope03':authorization['recovery_claims'][w.test_keys['04']]['scope_id']='r157_control_placement_03'
                if change=='protocol-only':authorization['qualification_lineage']=w.write('forged-lineage.json',{'protocol_version':c.REPLACEMENT_PROTOCOL})
                if change=='refund':authorization['old_charges_refunded']=True
                if change=='missing-roles':authorization.pop('recovery_claims')
                with self.assertRaises((ValueError,OSError)):b.recovery_claims(authorization)

    def test_sealed_worker_payload_marker_or_wrong_root_overrun_audit_is_rejected(self):
        w=self.world
        worker_pin=w.permits['DK2']['prior_failure']['worker_evidence']
        original=r.read(worker_pin['path']);changed=copy.deepcopy(original)
        changed['files']['payload-process-limits.json']='a'*64
        r.write(worker_pin['path'],changed)
        permit=copy.deepcopy(w.permits['DK2']);permit['prior_failure']['worker_evidence']=policy.pin(worker_pin['path'])
        pin=w.write('bad-worker-permit.json',permit)
        with self.assertRaises(c.GateError):
            c.validate_replacement(pin,w.plans['DK2'],w.plan_pins['DK2']['sha256'],state=w.legacy_state,
                operational_state=w.operational_state,now=w.now)
        r.write(worker_pin['path'],original)
        audit_pin=w.permits['FI']['prior_failure']['terminal_audit'];audit=r.read(audit_pin['path'])
        for change in ({'parent_control_violations':[]},{'no_active_jobs':False},{'observed_epoch':w.now-1000}):
            with self.subTest(change=change):
                fresh=w.write('bad-terminal-audit.json',dict(audit,**change));permit=copy.deepcopy(w.permits['FI'])
                permit['prior_failure']['terminal_audit']=fresh;pin=w.write('bad-audit-permit.json',permit)
                with self.assertRaises(c.GateError):
                    c.validate_replacement(pin,w.plans['FI'],w.plan_pins['FI']['sha256'],state=w.legacy_state,
                        operational_state=w.operational_state,now=w.now)

    def test_expired03_is_history_and_late_reads_never_admit_expired04_operations(self):
        w=build_replacement_fixture(self.world.root/'expired',old_expires_epoch=self.world.now-1000)
        with mock.patch.object(c,'CENTRAL',w.central):
            c.validate_replacement(w.permit_pins['FI'],w.plans['FI'],w.plan_pins['FI']['sha256'],
                state=w.legacy_state,operational_state=w.operational_state,now=w.now)
        with self.assertRaises(b.BudgetError):b.OperationBudget(w.old_control_spec['path']).snapshot(now=w.now)
        with mock.patch.object(b.time,'time',return_value=w.now+8000):
            self.assertEqual(b.recovery_claims(w.authorization),w.authorization['recovery_claims'])
            with self.assertRaises(b.BudgetError):b.OperationBudget(w.control_spec['path']).snapshot()

    def test_new_control_counts_are_bounded_to_three230_claims_and_seven8_parent_slices(self):
        w=self.world;before=Path(w.old_control_spec['path']).read_bytes();store=b.OperationBudget(w.control_spec['path'])
        for study in ('FI','DK2'):
            role=w.authorization['recovery_claims'][w.new_op_keys[study]]
            store.reserve_claim(w.new_op_keys[study],now=w.now,**role)
        store.reserve_publication(now=w.now)
        self.assertEqual(store.snapshot(w.now)['claim_reserved_CPU']+store.snapshot(w.now)['publication_reserved_CPU'],720)
        key=w.new_op_keys['FI']
        for index in range(7):
            store.reserve_parent_slice(key,dict(pid=100+index,start_ticks=1000+index,boot_id='fixture'),8,now=w.now)
        self.assertEqual(store.snapshot(w.now)['claims'][key]['parent_reserved_CPU'],56)
        with self.assertRaises(b.BudgetError):
            store.reserve_parent_slice(key,dict(pid=999,start_ticks=9999,boot_id='fixture'),8,now=w.now)
        self.assertEqual(Path(w.old_control_spec['path']).read_bytes(),before)

    def test_segmented_metadata_plan_bounds_whole_stage_without_reading_assets(self):
        files={'opaque-member-'+str(index)+'.rds':dict(bytes=80*1024**2,sha256=r.identity(index)) for index in range(8)}
        plan=c.replacement_partition_manifest({'files':files},'a'*64)
        self.assertEqual(len(plan['parts']),2)
        self.assertEqual(len(plan['verification_groups']),4)
        for key,limit in (('parts',c.STAGE_PART_BYTES),('verification_groups',c.STAGE_GROUP_BYTES)):
            names=[name for group in plan[key] for name in group['members']]
            self.assertEqual(sorted(names),sorted(files))
            self.assertTrue(all(group['bytes']<=limit for group in plan[key]))
        for bad in ({'too-large.rds':dict(bytes=c.STAGE_GROUP_BYTES+1,sha256='b'*64)},
                {'../outside.json':dict(bytes=1,sha256='b'*64)},
                {'opaque-'+str(i):dict(bytes=80*1024**2,sha256='b'*64) for i in range(10)}):
            with self.assertRaises(c.GateError):c.replacement_partition_manifest({'files':bad},'a'*64)


if __name__=='__main__':unittest.main()
