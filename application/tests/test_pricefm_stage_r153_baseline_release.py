"""Finite baseline authority/release tests; no real process or service actions."""
from pathlib import Path
from copy import deepcopy
from types import SimpleNamespace
import contextlib
import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import time
import unittest
from unittest.mock import Mock,patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/514_release_pricefm_stage_r153_control_repair.py'
spec=importlib.util.spec_from_file_location('r153_baseline_release_test',ENTRY)
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,sort_keys=True)+'\n')


def source():
    return dict(root=str(r.ROOT),branch=r.BRANCH,head='a'*40,
        runtime_sha256={str(p.relative_to(r.ROOT)):'e'*64 for p in r.runtime_entries()})


def probe_record(src=None,status='PASS_R153_PRIVATE_R_LIFECYCLE_PROBE',charge=35.):
    return dict(status=status,execution_source=src or source(),control_charged_CPU_seconds=charge,
        new_fits=0,production_service_actions=0,cleanup_verified=True,cleanup_errors=[],
        package_cwd_observed=True,launch_cwd_restored=True,unapproved_cwd_rejected=True,
        actual_process_checks=4,private_control_unit={'status':'PASS_R153_PRIVATE_CONTROL_UNIT_PROBE'})


class ProbeHistoryTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.root=Path(self.t.name);self.src=source()
    def record(self,name,**kwargs):
        path=self.root/name;write(path,probe_record(self.src,**kwargs));return path
    def test_latest_nonvacuous_probe_passes(self):
        p=self.record('pass.json');rows=r.validate_probes([p],self.src)
        self.assertEqual(rows[0]['control_CPU_seconds'],35.);self.assertEqual(rows[0]['sha256'],r.digest(p))
    def test_failed_prior_probe_charge_remains(self):
        a=self.record('failed.json',status='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE',charge=44.)
        b=self.record('pass.json',charge=37.)
        rows=r.validate_probes([a,b],self.src)
        self.assertEqual(sum(row['control_CPU_seconds'] for row in rows),81.)
        self.assertEqual(rows[0]['status'],'FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE')
    def test_old_committed_failed_probe_requires_ancestor_and_exact_bytes(self):
        old=deepcopy(self.src);old['head']='b'*40;data=b'old committed execution bytes'
        old['runtime_sha256']={k:hashlib.sha256(data).hexdigest() for k in old['runtime_sha256']}
        a=self.root/'old.json';write(a,probe_record(old,status='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE',charge=29.))
        b=self.record('pass.json')
        with patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as run,patch.object(r.subprocess,'check_output',return_value=data) as show:
            rows=r.validate_probes([a,b],self.src)
        self.assertEqual(rows[0]['control_CPU_seconds'],29.);self.assertEqual(show.call_count,len(r.runtime_entries()))
        self.assertIn('merge-base',run.call_args.args[0])
    def test_old_source_with_wrong_bytes_rejected(self):
        old=deepcopy(self.src);old['head']='b'*40;a=self.root/'old.json';write(a,probe_record(old))
        b=self.record('pass.json')
        with patch.object(r.subprocess,'run'),patch.object(r.subprocess,'check_output',return_value=b'changed'):
            with self.assertRaisesRegex(RuntimeError,'executable hash'):r.validate_probes([a,b],self.src)
    def test_last_failed_probe_is_not_release_proof(self):
        p=self.record('failed.json',status='FAILED_R153_PRIVATE_R_LIFECYCLE_PROBE')
        with self.assertRaisesRegex(RuntimeError,'non-vacuous'):r.validate_probes([p],self.src)
    def test_latest_must_match_current_source(self):
        p=self.record('pass.json');v=r.read(p);v['execution_source']['head']='c'*40;write(p,v)
        with self.assertRaisesRegex(RuntimeError,'current execution source'):r.validate_probes([p],self.src)
    def test_vacuous_or_missing_private_proofs_rejected(self):
        for key,value in [('package_cwd_observed',False),('launch_cwd_restored',False),
                ('unapproved_cwd_rejected',False),('actual_process_checks',2),('private_control_unit',{})]:
            p=self.record('pass.json');v=r.read(p);v[key]=value;write(p,v)
            with self.subTest(key=key),self.assertRaises(RuntimeError):r.validate_probes([p],self.src)
    def test_bad_charge_or_cleanup_rejected(self):
        for key,value in [('control_charged_CPU_seconds',0),('control_charged_CPU_seconds',True),
                ('control_charged_CPU_seconds',float('nan')),('cleanup_verified',False),
                ('cleanup_errors',['unresolved']),('new_fits',1),('production_service_actions',1)]:
            p=self.record('pass.json');v=r.read(p);v[key]=value;write(p,v)
            with self.subTest(key=key,value=value),self.assertRaises(RuntimeError):r.validate_probes([p],self.src)
    def test_duplicate_receipt_rejected(self):
        p=self.record('pass.json')
        with self.assertRaisesRegex(RuntimeError,'duplicate'):r.validate_probes([p,p],self.src)
    def test_no_probe_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'proof required'):r.validate_probes([],self.src)


class ImmutableEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.root=Path(self.t.name)
    def test_identical_immutable_publication_is_idempotent(self):
        path=self.root/'proof.json';r.immutable_bytes(path,b'proof');r.immutable_bytes(path,b'proof');self.assertEqual(path.read_bytes(),b'proof')
    def test_conflicting_immutable_publication_rejected(self):
        path=self.root/'proof.json';r.immutable_bytes(path,b'proof')
        with self.assertRaises(RuntimeError):r.immutable_bytes(path,b'replacement')
        self.assertEqual(path.read_bytes(),b'proof')
    def test_symlink_immutable_target_rejected(self):
        target=self.root/'target';target.write_text('proof');path=self.root/'proof';path.symlink_to(target)
        with self.assertRaises(RuntimeError):r.immutable_bytes(path,b'proof')


class FakeSystem:
    def __init__(self,units=None,processes=None,members=None):
        self.units=units or {};self.processes=processes or {};self.groups=members or {};self.member_reads=[]
    def unit(self,name):return deepcopy(self.units.get(name,dict(MainPID='0',ActiveState='inactive')))
    def process(self,pid):return deepcopy(self.processes.get(pid))
    def members(self,group):self.member_reads.append(group);return list(self.groups.get(group,[]))


class PredecessorTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.root=Path(self.t.name)
        self.legacy=self.root/'legacy';self.runtime=self.root/'new';self.pointer=self.legacy/'baseline/explicit_successor.json'
        write(self.legacy/'baseline/state.json',dict(phase='blocked',scope_id='scope',master_sha256='m',config_path=str(self.root/'config.json'),new_unit='old3.service'))
        self.epoch=dict(phase='blocked',generation=3,owner=dict(pid=31,start_ticks=1,boot_id='boot',cgroups=['/service/old3.service']),guardian_unit='guard3.service')
        write(self.legacy/'baseline/resource_ownership_epoch.json',self.epoch)
        self.api=SimpleNamespace(master_context=Mock(return_value=(dict(scope_id='scope'),dict(sha256='m'))),
            core=lambda:SimpleNamespace(read_config=lambda p:dict(max_owner_generations=3),same_process=lambda a,b:bool(a) and a==b),
            closed_cached_scope=Mock(return_value=dict(immutable_sha256={str(i):'h' for i in range(75)})))
        self.patches=[patch.object(r,'LEGACY',self.legacy),patch.object(r,'POINTER',self.pointer),patch.object(r,'legacy',return_value=self.api)]
        for p in self.patches:p.start();self.addCleanup(p.stop)
    def test_exact_spent_predecessor_accepts_live_original_model_group(self):
        system=FakeSystem(members={'/service/original-model.service':[100,101]})
        proof=r.predecessor(system);self.assertEqual(proof['epoch']['generation'],3)
        self.assertNotIn('/service/original-model.service',system.member_reads)
        self.api.master_context.assert_called_once_with(allow_expired=True)
    def test_live_old_owner_rejected(self):
        system=FakeSystem(units={'old3.service':dict(MainPID='31',ActiveState='active')},processes={31:self.epoch['owner']})
        with self.assertRaisesRegex(RuntimeError,'owner is still live'):r.predecessor(system)
    def test_live_guardian_rejected(self):
        system=FakeSystem(units={'guard3.service':dict(MainPID='32',ActiveState='active')})
        with self.assertRaisesRegex(RuntimeError,'guardian is still live'):r.predecessor(system)
    def test_control_group_not_drained_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'control group'):r.predecessor(FakeSystem(members={'/service/old3.service':[31]}))
    def test_nonexhausted_generation_rejected(self):
        self.epoch['generation']=2;write(self.legacy/'baseline/resource_ownership_epoch.json',self.epoch)
        with self.assertRaisesRegex(RuntimeError,'exhausted'):r.predecessor(FakeSystem())
    def test_existing_explicit_successor_rejected(self):
        write(self.pointer,{'already':'claimed'})
        with self.assertRaisesRegex(RuntimeError,'already been registered'):r.predecessor(FakeSystem())


class AuthorityAndLaunchTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.root=Path(self.t.name)
        self.legacy=self.root/'legacy';self.shared=self.root/'new';self.runtime=self.shared/'baseline'
        self.authority=self.runtime/'authority.json';self.pointer=self.legacy/'baseline/explicit_successor.json'
        self.src=source();self.master=dict(scope_id='oldscope',start_epoch=100.,expires_epoch=200.)
        write(self.legacy/'master.json',self.master)
        for name in ['state','resource_ownership_epoch','blocked']:write(self.legacy/'baseline'/f'{name}.json',{'predecessor':name})
        config=self.legacy/'config.json';write(config,{'frozen':'numerical settings'})
        self.cachepins={str(i):'c' for i in range(75)};self.oldpins={str(self.legacy/'master.json'):r.digest(self.legacy/'master.json')}
        self.release=self.root/'release.json'
        write(self.release,dict(status='R153_BASELINE_ONLY_SOURCE_RELEASE',execution_source=self.src,
            explicit_additional_activation_limit=1,cumulative_owner_limit=4,cached_restart_authorized=False,
            normal_build_context={'isolated_fixture':'context verified separately'},
            frozen_legacy_sha256=self.oldpins,frozen_cached_sha256=self.cachepins,created_epoch=time.time()-1))
        self.proof=dict(master=self.master,master_identity=dict(sha256=r.digest(self.legacy/'master.json')),
            state=dict(config_path=str(config)),closed=dict(immutable_sha256=self.cachepins))
        self.probes=[dict(path=str(self.root/'probe.json'),sha256='p',status='PASS',control_CPU_seconds=10.)]
        self.owner=SimpleNamespace(validate_authority_shape=Mock(side_effect=lambda x:x),inspect_sessions=Mock(return_value={'sessions':'verified'}),inspect_owner=Mock(return_value={'healthy':True}))
        self.patches=[patch.object(r,'LEGACY',self.legacy),patch.object(r,'SHARED',self.shared),patch.object(r,'RUNTIME',self.runtime),
            patch.object(r,'AUTHORITY',self.authority),patch.object(r,'POINTER',self.pointer),patch.object(r,'source_identity',return_value=self.src),
            patch.object(r,'verify_source'),patch.object(r,'check_pins'),patch.object(r,'predecessor',return_value=self.proof),
            patch.object(r,'verify_normal_build_context'),
            patch.object(r,'validate_probes',return_value=self.probes),patch.object(r,'owner',return_value=self.owner)]
        for p in self.patches:p.start();self.addCleanup(p.stop)
    def prepared(self):return r.prepare(self.release,[self.root/'probe.json'],system=FakeSystem())
    def test_preparation_is_explicit_additional_not_legacy_reset(self):
        value=self.prepared();self.assertEqual(value['activation'],dict(legacy_generations_spent=3,explicit_additional_activation=1,activation_limit=1,cumulative_owner_count=4))
        self.assertFalse(value['cached_restart_authorized']);self.assertFalse(value['original_cached_clock_reset']);self.assertFalse(value['new_cached_allocation'])
        self.assertEqual(value['legacy_master']['start_epoch'],100.);self.assertEqual(value['legacy_master']['expires_epoch'],200.)
        self.assertEqual(value['grant']['prior_control_CPU_seconds'],10.)
        self.assertFalse((self.runtime/'activation_claim.json').exists())
        self.assertEqual(value['poll_seconds'],20)
        self.assertEqual(value['normal_build_context'],r.read(self.release)['normal_build_context'])
    def test_second_preparation_does_not_replenish_authority(self):
        self.prepared()
        with self.assertRaisesRegex(RuntimeError,'already prepared or spent'):self.prepared()
    def test_excess_private_probe_charge_rejected_before_claim(self):
        self.probes[0]['control_CPU_seconds']=601.
        with self.assertRaisesRegex(RuntimeError,'finite control allowance'):self.prepared()
        self.assertFalse(self.authority.exists());self.assertFalse((self.runtime/'activation_claim.json').exists())
    def test_valid_authority_revalidates_original_clock_and_probe_history(self):
        expected=self.prepared();actual=r.validate_authority(self.authority,system=FakeSystem(),require_unclaimed=True)
        self.assertEqual(actual,expected)
    def test_namespace_cached_scope_and_counter_mutations_rejected(self):
        value=self.prepared()
        for key,new in [('runtime',str(self.root/'other')),('new_unit','unreviewed.service'),('cached_restart_authorized',True),
                ('original_cached_clock_reset',True),('new_cached_allocation',True)]:
            changed=deepcopy(value);changed[key]=new;write(self.authority,changed)
            with self.subTest(key=key),self.assertRaises(RuntimeError):r.validate_authority(self.authority,system=FakeSystem())
        write(self.authority,value)
    def test_old_master_clock_mutation_rejected(self):
        self.prepared();self.master['start_epoch']=101.;write(self.legacy/'master.json',self.master)
        with self.assertRaisesRegex(RuntimeError,'master identity/clock'):r.validate_authority(self.authority,system=FakeSystem())
    def test_probe_debit_cannot_be_refunded(self):
        value=self.prepared();value['grant']['prior_control_CPU_seconds']=0;write(self.authority,value)
        with self.assertRaisesRegex(RuntimeError,'proof charges'):r.validate_authority(self.authority,system=FakeSystem())
    def test_declared_intent_cannot_relax_restart(self):
        value=self.prepared();value['control_intent']['Restart']='on-failure';write(self.authority,value)
        with self.assertRaisesRegex(RuntimeError,'unit/entry intent'):r.validate_authority(self.authority,system=FakeSystem())
    def test_spent_activation_rejected_by_real_validator(self):
        self.prepared();write(self.runtime/'activation_claim.json',{'spent':True})
        with self.assertRaisesRegex(RuntimeError,'already consumed'):r.validate_authority(self.authority,system=FakeSystem(),require_unclaimed=True)
    def test_stale_staging_consumes_no_activation(self):
        value=self.prepared();value['grant']['starts_epoch']=time.time()-301
        with patch.object(r,'validate_authority',return_value=value),patch.object(r,'start_control') as start:
            with self.assertRaisesRegex(RuntimeError,'handoff is too old'):r.launch(self.authority,system=FakeSystem())
        self.assertFalse((self.runtime/'activation_claim.json').exists());start.assert_not_called()
    def test_start_failure_spends_one_activation_and_never_retries(self):
        value=self.prepared()
        def validate(path,system=None,require_unclaimed=False):
            if require_unclaimed and (self.runtime/'activation_claim.json').exists():raise RuntimeError('single activation already consumed')
            return value
        with patch.object(r,'validate_authority',side_effect=validate),patch.object(r,'start_control',side_effect=RuntimeError('launch failed')) as start:
            with self.assertRaisesRegex(RuntimeError,'launch failed'):r.launch(self.authority,system=FakeSystem())
            with self.assertRaisesRegex(RuntimeError,'already consumed'):r.launch(self.authority,system=FakeSystem())
        self.assertEqual(start.call_count,1)
        self.assertTrue(r.read(self.runtime/'activation_failed.json')['activation_spent'])
        self.assertEqual(r.read(self.runtime/'activation_claim.json')['activation']['activation_limit'],1)
        self.assertFalse(self.pointer.exists())
    def test_second_start_failure_cleans_only_declared_control_unit(self):
        value=self.prepared();system=FakeSystem(units={value['new_unit']:dict(KillMode='process',ExecStart=str(r.OWNER))})
        with patch.object(r,'validate_authority',return_value=value),patch.object(r,'start_control',side_effect=[None,RuntimeError('guardian start failed')]),patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as stop:
            with self.assertRaisesRegex(RuntimeError,'guardian start failed'):r.launch(self.authority,system=system)
        self.assertEqual(stop.call_count,1);self.assertEqual(stop.call_args.args[0],['systemctl','--user','stop',value['new_unit']])
        self.assertEqual(r.read(self.runtime/'activation_failed.json')['numerical_worker_signals'],0)
    def test_unattested_killmode_is_not_stopped(self):
        value=self.prepared();system=FakeSystem(units={value['new_unit']:dict(KillMode='control-group',ExecStart=str(r.OWNER))})
        with patch.object(r,'validate_authority',return_value=value),patch.object(r,'start_control',side_effect=[None,RuntimeError('failure')]),patch.object(r.subprocess,'run') as stop:
            with self.assertRaises(RuntimeError):r.launch(self.authority,system=system)
        stop.assert_not_called();self.assertFalse(r.read(self.runtime/'activation_failed.json')['control_cleanup'][0]['stopped'])
    def test_healthy_activation_publishes_only_explicit_legacy_registry(self):
        value=self.prepared();before={str(p):r.digest(p) for p in self.legacy.rglob('*') if p.is_file()}
        capsule=dict(process={'pid':101},unit_properties={'InvocationID':'private'})
        with patch.object(r,'validate_authority',return_value=value),patch.object(r,'start_control') as start,patch.object(r,'attest',return_value=capsule):
            result=r.launch(self.authority,system=FakeSystem())
        self.assertTrue(result['healthy']);self.assertEqual(start.call_count,2)
        pointer=r.read(self.pointer)
        self.assertEqual(pointer['cumulative_owner_count'],4);self.assertEqual(pointer['legacy_generations_spent'],3)
        self.assertFalse(pointer['cached_restart_authorized'])
        self.assertEqual(pointer['authority_sha256'],r.digest(self.authority))
        self.assertTrue((self.runtime/'activation_verified.json').exists())
        self.assertTrue(all(r.digest(Path(path))==wanted for path,wanted in before.items()))
        added={str(p) for p in self.legacy.rglob('*') if p.is_file()}-set(before)
        self.assertEqual(added,{str(self.pointer)})
    def test_unhealthy_activation_never_publishes_registry_or_refunds_claim(self):
        value=self.prepared();capsule=dict(process={'pid':101},unit_properties={'InvocationID':'private'})
        system=FakeSystem(units={u:dict(KillMode='process',ExecStart=str(r.OWNER)) for u in [value['new_unit'],value['guardian_unit']]})
        with patch.object(r,'validate_authority',return_value=value),patch.object(r,'start_control'),patch.object(r,'attest',return_value=capsule),patch.object(r.time,'monotonic',side_effect=[0,61]),patch.object(r.subprocess,'run',return_value=subprocess.CompletedProcess([],0)):
            with self.assertRaisesRegex(RuntimeError,'did not become healthy'):r.launch(self.authority,system=system)
        self.assertFalse(self.pointer.exists());self.assertTrue((self.runtime/'activation_claim.json').exists())
        self.assertTrue(r.read(self.runtime/'activation_failed.json')['activation_spent'])


class NormalBuildContextTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.root=Path(self.t.name)
        self.package=self.root/'normal';(self.package/'src').mkdir(parents=True)
        (self.package/'DESCRIPTION').write_text('Package: normal\n')
        self.input=self.package/'src/model.cpp';self.input.write_text('int value = 1;\n')
        self.header=self.package/'src/Makevars';self.header.write_text('PKG_CPPFLAGS=\n')
        self.dll=self.package/'src/normal.so';self.dll.write_bytes(b'frozen binary')
        os.utime(self.input,ns=(100,100));os.utime(self.header,ns=(100,100));os.utime(self.dll,ns=(200,200))
        libs=[]
        for name in ('pkgbuild','pkgload'):
            folder=self.root/name;(folder/'R').mkdir(parents=True)
            (folder/'DESCRIPTION').write_text('Package: '+name+'\n')
            (folder/'NAMESPACE').write_text('exportPattern(".")\n')
            (folder/'R'/name).write_bytes(b'frozen namespace');libs.append(str(folder))
        self.proof=self.root/'proof.json';inputs=r.build_paths(self.package)
        value=dict(status='PASS_PINNED_NORMAL_PACKAGE_ALREADY_BUILT',needs_compile=False,
            nanosecond_predicate_false=True,compile_called=False,load_all_called=False,posterior_fits=0,
            canonical_runtime_writes=0,package_path=str(self.package),predicate_input_paths=inputs,
            predicate_input_records={p:r.build_record(p) for p in inputs},
            DESCRIPTION=r.build_record(self.package/'DESCRIPTION'),dll=r.build_record(self.dll),
            pkgbuild_namespace=libs[0],pkgload_namespace=libs[1])
        write(self.proof,value)
        self.namespace_proof=self.proof.with_name('NORMAL_PACKAGE_BUILD_NAMESPACE_PINS.json')
        namespace_paths=[path for folder in libs for path in
            [Path(folder)/'DESCRIPTION',Path(folder)/'NAMESPACE',*sorted((Path(folder)/'R').glob('*'))]]
        write(self.namespace_proof,dict(status='PASS_INSTALLED_BUILD_PREDICATE_NAMESPACE_PINS',
            build_preflight_sha256=r.digest(self.proof),namespace_code_records={str(p):r.build_record(p) for p in namespace_paths}))
        self.context=r.normal_build_context(self.proof)
    def test_exact_context_full_and_metadata_checks_pass(self):
        self.assertTrue(r.verify_normal_build_context(self.context))
        self.assertTrue(r.verify_normal_build_context(self.context,metadata_only=True))
    def test_scope_cannot_authorize_compilation_or_helper_role(self):
        for key in ('no_compilation_permitted','no_build_helper_role_authorized'):
            value=deepcopy(self.context);value[key]=False
            with self.subTest(key=key),self.assertRaises(RuntimeError):r.verify_normal_build_context(value)
    def test_changed_discovery_inventory_rejected(self):
        (self.package/'src/new.cpp').write_text('new input')
        with self.assertRaisesRegex(RuntimeError,'discovery inventory'):r.verify_normal_build_context(self.context)
    def test_metadata_only_still_rejects_replaced_source_or_library(self):
        for path in (self.input,Path(next(iter(self.context['namespace_records'])))):
            before=path.read_bytes();path.write_bytes(before+b'changed')
            with self.subTest(path=path),self.assertRaisesRegex(RuntimeError,'bytes or metadata'):
                r.verify_normal_build_context(self.context,metadata_only=True)
            path.write_bytes(before)
    def test_proof_mutation_rejected(self):
        self.proof.write_text(self.proof.read_text()+' ')
        with self.assertRaisesRegex(RuntimeError,'context or discovery'):r.verify_normal_build_context(self.context)
    def test_namespace_proof_mutation_or_inventory_change_rejected(self):
        self.namespace_proof.write_text(self.namespace_proof.read_text()+' ')
        with self.assertRaisesRegex(RuntimeError,'context or discovery'):r.verify_normal_build_context(self.context)
        namespace=r.read(self.namespace_proof);namespace['namespace_code_records'].pop(next(iter(namespace['namespace_code_records'])))
        write(self.namespace_proof,namespace)
        with self.assertRaisesRegex(RuntimeError,'namespace file inventory'):r.normal_build_context(self.proof)
    def test_dot_hidden_build_sources_are_ignored_like_r_discovery(self):
        (self.package/'src/.hidden.cpp').write_text('ignored')
        hidden=self.package/'src/.hidden';hidden.mkdir();(hidden/'nested.cpp').write_text('ignored')
        self.assertEqual(r.build_paths(self.package),self.context['predicate_input_paths'])
    def test_symlink_build_input_is_not_a_new_helper_permission(self):
        target=self.root/'external.cpp';target.write_text('external')
        (self.package/'src/linked.cpp').symlink_to(target)
        with self.assertRaisesRegex(RuntimeError,'symlinked Normal build'):r.build_paths(self.package)
    def test_newer_input_forbids_hidden_compilation(self):
        os.utime(self.input,ns=(300,300));value=deepcopy(self.context)
        value['records'][str(self.input)]=r.build_record(self.input)
        with self.assertRaisesRegex(RuntimeError,'unadmitted compilation'):r.verify_normal_build_context(value)
    def test_extra_source_discovery_rejected(self):
        (self.package/'DESCRIPTION').write_text('Package: normal\nConfig/build/extra-sources: arbitrary\n')
        with self.assertRaisesRegex(RuntimeError,'extra-source'):r.build_paths(self.package)
    def test_changed_proof_cannot_claim_compilation_never_called(self):
        value=r.read(self.proof);value['compile_called']=True;write(self.proof,value)
        with self.assertRaisesRegex(RuntimeError,'read-only Normal'):r.normal_build_context(self.proof)


