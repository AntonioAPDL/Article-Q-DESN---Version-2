"""Independent metadata integration boundaries for the prospective R161 path.

No scheduler, transport, numerical import, scientific array, or real registry
is used. Old claim identities and paid failure values reflect the retained
2026-10-28 FI/DK2 failures; all writable paths are private temporary fixtures.
"""
from __future__ import annotations

import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import time
import unittest
from unittest import mock

from pricefm_hb import activation as a, admission as adm, benchmark as bench
from pricefm_hb import cost_control as cost, lifecycle as l, operation_budget as ob, policy, registry as r
from pricefm_hb.environment import REFERENCE_NUMERICAL_ENV, THREAD_ENV
from pricefm_hb.fixture import ARRAY_SHAPES


OLD_FI_OP = '8309cff635d90324c0a630458c8f5b003d43ad36aacc1cb171003992d38d406f'
OLD_FI_LEGACY = 'e015d2e212ddeaabeec7a963691e0d22408e22e1ff7e242aba1f16e052b36a0c'
OLD_DK2_OP = '7d33f867c4f26d8c7a9a158d499087d3ee58ddf2a2323ad04b8deffd9ab0aa7b'
OLD_DK2_LEGACY = '8aa719261207618ff218fc4108fa336832a766cee94ba7beb5b6c981b033efaf'
OLD03_END = 1793222773.5832958
# Exact executed-source index in retained TEST03/release.json. No scientific
# input, result array, runtime grant, or live journal is embedded here.
OLD_ACCEPTED_SOURCES = {
    '__init__.py': '722d56287c657ef4c874e395ca65da2da948f81fe30c05450bde7c444665054f',
    'activation.py': '3ce4bbdec0f1f41b8bfde01672f430dae04af42266765a4f29c67bfefc6db0fb',
    'admission.py': '1ca3c5f9dc17931971e8d58238b7a5abd36f68b541dd1b0d5ad2be48da6340ba',
    'benchmark.py': 'a39128481f7959795fd41f68e5f627d311bd57fbf3e9a79c3caae9602a0f74ab',
    'benchmark_plan.py': '970f050aa5c3354b2b82a198d094158ded5bf57a3c887d8d916943dbcf3be81a',
    'control.py': 'f86fab9998f8ecf792cf959f67467771400d57c07c51ac99ba82663dc252ad4f',
    'cost_control.py': '0367b037bc409724fdd31142979770c6f9dc1d3030211bfdb6528ed1f87cfe14',
    'environment.py': '298a5d262606c6a0a09cf42423429cc1fae63290ebef37a951c2f803aa485ed1',
    'fixture.py': '6aeb500b83c0b8a1505920deed87e6a7402ea1bf80e284cd7c9d3542bb0ba391',
    'handoff.py': '492c183d72648da47d99b01e1aa1f3563df7d23054f4ed32f2380839412dfcca',
    'lifecycle.py': '641a4d15b6670c2f22ca332f2f52677f57282ee7662ac9090f996d3d64367f1f',
    'metered_io.py': '2a46d9d53083e338e87158624530f46ea6d205fb30635cfc9e4f1036819e9405',
    'operation_budget.py': '10d1b6ffd76c9f6f19cac8ce01777d574798f21cf07bb8d9a89df8d99819b16a',
    'policy.py': 'dac5bc5deb0b30242c8b3759f0a14a5368d5defeb0c8b8c6f34f85f2e2f7649f',
    'readiness.py': '2a45d1fbaf6e83f8d2726120e5eb3c2afb2bb2220bdd8d94d2875e98ab5d2141',
    'registry.py': '47163ed96b648d540c74f5a65b40ff73f1bc5e40f60a163d6408398f6f585cc2',
    'science.py': '3db567ec7f98b70449740a285f34f1a5b733ab51f7b7691f2644e8e7a5dba319',
}


def augment_complete_qualification_history(world, claims, failed_references, accepted_reference):
    """Add complete sealed JSON shape before the shared fixture pins history.

    This deliberately uses the real qualification and accounting validators.
    The records describe private test evidence; no science is executed.
    """
    write=world.write
    resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=120,wall_seconds=120)
    def accounting_rows(job,complete=True,times=False):
        suffix='|2026-10-28T19:00:00|2026-10-28T19:00:43' if times else ''
        return '\n'.join(job+step+'|'+('COMPLETED|0:0' if complete else 'FAILED|1:0')+
            '|43|1|00:00:12.339|375240K|node-13'+suffix for step in ('','.batch','.0'))+'\n'
    disabled=REFERENCE_NUMERICAL_ENV['NPY_DISABLE_CPU_FEATURES'].split(',')
    profile=dict(enabled=True,environment=REFERENCE_NUMERICAL_ENV,
        numpy_cpu_features={name:False for name in disabled},numpy_dispatch_targets=disabled,
        openblas_architectures=['Sandybridge'])
    runtime=dict(status='verified',python_version='3.11.13',executable='/private/runtime/bin/python',
        versions=dict(numpy='2.2.6',scipy='1.15.3'),threadpoolctl=[dict(num_threads=1)],
        native_library_sha256={'/private/ref-numpy.so':'1'*64,'/private/ref-scipy.so':'2'*64},
        reference_numerical_profile=profile)
    fixture_sha='f'*64
    prior_job='900003';runtime_job='900002'
    runtime_pin=write('qualification/runtime.json',runtime)
    prior_runtime=dict(runtime,allocation=dict(job_id=prior_job,node='node-13'))
    prior_runtime_pin=write('qualification/parity-runtime.json',prior_runtime)
    parity=dict(status='PASS_TEST_FORECAST_PARITY',accepted=True,
        execution=dict(namespace='TEST',slurm_job_id=prior_job,fixture_manifest_sha256=fixture_sha))
    prior_parity_pin=write('qualification/parity.json',parity)
    prior_seal=write('qualification/parity-seal.json',dict(status='COMPLETE_TEST_ONLY',artifacts={'parity.json':prior_parity_pin['sha256']}))
    request=dict(accepted_parity_fixture_manifest_sha256=fixture_sha,runtime_result=runtime_pin,
        parity_result=prior_parity_pin,parity_seal=prior_seal,parity_runtime_result=prior_runtime_pin)
    for prefix,job,result,relative,extra in (
            ('runtime',runtime_job,runtime_pin,'environment-evidence/runtime-verification.json',{}),
            ('parity',prior_job,prior_parity_pin,'TEST/parity/parity.json',
                {'environment-runtime.json':prior_runtime_pin['sha256']})):
        seal=write('qualification/'+prefix+'-outer.json',dict(schema=r.SCHEMA,application_passed=True,
            job_id=job,files={relative:result['sha256'],**extra}))
        request[prefix+'_qualification_seal']=seal
        request[prefix+'_accounting']=write('qualification/'+prefix+'-accounting.json',dict(job_id=job,
            complete=True,squeue='',sacct=accounting_rows(job)))
    world.complete_qualification_request=request
    for index,job in (('01','868958'),('02','869313')):
        key=world.test_keys[index];root='history/TEST'+index;publication=root+'/published'
        release=dict(purpose='CONTROL_TEST',task_key=key,scope_id='r157_control_placement_'+index,
            source_hashes=OLD_ACCEPTED_SOURCES,resources=resources,control_cpu_scope=world.old_control_spec)
        rp=write(root+'/release.json',release);write(publication+'/release.json',release)
        failure=dict(type='ActivationError',message='retained pre-numerical failure '+index)
        fp=write(publication+'/outputs/worker-failure.json',failure)
        wp=write(publication+'/outputs/worker_evidence.json',dict(schema=l.SCHEMA,task_key=key,job_id=job,
            release_sha256=rp['sha256'],application_passed=False,error=failure,files={'worker-failure.json':fp['sha256']}))
        ap=write(publication+'/accounting.json',dict(task_key=key,job_id=job,release_sha256=rp['sha256'],
            terminal=True,complete=False,squeue='',sacct_with_times=accounting_rows(job,False,True)))
        cp=write(publication+'/collection.json',dict(schema=l.SCHEMA,task_key=key,application_accepted=False,
            no_refund=True,reserved_CPU_seconds=120))
        claims[key].update(release_path=str(Path(rp['path']).parent),release_sha256=rp['sha256'],
            publication=str(Path(cp['path']).parent),created=world.now-200)
        reference=dict(prior_failed_claim_key=key,prior_failed_job_id=job,prior_publication=cp,
            prior_evidence=dict(accounting=ap,worker_evidence=wp,worker_failure=fp))
        failed_references[int(index)-1].clear();failed_references[int(index)-1].update(reference)
    key=world.test_keys['03'];root='history/TEST03';publication=root+'/published';job='869369'
    request_pin=write(root+'/launch-request.json',request)
    release=dict(purpose='CONTROL_TEST',study='TEST',task_key=key,scope_id='r157_control_placement_03',
        source_hashes=OLD_ACCEPTED_SOURCES,resources=resources,control_cpu_scope=world.old_control_spec,
        request_sha256=request_pin['sha256'])
    rp=write(root+'/release.json',release);write(publication+'/release.json',release)
    parity=dict(status='PASS_TEST_FORECAST_PARITY',accepted=True,
        execution=dict(namespace='TEST',slurm_job_id=job,fixture_manifest_sha256=fixture_sha),
        array_comparison={name:dict(accepted=True,shape=shape) for name,shape in ARRAY_SHAPES.items()})
    pp=write(publication+'/outputs/TEST/parity/parity.json',parity)
    sp=write(publication+'/outputs/TEST/parity/completed_evidence.json',dict(status='COMPLETE_TEST_ONLY',artifacts={'parity.json':pp['sha256']}))
    actual_runtime=write(publication+'/outputs/environment-runtime.json',dict(runtime,allocation=dict(job_id=job,node='node-13')))
    authority_sha='a'*64
    wp=write(publication+'/outputs/worker_evidence.json',dict(schema=l.SCHEMA,task_key=key,job_id=job,
        release_sha256=rp['sha256'],authority_sha256=authority_sha,source_hashes=OLD_ACCEPTED_SOURCES,
        application_passed=True,new_model_fits=0,official_origins=0,files={
            'TEST/parity/parity.json':pp['sha256'],'TEST/parity/completed_evidence.json':sp['sha256'],
            'environment-runtime.json':actual_runtime['sha256']}))
    ap=write(publication+'/accounting.json',dict(task_key=key,job_id=job,release_sha256=rp['sha256'],
        terminal=True,complete=True,squeue='',sacct_with_times=accounting_rows(job,True,True)))
    cp=write(publication+'/collection.json',dict(schema=l.SCHEMA,task_key=key,application_accepted=True,no_refund=True,reserved_CPU_seconds=120))
    claims[key].update(job_id=job,authority_sha256=authority_sha,release_path=str(Path(rp['path']).parent),
        release_sha256=rp['sha256'],publication=str(Path(cp['path']).parent),created=world.now-200)
    accepted_reference.clear();accepted_reference.update(claim_key=key,job_id=job,release=rp,publication=cp,
        accounting=ap,worker_evidence=wp,parity_result=pp,parity_seal=sp,runtime_result=actual_runtime,
        source_hashes=OLD_ACCEPTED_SOURCES)


class ProtocolIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = time.time()
        self.resources = dict(cpus=1, memory_MiB=4096, cpu_seconds=1200, wall_seconds=1200)
        self.paid = dict(scope_id='r158_initial_recovery_20261028_03',
            expires_epoch=OLD03_END, claim_reserved_CPU=690, publication_reserved_CPU=30,
            no_refund=True, claims={OLD_FI_OP: dict(reserved_CPU=230, no_refund=True,
                parent_reserved_CPU=16, measured_parent_CPU=15.025331,
                parent_lifetime_CPU=8.502209, violations=[dict(reason='PARENT_CPU_CAP_EXCEEDED')]),
                OLD_DK2_OP: dict(reserved_CPU=230, no_refund=True, parent_reserved_CPU=56)})
        self.old_legacy = {
            OLD_FI_LEGACY: dict(task_key=OLD_FI_LEGACY, state='FAILED_RECONCILED',
                task=dict(study='FI'), reserved_CPU_seconds=1200, wall_seconds=1200,
                application_accepted=False, job_id=None, events=[dict(target='FAILED_RECONCILED')]),
            OLD_DK2_LEGACY: dict(task_key=OLD_DK2_LEGACY, state='FAILED_RECONCILED',
                task=dict(study='DK2'), reserved_CPU_seconds=1200, wall_seconds=1200,
                application_accepted=False, job_id='869420', events=[dict(target='FAILED_RECONCILED')])}
        self.legacy_state = dict(schema=cost.SCHEMA, owner=a.OWNER,
            claims=copy.deepcopy(self.old_legacy),
            spent_regions=dict(FI=OLD_FI_LEGACY, DK2=OLD_DK2_LEGACY))

    def write(self, relative, value):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        r.write(path, value)
        return dict(path=str(path), sha256=r.digest(path))

    def authority(self, study='DK2'):
        return dict(schema=a.AUTHORITY_SCHEMA, issuer=a.OWNER, controller=a.OWNER,
            purpose='COST_ONLY', study=study, role=study+'_COST_ONLY_BENCHMARK',
            plan_sha256='a'*64, executed_sources=a.executed_sources('COST_ONLY'),
            reference_numerical_environment=REFERENCE_NUMERICAL_ENV,
            automatic_retry=False, new_model_fits=0, official_origins=0, promotion=False,
            issued_epoch=self.now-1, calendar_expires_epoch=self.now+3500,
            max_queue_seconds=180, resources=self.resources,
            slurm_job_id='900004', node='node-13')

    def test_new_source_closure_cannot_be_the_old_accepted_TEST03_closure(self):
        current=a.executed_sources('CONTROL_TEST')
        self.assertEqual(set(current),set(OLD_ACCEPTED_SOURCES))
        self.assertNotEqual(current,OLD_ACCEPTED_SOURCES)
        for name in ('cost_control.py','operation_budget.py','lifecycle.py','admission.py','activation.py','benchmark.py'):
            self.assertNotEqual(current[name],OLD_ACCEPTED_SOURCES[name],name)

    def pair(self, state='AUTHORIZED', study='DK2'):
        key='new-r161-'+study
        root=self.root/('release-'+study); root.mkdir()
        release=dict(purpose='COST_ONLY',study=study,task_key=key,
            plan_sha256='a'*64,scientific_exclusion_key=study+'|retained-preparation',
            scope_id='r161_'+study.lower()+'_replacement_01',remote_root='/remote/'+key,
            policy_pin=dict(path='/policy.json',sha256='b'*64),resources=self.resources,
            source_hashes=a.executed_sources('COST_ONLY'),cost_replacement=dict(path='/replacement.json',sha256='c'*64))
        rp=self.write('release-'+study+'/release.json',release)
        claim=dict(task_key=key,task=dict(purpose='COST_ONLY',study=study,
            plan_sha256=release['plan_sha256'],scientific_exclusion_key=release['scientific_exclusion_key']),
            scope_id=release['scope_id'],state=state,release_path=str(root),release_sha256=rp['sha256'],
            remote_root=release['remote_root'],policy_pin=release['policy_pin'],resources=self.resources,
            config_sha256='d'*64,job_id='900004',legacy_cost_key='new-legacy-'+study,
            authority_sha256='e'*64,cost_replacement=release['cost_replacement'],events=[])
        # Retained legacy task shape has no operational-purpose field.
        legacy_task=dict(study=study,region=study,source='/canonical/preparation.py',
            preparation_sha256='f'*64,all_hosts=['hb.ucsc.edu','jerez','muscat'],
            plan_sha256=release['plan_sha256'],scientific_exclusion_key=release['scientific_exclusion_key'])
        legacy=dict(task_key=claim['legacy_cost_key'],task=legacy_task,
            state=state,scope_id=claim['scope_id'],release_path=claim['release_path'],
            release_sha256=claim['release_sha256'],remote_root=claim['remote_root'],
            config_sha256=claim['config_sha256'],job_id=claim['job_id'],
            authority_sha256=claim['authority_sha256'],reserved_CPU_seconds=1200,wall_seconds=1200,
            cost_replacement=claim['cost_replacement'],events=[])
        return claim,release,legacy

    def test_both_studies_require_role_and_original_finite_allocation_before_worker(self):
        for study in ('FI','DK2'):
            authority=self.authority(study)
            self.assertEqual(a.validate_authority(authority,'COST_ONLY','a'*64,
                authority['executed_sources'],self.now),self.resources)
            for change in ({'role':None},{'role':'TEST'},{'role':('FI' if study=='DK2' else 'DK2')+'_COST_ONLY_BENCHMARK'},
                    {'max_queue_seconds':181},{'resources':dict(self.resources,memory_MiB=8192)},
                    {'resources':dict(self.resources,cpu_seconds=1199)}):
                with self.subTest(study=study,change=change),self.assertRaises(a.ActivationError):
                    a.validate_authority(dict(authority,**change),'COST_ONLY','a'*64,
                        authority['executed_sources'],self.now)

    def test_benchmark_rejects_missing_role_before_activation_or_numerical_adapter(self):
        activation=self.write('activation.json',{})
        plan=dict(study='DK2',claim=dict(planned_attempt_id='new-scope',scientific_exclusion_key='DK2|prep'))
        authority=dict(self.authority(),scope_id='new-scope',scientific_exclusion_key='DK2|prep',full_prefix_admitted=False)
        with mock.patch.dict('os.environ',PRICEFM_ACTIVATION_PATH=activation['path'],PRICEFM_ACTIVATION_SHA256=activation['sha256']),\
                mock.patch.object(a,'validate_worker',side_effect=AssertionError('worker gate must not be reached')):
            for role in (None,'FI_COST_ONLY_BENCHMARK'):
                with self.subTest(role=role),self.assertRaises(bench.BenchmarkError):
                    bench.validate_authority(dict(authority,role=role),plan,'a'*64,{},self.now)

    def direct_activation_fixture(self,post_authority):
        claim,release,_=self.pair(state='SUBMITTED');root=Path(claim['release_path']);events=[]
        release['node']='node-13';release_pin=self.write('release-DK2/release.json',release)
        claim['release_sha256']=release_pin['sha256']
        authority=dict(self.authority(),issued_epoch=self.now-181,scope_id=release['scope_id'],
            task_key=claim['task_key'],release_sha256=release_pin['sha256'])
        authority_pin=self.write('release-DK2/authorization/authority.json',authority)
        claim.update(authority_sha256=authority_pin['sha256'],authority_identity_sha256=r.identity(authority))
        start=authority['issued_epoch']+179
        ready=dict(schema=a.READY_SCHEMA,authority_sha256=authority_pin['sha256'],
            authority_identity_sha256=r.identity(authority),node='node-13',plan_sha256=release['plan_sha256'],
            job_id=claim['job_id'],release_sha256=release_pin['sha256'],
            allocation=dict(job_id=claim['job_id'],node='node-13'),allocation_start_epoch=start,
            observed_epoch=self.now-1)
        claim['ready_pin']=self.write('ready.json',ready)
        proofs={name:dict(observed_epoch=authority['issued_epoch']+
            (-1 if post_authority is False or post_authority==name else 1),node='node-13')
            for name in ('handoff','hosts','site')}
        request={field:self.write('activation-proofs/'+name+'.json',proofs[name])
            for name,field in (('handoff','handoff_receipt'),('hosts','all_hosts_observation'),('site','site_admission'))}
        request_pin=self.write('activation-request.json',request)
        class Ledger:
            def transition(inner,key,expected,target,**fields):
                self.assertEqual(claim['state'],expected);events.append(target);claim.update(state=target,**fields)
                return copy.deepcopy(claim)
        def remote(config,argv):
            events.append('remote-activation-sha')
            return r.digest(root/'authorization/activation/packet.json')+' packet.json'
        stack=contextlib.ExitStack();self.addCleanup(stack.close)
        for obj,key,value in ((l,'_bound_claim',lambda *args:(Ledger(),claim,release,{})),
                (l,'validate_request',lambda *args,**kwargs:proofs),
                (l,'transfer',lambda *args,**kwargs:events.append('transfer-activation')),
                (l,'remote',remote),(l.time,'time',lambda:self.now)):
            stack.enter_context(mock.patch.object(obj,key,value))
        return claim,release,authority,Path(authority_pin['path']),request_pin,events

    def test_direct_COST_activation_rejects_fresh_pre_authority_proof_before_intent(self):
        original_root=self.root
        for proof in ('handoff','hosts','site','authority-tamper'):
            self.root=original_root/proof;self.root.mkdir()
            claim,release,authority,path,request,events=self.direct_activation_fixture(
                True if proof=='authority-tamper' else proof)
            if proof=='authority-tamper':r.write(path,dict(authority,status='CHANGED_AFTER_SEAL'))
            original=path.read_bytes()
            with self.subTest(proof=proof),self.assertRaises(a.ActivationError):
                l.activate(claim['task_key'],'fake-site',request['path'])
            self.assertEqual(events,[]);self.assertEqual(claim['state'],'SUBMITTED')
            self.assertFalse((path.parent/'activation').exists());self.assertEqual(path.read_bytes(),original)
        self.root=original_root

    def test_post_authority_activation_after_queue_end_accepts_in_time_actual_start(self):
        claim,release,authority,path,request,events=self.direct_activation_fixture(True)
        original=path.read_bytes()
        self.assertEqual(self.now-authority['issued_epoch'],181)
        result=l.activate(claim['task_key'],'fake-site',request['path'])
        self.assertEqual(result['state'],'ACTIVATED')
        self.assertEqual(result['allocation_start_epoch']-authority['issued_epoch'],179)
        self.assertEqual(events,['ACTIVATION_INTENT','transfer-activation','remote-activation-sha','ACTIVATED'])
        self.assertEqual(path.read_bytes(),original)

    def test_COST_watch_grace_observes_late_READY_without_allowing_late_allocation_start(self):
        from pricefm_hb import metered_io
        claim,release,authority,path,request,events=self.direct_activation_fixture(True)
        authority['issued_epoch']=self.now-184;r.write(path,authority)
        claim.update(authority_sha256=r.digest(path),authority_identity_sha256=r.identity(authority))
        ready=dict(schema=a.READY_SCHEMA,authority_sha256=claim['authority_sha256'],
            authority_identity_sha256=claim['authority_identity_sha256'],node='node-13',
            plan_sha256=release['plan_sha256'],job_id=claim['job_id'],release_sha256=claim['release_sha256'],
            allocation=dict(job_id=claim['job_id'],node='node-13'),
            allocation_start_epoch=authority['issued_epoch']+179,observed_epoch=authority['issued_epoch']+183)
        valid_pin=self.write('valid-on-time-start-ready.json',ready)
        claim['ready_pin']=self.write('late-allocation-start-ready.json',dict(ready,
            allocation_start_epoch=authority['issued_epoch']+181))
        with self.assertRaises(a.ActivationError):l.activate(claim['task_key'],'fake-site',request['path'])
        self.assertEqual(events,[]);self.assertFalse((path.parent/'activation').exists())
        claim['ready_pin']=valid_pin
        request_value=r.read(request['path'])
        with self.assertRaises(a.ActivationError):l._cost_proof_fresh(request_value,authority,release,now=self.now)
        l._cost_proof_fresh(request_value,authority,release,now=self.now,startup_observation=True)
        ledger=l._bound_claim(claim['task_key'],'fake-site')[0]
        ledger.snapshot=lambda:{'claims':{claim['task_key']:copy.deepcopy(claim)}}
        ledger.update=lambda key,**fields:claim.update(fields)
        config={'_r157_control_budget':object()}
        with mock.patch.object(l,'Ledger',return_value=ledger),\
                mock.patch.object(l,'_bound_claim',return_value=(ledger,claim,release,config)),\
                mock.patch.object(l,'finish_parent_contexts'),\
                mock.patch.object(metered_io,'watch',return_value=json.dumps(dict(event='READY',evidence=ready))) as watched:
            result=l.watch_and_activate(claim['task_key'],'fake-site',request['path'],self.root/'startup-grace')
        self.assertEqual(result['state'],'ACTIVATED');self.assertEqual(watched.call_count,1)
        expected=min(authority['issued_epoch']+180+30,authority['calendar_expires_epoch'])
        self.assertIn('deadline='+repr(expected),watched.call_args.args[1])
        self.assertLessEqual(watched.call_args.kwargs['timeout'],215)
        self.assertEqual(result['allocation_start_epoch']-authority['issued_epoch'],179)
        self.assertEqual(result['expires_epoch'],ready['allocation_start_epoch']+1200)

    def test_COST_worker_rejects_pre_authority_handoff_or_hosts_in_existing_staged_proofs(self):
        from pricefm_hb import handoff
        authority=dict(self.authority(),issued_epoch=self.now-110,release_sha256='b'*64,
            scientific_exclusion_key='DK2|private',proof_manifest={})
        allocation=dict(job_id=authority['slurm_job_id'],node='node-13');start=self.now-10
        def staged(name,value,manifest):
            pin=self.write('worker/proofs/'+name+'.json',value)
            manifest[pin['path']]=dict(relative_path='worker/proofs/'+name+'.json',sha256=pin['sha256'],bytes=Path(pin['path']).stat().st_size)
            return pin
        authority['policy_pin']=staged('policy',dict(execution_sources=[dict(path='/source/'+name,sha256=sha)
            for name,sha in authority['executed_sources'].items()]),authority['proof_manifest'])
        extra={};ready=staged('ready',dict(schema=a.READY_SCHEMA,job_id=allocation['job_id'],node='node-13',
            authority_identity_sha256=r.identity(authority),allocation=allocation,allocation_start_epoch=start,
            release_sha256='b'*64,observed_epoch=self.now-2),extra)
        activation=dict(schema=a.ACTIVATION_SCHEMA,status='ACTIVATED_ONCE',controller=a.OWNER,
            authority_identity_sha256=r.identity(authority),job_id=allocation['job_id'],node='node-13',
            plan_sha256='a'*64,observed_epoch=self.now-1,ready=ready,started_epoch=start,expires_epoch=start+1200,
            proof_manifest=extra)
        def observations(bad=None):
            closed=dict(observed_epoch=authority['issued_epoch']+(1 if bad!='handoff' else -1))
            hosts=dict(status='NO_OVERLAP',controller=a.OWNER,hosts=[a.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'],
                scientific_exclusion_key=authority['scientific_exclusion_key'],overlapping_scientific_claims=[],
                observed_epoch=authority['issued_epoch']+(1 if bad!='hosts' else -1))
            activation['handoff_receipt']=staged('handoff',closed,extra)
            activation['all_hosts_observation']=staged('hosts',hosts,extra)
        with mock.patch.object(a,'require_compute',return_value=allocation),\
                mock.patch.object(a,'allocation_start',return_value=start),mock.patch.object(a,'validate_qualification',return_value={}),\
                mock.patch.object(policy,'validate_policy'),mock.patch.object(handoff,'validate_handoff_receipt'),\
                mock.patch.object(a.time,'time',return_value=self.now),\
                mock.patch.dict('os.environ',dict(THREAD_ENV,**REFERENCE_NUMERICAL_ENV,PRICEFM_RELEASE_ROOT=str(self.root))):
            observations()
            self.assertEqual(a.validate_worker(authority,activation,allocation,'COST_ONLY','a'*64,
                authority['executed_sources'])['started_epoch'],start)
            for bad in ('handoff','hosts'):
                observations(bad)
                with self.subTest(proof=bad),self.assertRaises(a.ActivationError):
                    a.validate_worker(authority,activation,allocation,'COST_ONLY','a'*64,authority['executed_sources'])

    def test_new_permit_pointer_cannot_turn_accepted_old03_into_new17_qualification(self):
        claim,release,_=self.pair()
        old_release=dict(purpose='CONTROL_TEST',study='TEST',task_key='retained-test03',
            scope_id='r157_control_placement_03',source_hashes=OLD_ACCEPTED_SOURCES)
        old_pin=self.write('old03-release/release.json',old_release)
        old=dict(task_key='retained-test03',task=dict(purpose='CONTROL_TEST',study='TEST'),
            state='COLLECTED',application_accepted=True,job_id='869369',
            scope_id='r157_control_placement_03',created=self.now-4000,
            release_path=str(self.root/'old03-release'),release_sha256=old_pin['sha256'])
        state=dict(schema=l.SCHEMA,owner=a.OWNER,claims={old['task_key']:old},spent_tests=[old['task_key']])
        before=copy.deepcopy(state)
        with mock.patch.object(l,'verify_release',side_effect=AssertionError('never reinterpret historical03 with new code')):
            with self.assertRaises(a.ActivationError):l.select_cost_qualification(release,state,{'expires_epoch':self.now+3600})
        self.assertEqual(state,before)
        central=self.root/'canonical';central.mkdir();r.write(central/'activation_registry.json',state)
        original=(central/'activation_registry.json').read_bytes()
        with mock.patch.object(l,'owner'),mock.patch.object(l,'CENTRAL',central),\
                mock.patch.object(l,'policy_document',return_value={'expires_epoch':self.now+3600}),\
                mock.patch.object(l,'hb_concurrency',return_value=1):
            with self.assertRaises((ValueError,OSError)):l.Ledger().reserve(release,claim['release_path'],{})
        self.assertEqual((central/'activation_registry.json').read_bytes(),original)

    def test_authorized_self_pair_is_exact_and_preserves_paid_old_claims(self):
        claim,release,legacy=self.pair()
        before=copy.deepcopy((self.legacy_state,self.paid))
        self.assertEqual(adm.authorized_cost_pair(claim,release,legacy),legacy)
        for obj,field,value in ((claim,'state','HELD'),(legacy,'state','HELD'),(legacy,'job_id','869420'),
                (legacy,'authority_sha256','f'*64),(legacy,'reserved_CPU_seconds',0),
                (release,'cost_replacement',None)):
            changed=copy.deepcopy((claim,release,legacy));index=0 if obj is claim else 1 if obj is release else 2
            changed[index][field]=value
            with self.subTest(field=field,value=value),self.assertRaises(adm.AdmissionError):
                adm.authorized_cost_pair(*changed)
        self.assertEqual((self.legacy_state,self.paid),before)

    def test_worker_uses_staged_permit_and_never_traverses_controller_history(self):
        authority=self.authority()
        spec=dict(path='/controller/new04.control_cpu.json',authorization_pin=dict(path='/controller/new04.json',sha256='1'*64),scope_id='new04')
        policy_pin=dict(path='/controller/policy.json',sha256='2'*64)
        document=dict(protocol_version='r161_cost_replacement_v1',schema='r161_cost_replacement_authorization_v1',
            status='ROOT_ADMITTED_ONE_R161_COST_REPLACEMENT',controller=a.OWNER,study='DK2',
            created_epoch=self.now-10,expires_epoch=self.now+1000,new_scope_id='r161_DK2_replacement_01',
            new_plan_sha256='a'*64,new_operational_task_key='3'*64,new_legacy_task_key='4'*64,
            new_executed_sources=authority['executed_sources'],new_control_cpu_scope=spec,resource_policy=policy_pin,
            resources=self.resources,scientific_CPU_seconds=1200,scientific_wall_seconds=1200,
            control_CPU_reservation=230,priced_maximum_CPU=217,parent_CPU_cap=60,parent_lifetimes=7,
            parent_slice_CPU=8,operation_limits=ob.INITIAL_LIMITS,max_new_attempts=1,
            old_charges_refunded=False,old_clocks_mutated=False,automatic_retry=False,
            prior_legacy_snapshot=dict(path='/absent/old-ledger.json',sha256='5'*64))
        physical=self.write('proofs/replacement.json',document)
        pointer=dict(path='/unavailable/controller/replacement.json',sha256=physical['sha256'])
        authority.update(cost_replacement=pointer,protocol_version='r161_cost_replacement_v1',
            scope_id=document['new_scope_id'],task_key=document['new_operational_task_key'],
            control_cpu_scope=spec,policy_pin=policy_pin,calendar_expires_epoch=self.now+999)
        view=dict(proof_manifest={pointer['path']:dict(relative_path='proofs/replacement.json',
            sha256=physical['sha256'],bytes=Path(physical['path']).stat().st_size)})
        with mock.patch.dict('os.environ',PRICEFM_RELEASE_ROOT=str(self.root)):
            self.assertEqual(a.validate_replacement_worker(authority,view,self.now),document)
            for change in ({'calendar_expires_epoch':self.now+1001},{'task_key':OLD_DK2_OP},
                    {'resources':dict(self.resources,memory_MiB=8192)},
                    {'control_cpu_scope':dict(spec,scope_id='old03')}):
                with self.subTest(change=change),self.assertRaises((ValueError,OSError)):
                    a.validate_replacement_worker(dict(authority,**change),view,self.now)
            with self.assertRaises((ValueError,OSError)):
                a.validate_replacement_worker(authority,dict(proof_manifest={}),self.now)

    def test_segmented_factory_keeps_reservation_queue_and_mutation_order_then_stops(self):
        claim,release,legacy=self.pair(state='RESERVED')
        events=[]
        release.update(node='node-13',backend=None,release_id='r161-'+'1'*32)
        self.write('release-DK2/launch-request.json',{'private_fixture':True})
        self.write('release-DK2/plan.json',{'private_fixture':True})
        class OperationalLedger:
            def reserve(inner,*args):events.append('reserve-operational');return copy.deepcopy(claim)
            def update(inner,key,**fields):events.append('pair-legacy');claim.update(fields)
            def transition(inner,*args,**kwargs):raise AssertionError('phase1 cannot submit or transition')
        class LegacyLedger:
            def reserve(inner,*args,**kwargs):
                self.assertEqual(kwargs['replacement_pin'],release['cost_replacement'])
                events.append('reserve-legacy');return legacy
        def remote(config,argv):
            if argv[0]=='squeue':events.append('queue');return ''
            self.assertEqual(argv[0],'mkdir');events.append('mkdir');return ''
        def stage(config,release_path,value,reservation,ledger):
            self.assertEqual(claim['state'],'RESERVED');self.assertEqual(legacy['state'],'RESERVED')
            self.assertEqual(value,release);events.append('part1-only');return {'stopped_before_intent':True}
        with mock.patch.object(l,'owner'),mock.patch.object(l,'verify_release',return_value=release),\
                mock.patch.object(l,'validate_request'),mock.patch.object(l,'Ledger',return_value=OperationalLedger()),\
                mock.patch.object(cost,'Ledger',return_value=LegacyLedger()),\
                mock.patch.object(l.ctl,'config',return_value={'user':'fixture','remote_root':'/remote'}),\
                mock.patch.object(l,'bind_control',side_effect=lambda *args,**kwargs:events.append('reserve-control')),\
                mock.patch.object(l,'remote',side_effect=remote),\
                mock.patch.object(l,'transfer',side_effect=AssertionError('stock whole-release transfer must be replaced')):
            function=cost.replacement_submit_factory(stage)
            result=function(claim['release_path'],'fake-site')
        self.assertEqual(result,{'stopped_before_intent':True})
        self.assertEqual(events,['reserve-operational','reserve-control','queue','reserve-legacy',
            'pair-legacy','mkdir','mkdir','part1-only'])

    def phase2_fixture(self, *, debris=False, stale_after_hashes=False):
        """Tiny JSON stage, real generated hash scripts, fake scheduler only."""
        claim,release,legacy=self.pair(state='RESERVED')
        root=Path(claim['release_path']);events=[]
        for record in (claim,legacy):
            record.pop('job_id',None);record.pop('authority_sha256',None)
        release.update(remote_root=str(self.root/'private-remote'),node='node-13',
            release_id='r161-'+'1'*32,backend=None,files={})
        claim['remote_root']=legacy['remote_root']=release['remote_root']
        for index in range(4):
            member=self.write('release-DK2/metadata/member'+str(index)+'.json',{'index':index})
            relative='metadata/member'+str(index)+'.json'
            release['files'][relative]=dict(sha256=member['sha256'],bytes=Path(member['path']).stat().st_size)
        release_pin=self.write('release-DK2/release.json',release)
        claim['release_sha256']=legacy['release_sha256']=release_pin['sha256']
        claim['legacy_cost_key']=legacy['task_key']
        self.write('release-DK2/launch-request.json',{'private_metadata_request':True})
        config={'user':'private-fixture','remote_root':str(self.root)}
        claim['config_sha256']=legacy['config_sha256']=r.identity(config)
        phase1=self.root/'phase1';phase1.mkdir();output=self.root/'phase1-phase2'
        plan=cost.replacement_partition_manifest(release,release_pin['sha256'])
        parts=cost.replacement_make_partitions(root,release,plan,phase1/'partitions')
        remote_root=Path(release['remote_root']);shutil.copytree(parts[0],remote_root)
        if debris:
            (remote_root/'.~tmp~').mkdir();(remote_root/'.~tmp~/release.json').write_text('{}\n')
        fixture=self
        class PrivateLedger:
            def __init__(inner,path,value,name):inner.path=path;inner.value=value;inner.name=name;inner.persist()
            def persist(inner):r.write(inner.path,{'claims':{inner.value['task_key']:inner.value}})
            def snapshot(inner):return {'claims':{inner.value['task_key']:copy.deepcopy(inner.value)}}
            def reserve(inner,*args,**kwargs):raise AssertionError('phase2 must never reserve again')
            def transition(inner,key,expected,target,**fields):
                fixture.assertEqual(key,inner.value['task_key']);fixture.assertEqual(inner.value['state'],expected)
                events.append(inner.name+'-'+target);inner.value['events'].append(dict(target=target))
                inner.value.update(state=target,**fields);inner.persist();return copy.deepcopy(inner.value)
        operational=PrivateLedger(self.root/'private-op.json',claim,'operational')
        scientific=PrivateLedger(self.root/'private-legacy.json',legacy,'legacy')
        packet=dict(schema=cost.REPLACEMENT_STAGE_SCHEMA,status='PART1_COMPLETE_SAME_RESERVED_REPLACEMENT',
            release_pin=release_pin,cost_replacement=release['cost_replacement'],task_key=claim['task_key'],
            source_hashes=release['source_hashes'],config_identity=r.identity(config),partition_plan=plan,
            partitions_root=str(phase1/'partitions'),phase1_output=str(phase1),phase2_output=str(output),
            activation_pin=dict(path=str(operational.path),sha256=r.digest(operational.path)),
            legacy_pin=dict(path=str(scientific.path),sha256=r.digest(scientific.path)),
            operational_claim=copy.deepcopy(claim),legacy_claim=copy.deepcopy(legacy),
            part1_transfer_complete=True,old_charges_refunded=False)
        self.write('phase1/PHASE1_RESERVED.json',packet)
        packet_path=phase1/'PHASE1_RESERVED.json'
        funding=dict(counts=dict(transfer=1,metadata=3),violations=[],operation_limits=ob.INITIAL_LIMITS,
            reserved_CPU=230,parent_CPU_cap=60,priced_command_and_parent_maximum_CPU=217)
        class Budget:
            def snapshot(inner):return {'claims':{claim['task_key']:funding}}
        def bind(config,release):events.append('bind-control');config['_r157_control_budget']=Budget()
        def transfer(config,source,destination,**kwargs):
            self.assertTrue((output/'PHASE2_INTENT.json').exists());events.append('part2-transfer')
            self.assertEqual(Path(destination),remote_root);shutil.copytree(source,destination,dirs_exist_ok=True)
        def remote(config,argv):
            if argv[0]=='squeue':events.append('queue');return ''
            if argv[0]=='sbatch':
                self.assertEqual(claim['state'],'SUBMISSION_INTENT');self.assertEqual(legacy['state'],'SUBMISSION_INTENT')
                events.append('sbatch');return '900004'
            self.assertEqual(argv[:3],['/usr/bin/python3','-B','-c'])
            index=int(argv[3].split('index=')[1].split(';')[0]);events.append('hash-'+str(index))
            self.assertEqual((remote_root/'release.json').exists(),False)
            out=io.StringIO()
            with contextlib.redirect_stdout(out):exec(argv[3],{'__name__':'__main__'})
            self.assertEqual((remote_root/'release.json').exists(),index==3)
            return out.getvalue()
        def validate(*args,**kwargs):
            events.append('fresh-request')
            if stale_after_hashes and 'hash-3' in events:raise a.ActivationError('private request became stale')
        stack=contextlib.ExitStack();self.addCleanup(stack.close)
        for obj,key,value in ((l,'owner',lambda:None),(l,'Ledger',lambda:operational),(cost,'Ledger',lambda:scientific),
                (cost,'_replacement_stage_release',lambda *args:(root,release,config,{'operation_limits':ob.INITIAL_LIMITS})),
                (l,'bind_control',bind),(l,'transfer',transfer),(l,'remote',remote),(l,'validate_request',validate),
                (l,'verify_release',lambda path:release),(l,'finish_parent_contexts',lambda:events.append('finish-parent'))):
            stack.enter_context(mock.patch.object(obj,key,value))
        return packet_path,output,events,claim,legacy,remote_root

    def test_phase2_hashes_complete_membership_before_both_intents_and_rejects_replay(self):
        packet,output,events,claim,legacy,remote=self.phase2_fixture()
        result=cost.submit_replacement_part2(packet,'fake-site',output)
        self.assertEqual(result['state'],'HELD');self.assertEqual(legacy['state'],'HELD')
        self.assertTrue((remote/'release.json').is_file())
        for index in range(4):self.assertTrue((output/('stage-group-'+str(index)+'.json')).is_file())
        self.assertLess(events.index('hash-3'),events.index('operational-STAGED'))
        self.assertLess(events.index('legacy-SUBMISSION_INTENT'),events.index('sbatch'))
        self.assertEqual(events.count('part2-transfer'),1);self.assertEqual(events.count('sbatch'),1)
        before=list(events)
        for destination in (output,output.with_name('different-replay-output')):
            with self.assertRaises(ValueError):cost.submit_replacement_part2(packet,'fake-site',destination)
        self.assertEqual(events,before)

    def test_phase2_old_partial_member_fails_without_submission_or_cleanup(self):
        packet,output,events,claim,legacy,remote=self.phase2_fixture(debris=True)
        with self.assertRaisesRegex(ValueError,'unexpected or missing sealed staging membership'):
            cost.submit_replacement_part2(packet,'fake-site',output)
        self.assertEqual(claim['state'],'AMBIGUOUS');self.assertEqual(legacy['state'],'AMBIGUOUS')
        self.assertNotIn('sbatch',events);self.assertFalse((remote/'release.json').exists())
        self.assertTrue((remote/'.~tmp~/release.json').is_file())
        with self.assertRaises(ValueError):cost.submit_replacement_part2(packet,'fake-site',output.with_name('retry'))

    def test_phase2_rechecks_request_after_hashing_and_before_submission(self):
        packet,output,events,claim,legacy,remote=self.phase2_fixture(stale_after_hashes=True)
        with self.assertRaisesRegex(a.ActivationError,'became stale'):cost.submit_replacement_part2(packet,'fake-site',output)
        self.assertEqual(claim['state'],'AMBIGUOUS');self.assertEqual(legacy['state'],'AMBIGUOUS')
        self.assertNotIn('operational-STAGED',events);self.assertNotIn('sbatch',events)
        self.assertEqual(events.count('fresh-request'),2)

    def test_collection_routes_only_new_paid_legacy_claim_and_preserves_history(self):
        for accepted in (False,True):
            with self.subTest(accepted=accepted):
                claim,release,legacy=self.pair(state='SUBMITTED',study='FI' if accepted else 'DK2')
                state=copy.deepcopy(self.legacy_state);state['claims'][legacy['task_key']]=legacy
                state['replacement_spent_regions']={release['study']:legacy['task_key']}
                old=copy.deepcopy(state);paid=copy.deepcopy(self.paid);events=[]
                class LegacyLedger:
                    def snapshot(inner):return copy.deepcopy(state)
                    def transition(inner,key,expected,target,**fields):
                        self.assertEqual(key,legacy['task_key']);self.assertEqual(state['claims'][key]['state'],expected)
                        state['claims'][key].update(state=target,**fields);events.append(('legacy',key,target));return state['claims'][key]
                class OperationalLedger:
                    def transition(inner,key,expected,target,**fields):
                        self.assertEqual(key,claim['task_key']);events.append(('operational',key,target));return dict(claim,state=target,**fields)
                receipt=self.write(('ok' if accepted else 'bad')+'-accounting.json',dict(task_key=claim['task_key'],
                    job_id=claim['job_id'],release_sha256=claim['release_sha256'],checked=self.now,
                    squeue='',terminal=True,sacct_with_times='FAKE_METADATA'))
                def transfer(config,source,target,**kwargs):Path(target).mkdir(parents=True)
                dest=self.root/('publication-'+str(accepted));incoming=self.root/('incoming-'+str(accepted))
                with mock.patch.object(l,'_bound_claim',return_value=(OperationalLedger(),claim,release,{})),\
                        mock.patch.object(l,'parse_accounting',return_value=dict(terminal=True,complete=accepted,scope_violations=[])),\
                        mock.patch.object(l,'transfer',side_effect=transfer),mock.patch.object(l,'validate_outputs',return_value=True),\
                        mock.patch.object(l,'validate_cost_outputs',return_value=True),mock.patch.object(cost,'Ledger',return_value=LegacyLedger()):
                    result=l.collect(claim['task_key'],'fake-site',receipt['path'],incoming,dest)
                self.assertEqual(result['state'],'COLLECTED' if accepted else 'FAILED_RECONCILED')
                self.assertEqual(events,[('legacy',legacy['task_key'],'COLLECTED_COST_ONLY' if accepted else 'FAILED_RECONCILED'),
                    ('operational',claim['task_key'],'COLLECTED' if accepted else 'FAILED_RECONCILED')])
                self.assertEqual({key:state['claims'][key] for key in self.old_legacy},self.old_legacy)
                self.assertEqual(state['spent_regions'],old['spent_regions'])
                self.assertEqual(state['replacement_spent_regions'],old['replacement_spent_regions'])
                self.assertEqual(self.paid,paid)
                self.assertEqual(r.read(dest/'collection.json')['no_refund'],True)


class FullProtocolIntegrationTests(unittest.TestCase):
    """Exercise real qualification/funding/lineage gates in one private world."""
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        path=Path(__file__).with_name('r161_cost_replacement_test.py')
        spec=importlib.util.spec_from_file_location('r161_private_replacement_fixture',path)
        fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
        self.w=fixtures.build_replacement_fixture(Path(temp.name),
            qualification_augment=augment_complete_qualification_history,old_expires_epoch=OLD03_END)
        w=self.w
        for module,key,value in ((l,'owner',lambda:None),(cost,'owner',lambda:None),(ob,'owner',lambda:None),
                (l,'CENTRAL',w.central),(cost,'CENTRAL',w.central),(adm,'CENTRAL',w.central)):
            patch=mock.patch.object(module,key,value);patch.start();self.addCleanup(patch.stop)
        self.old_history=copy.deepcopy(w.old_operational_state)
        self.old_legacy=copy.deepcopy(w.legacy_state)
        self.old_control_bytes=Path(w.old_control_spec['path']).read_bytes()
        r.write(w.central/'activation_registry.json',w.old_operational_state)
        r.write(w.central/'cost_only_registry.json',w.legacy_state)
        self.q=dict(schema=l.REQUALIFICATION_SCHEMA,status='ROOT_ADMITTED_ONE_SOURCE_BOUND_REPLACEMENT_TEST',
            protocol_version='r161_cost_replacement_v1',controller=a.OWNER,scope_id='r161_control_placement_04',
            created_epoch=w.now-5,expires_epoch=w.now+3500,max_new_attempts=1,old_charges_refunded=False,
            new_executed_sources=w.sources,qualification_lineage=w.qualification_lineage_pin)
        qpin=w.write('new/TEST04/requalification.json',self.q)
        self.release04=dict(purpose='CONTROL_TEST',study='TEST',task_key=w.test_keys['04'],
            scope_id='r161_control_placement_04',source_hashes=w.sources,control_cpu_scope=w.control_spec,
            control_test_requalification=qpin,scientific_exclusion_key='TEST|unchanged-private-fixture',
            plan_sha256=w.plan_pins['FI']['sha256'],resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=120,wall_seconds=120),
            policy_pin=w.resource_policy_pin,remote_root='/private/test04-new-release',backend=None)
        self.release04_pin=w.write('new/TEST04/release.json',self.release04)
        self.release04_root=Path(self.release04_pin['path']).parent

    def accept_private04(self):
        """Simulate collected scientific output; validators for lineage stay real."""
        w=self.w;ledger=l.Ledger()
        ledger.reserve(self.release04,self.release04_root,{})
        state=ledger.snapshot();claim=state['claims'][w.test_keys['04']]
        claim.update(state='COLLECTED',application_accepted=True,job_id='900004')
        r.write(ledger.path,state)
        return state

    def cost_release(self,study):
        w=self.w
        release=dict(w.releases[study],policy_pin=w.resource_policy_pin,
            accepted_control_test=dict(claim_key=w.test_keys['04'],release=self.release04_pin),
            remote_root='/private/new-'+study,node='node-13',backend=None)
        pin=w.write('new/'+study+'/release.json',release)
        return release,Path(pin['path']).parent

    def assert_history_preserved(self):
        w=self.w;state=l.Ledger().snapshot();legacy=cost.Ledger().snapshot()
        self.assertEqual({k:state['claims'][k] for k in self.old_history['claims']},self.old_history['claims'])
        self.assertEqual({k:legacy['claims'][k] for k in self.old_legacy['claims']},self.old_legacy['claims'])
        self.assertEqual(legacy['spent_regions'],self.old_legacy['spent_regions'])
        self.assertEqual(Path(w.old_control_spec['path']).read_bytes(),self.old_control_bytes)
        self.assertEqual(w.paid_control['expires_epoch'],OLD03_END)
        paid=w.paid_control['claims'][w.old_keys['FI']['operational']]
        self.assertEqual(paid['parent_measured_CPU'],8.502209)
        self.assertTrue(any(v['reason']=='PARENT_CPU_CAP_EXCEEDED' for v in paid['violations']))

    def test_complete04_then_exact_new_reservation_append_without_old_refund(self):
        w=self.w
        # Real qualification parsing verifies the old runtime and all15 JSON rows;
        # the old expired control snapshot is read historically, never renewed.
        packet=a.read_pin(w.resource_policy_pin)
        l.validate_control_test_requalification(self.q,self.release04,self.old_history,now=w.now,packet=packet)
        state=self.accept_private04()
        self.assertEqual(state['spent_tests'],self.old_history['spent_tests']+[w.test_keys['04']])
        release,root=self.cost_release('FI')
        with mock.patch.object(l,'verify_release',side_effect=lambda path:
                self.release04 if Path(path)==self.release04_root else self.fail('only CURRENT TEST04 is verified')):
            operational=l.Ledger().reserve(release,root,{})
        legacy=cost.Ledger().reserve(w.plans['FI'],w.plan_pins['FI']['sha256'],operational['release_sha256'],
            operational['config_sha256'],root,release['remote_root'],replacement_pin=w.permit_pins['FI'])
        l.Ledger().update(operational['task_key'],legacy_cost_key=legacy['task_key'])
        self.assertEqual(cost.Ledger().snapshot()['replacement_spent_regions'],{'FI':legacy['task_key']})
        cost.validate_replacement(w.permit_pins['FI'],w.plans['FI'],w.plan_pins['FI']['sha256'],
            state=cost.Ledger().snapshot(),operational_state=l.Ledger().snapshot(),now=w.now,phase='own')
        expected='RESERVED'
        for target in ('STAGED','SUBMISSION_INTENT','HELD','AUTHORITY_INTENT','AUTHORIZED'):
            fields={'job_id':'900004'} if target=='HELD' else {'authority_sha256':'e'*64} if target=='AUTHORIZED' else {}
            l.Ledger().transition(operational['task_key'],expected,target,**fields)
            cost.Ledger().transition(legacy['task_key'],expected,target,**fields)
            expected=target
        authorized=l.Ledger().snapshot()['claims'][operational['task_key']]
        _,own,peers=adm.canonical_claims(packet,w.plan_pins['FI']['sha256'],
            release['scientific_exclusion_key'],self_claim=authorized)
        self.assertEqual(own,authorized);self.assertEqual(peers,[])
        snapshot=dict(slurm=dict(partition='State=UP MaxTime=1-00:00:00',
            self_job='JobId=900004 JobState=PENDING Reason=JobHeldUser ReqNodeList=node-13 NumCPUs=1 ReqTRES=cpu=1,mem=4096M',
            nodes='NodeName=node-13 Partitions=128x24 State=IDLE CPUTot=1 CPUEfctv=1 CPUAlloc=0 FreeMem=8192 RealMemory=8192 AllocMem=0'))
        selected=adm.select_node(snapshot,4096,1200,self_claim=own)
        self.assertEqual(selected['available_cpus'],1);self.assertFalse(selected['self_allocation_added_back'])
        snapshot['slurm']['nodes']=snapshot['slurm']['nodes'].replace('CPUAlloc=0','CPUAlloc=1')
        with self.assertRaises(adm.AdmissionError):adm.select_node(snapshot,4096,1200,self_claim=own)
        with self.assertRaises(ValueError):
            cost.Ledger().reserve(w.plans['FI'],w.plan_pins['FI']['sha256'],'a'*64,'b'*64,root,
                release['remote_root'],replacement_pin=w.permit_pins['FI'])
        self.assert_history_preserved()

    def test_new_permit_cannot_bypass04_or_hidden_active_owner_or_fifth_test(self):
        w=self.w;release,root=self.cost_release('FI')
        before=(w.central/'activation_registry.json').read_bytes()
        with self.assertRaises((ValueError,OSError)):l.Ledger().reserve(release,root,{})
        self.assertEqual((w.central/'activation_registry.json').read_bytes(),before)
        self.accept_private04();state=l.Ledger().snapshot()
        with self.assertRaises(ValueError):
            l.validate_control_test_requalification(self.q,self.release04,state,now=w.now,
                packet=a.read_pin(w.resource_policy_pin))
        for change in ('active','fifth','old-key','old-scope'):
            current=copy.deepcopy(state);permit=copy.deepcopy(w.permits['FI'])
            if change=='active':current['claims']['unknown-owner']={'state':'SUBMITTED'}
            if change=='fifth':current['spent_tests'].append('fifth-test')
            if change=='old-key':permit['new_operational_task_key']=w.old_keys['FI']['operational']
            if change=='old-scope':permit['new_scope_id']=w.old_plans['FI']['claim']['planned_attempt_id']
            pin=w.write('bad-'+change+'.json',permit)
            with self.subTest(change=change),self.assertRaises((ValueError,OSError)):
                cost.validate_replacement(pin,w.plans['FI'],w.plan_pins['FI']['sha256'],state=w.legacy_state,
                    operational_state=current,now=w.now)
        self.assert_history_preserved()

    def test_current04_missing_replacement_permit_rejects_before_operational_write(self):
        w=self.w;self.accept_private04();release,root=self.cost_release('FI')
        release.pop('cost_replacement');w.write('new/FI/release.json',release)
        paths=[w.central/'activation_registry.json',w.central/'cost_only_registry.json',
            Path(w.control_spec['path']),Path(w.old_control_spec['path'])]
        before={path:path.read_bytes() for path in paths}
        with mock.patch.object(l,'verify_release',side_effect=lambda path:
                self.release04 if Path(path)==self.release04_root else self.fail('only CURRENT TEST04 is verified')):
            with self.assertRaises(a.ActivationError):l.Ledger().reserve(release,root,{})
        self.assertEqual({path:path.read_bytes() for path in paths},before)
        self.assert_history_preserved()

    def test_new_finite_scope_has_exact_three_roles_and_no_fifth_or_forged_lineage(self):
        w=self.w;budget=ob.OperationBudget(w.control_spec['path'])
        for study in ('FI','DK2'):
            budget.reserve_claim(w.new_op_keys[study],purpose='COST_ONLY',study=study,
                scope_id=w.plans[study]['claim']['planned_attempt_id'],now=w.now)
        budget.reserve_publication(now=w.now)
        state=budget.snapshot(w.now)
        self.assertEqual(state['claim_reserved_CPU'],690)
        self.assertEqual(state['publication_reserved_CPU'],30)
        self.assertEqual(state['CPU_ceiling'],720)
        with self.assertRaises(ob.BudgetError):
            budget.reserve_claim('unadmitted-fourth-role',purpose='CONTROL_TEST',study='TEST',
                scope_id='r161_control_placement_05',now=w.now)
        with self.assertRaises(ob.BudgetError):budget.reserve_publication(now=w.now)
        forged=dict(w.authorization,qualification_lineage=w.write('forged-lineage.json',
            {'protocol_version':'r161_cost_replacement_v1'}))
        with self.assertRaises(ob.BudgetError):ob.recovery_claims(forged)
        self.assert_history_preserved()

    def test_overlap_exception_is_exact_paid_predecessor_and_rejects_unknown_queue(self):
        w=self.w;current=self.accept_private04();packet=a.read_pin(w.resource_policy_pin)
        snapshots={host:dict(matching_processes=[],unreadable_own_processes=[],registries=[],
            slurm=dict(queue='')) for host in (a.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu')}
        snapshots[a.OWNER]['registries']=[dict(path=str(w.central/'cost_only_registry.json'),
            present=True,value=copy.deepcopy(w.legacy_state))]
        args=(w.plans['FI'],'FI',snapshots,{}, {},None,[],packet)
        with self.assertRaises(adm.AdmissionError):adm._overlap(*args)
        self.assertEqual(adm._overlap(*args,cost_replacement=w.permit_pins['FI'],
            plan_sha=w.plan_pins['FI']['sha256'],operational_state=current),[])
        snapshots['hb.ucsc.edu']['slurm']['queue']='777777|RUNNING|unknown-node'
        with self.assertRaisesRegex(adm.AdmissionError,'unknown_HB_job'):
            adm._overlap(*args,cost_replacement=w.permit_pins['FI'],
                plan_sha=w.plan_pins['FI']['sha256'],operational_state=current)
        self.assert_history_preserved()


if __name__=='__main__':unittest.main()