class AttestationTests(unittest.TestCase):
    def setUp(self):
        self.intent=r.intent('private-owner.service','run',Path('/tmp/authority.json'))
        self.proc=dict(pid=101,start_ticks=123,boot_id='boot',argv=self.intent['argv'],cwd=str(r.ROOT),cpus=list(range(30)))
        self.props=dict(MainPID='101',ActiveState='active',Restart='no',KillMode='process',WorkingDirectory=str(r.ROOT),InvocationID='invocation',ExecStart=str(r.OWNER),RuntimeMaxUSec='1w')
    def test_actual_declared_unit_passes(self):
        result=r.attest(self.intent,FakeSystem(units={self.intent['unit']:self.props},processes={101:self.proc}))
        self.assertEqual(result['process']['pid'],101);self.assertEqual(result['unit_properties']['InvocationID'],'invocation')
    def test_argv_cwd_CPU_and_unit_policy_mutations_rejected(self):
        changes=[('process','argv',['wrong']),('process','cwd','/tmp/wrong'),('process','cpus',[0]),
            ('unit','Restart','on-failure'),('unit','KillMode','control-group'),('unit','WorkingDirectory','/tmp/wrong'),
            ('unit','InvocationID',''),('unit','ExecStart','unrelated'),('unit','RuntimeMaxUSec','infinity')]
        for layer,key,new in changes:
            proc=deepcopy(self.proc);props=deepcopy(self.props);(proc if layer=='process' else props)[key]=new
            with self.subTest(layer=layer,key=key),self.assertRaises(RuntimeError):
                r.attest(self.intent,FakeSystem(units={self.intent['unit']:props},processes={101:proc}))
    def test_missing_PID_bounded_timeout(self):
        system=FakeSystem(units={self.intent['unit']:dict(MainPID='0',ActiveState='inactive')})
        with patch.object(r.time,'monotonic',side_effect=[0,2]):
            with self.assertRaisesRegex(RuntimeError,'timed out'):r.attest(self.intent,system,timeout=1)


if __name__=='__main__':unittest.main()
