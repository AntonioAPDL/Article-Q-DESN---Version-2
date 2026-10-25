"""Current registered runtime observation; hermetic reads, never real services."""
import ast
from copy import deepcopy
import csv
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock,patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/518_inspect_pricefm_stage_r153_runtime.py'
spec=importlib.util.spec_from_file_location('r153_runtime_observer_test',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,sort_keys=True)+'\n')


class System:
    def __init__(self):self.clock=1000.;self.units={};self.processes={};self.groups={}
    def unit(self,name):return deepcopy(self.units.get(name,dict(MainPID='0',ActiveState='inactive',ControlGroup='')))
    def process(self,pid):return deepcopy(self.processes.get(pid))
    def members(self,group):return list(self.groups.get(group,[]))
    def now(self):return self.clock


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.data=self.root/'data';self.source=self.root/'source'
        self.legacy=self.data/'legacy';self.shared=self.data/'r153';self.br=self.shared/'baseline'
        self.bp=self.legacy/'baseline/explicit_successor.json';self.ba=self.br/'authority.json'
        self.cr=self.shared/'cz';self.cc=self.cr/'single_activation_claim.json'
        for key,value in dict(DATA=self.data,ROOT=self.source,LEGACY=self.legacy,SHARED=self.shared,
                BASELINE_RUNTIME=self.br,BASELINE_POINTER=self.bp,BASELINE_AUTHORITY=self.ba,
                CZ_ROOT=self.cr,CZ_CLAIM=self.cc,FORBIDDEN_OUTPUT_ROOTS=(self.data,self.source)).items():
            obj=patch.object(m,key,value);obj.start();self.addCleanup(obj.stop)
        self.system=System();self.src=dict(root=str(self.source),branch='work/r153',head='a'*40)
        self.load=patch.object(m,'load_release').start();self.addCleanup(patch.stopall)
    def baseline(self,finished=False):
        authority=dict(execution_source=self.src)
        write(self.ba,authority)
        self.registration=dict(kind='EXPLICIT_R153_BASELINE_ONLY_SUCCESSOR',authority_path=str(self.ba),
            runtime=str(self.br),legacy_generations_spent=3,explicit_additional_activation=1,
            cumulative_owner_count=4,cached_restart_authorized=False,authority_sha256=m.digest(self.ba),source=self.src)
        write(self.bp,self.registration)
        proof=dict(healthy=True,phase='complete' if finished else 'running',tail_finished=finished,
            execution_source=self.src,cached_scope_closed=True)
        self.owner=SimpleNamespace(inspect_owner=Mock(return_value=proof))
        self.release=SimpleNamespace(AUTHORITY=self.ba,RUNTIME=self.br,
            validate_authority=Mock(return_value=authority),owner=Mock(return_value=self.owner))
        self.load.return_value=self.release
        return authority
    def cz(self):
        identity='b'*32;self.cp=self.cr/identity/'authority.json';self.runtime=self.cp.parent
        self.authority=dict(id=identity,runtime=str(self.runtime),execution_source=self.src,
            science_source=dict(root='/frozen/r144',branch='work/pricefm-r144-cz-training-fallback-20261020',
                head='f96fcb0e3dc47da236d656cda2f0e58fb537ee1f'),created_epoch=900.,expires_epoch=2000.,
            waiter_unit='wait.service',science_unit='science.service',effective_config_sha256='c'*64,
            waiter_control_cpu=29,budget_heartbeat_max_age_seconds=90,final_publication_CPU_reserve_seconds=90.,
            control_CPU_allowance_seconds=1800.,prior_control_CPU_charged_seconds=125.,
            effective_config=dict(tag='frozen_cz',fallback_candidate=dict(candidate_id='original')))
        write(self.cp,self.authority)
        self.global_claim=dict(claim=1,id=identity,authority_path=str(self.cp),authority_sha256=m.digest(self.cp),epoch=950.)
        write(self.cc,self.global_claim)
        self.api=SimpleNamespace(RUNTIME=self.cr,DATA=self.data,PYTHON=Path('/pinned/python'),
            ENTRY=Path('/pinned/515.py'),R144_ENTRY=Path('/frozen/486.py'),
            validate_authority=Mock(return_value=self.authority),
            old_waiter_drained=Mock(return_value=dict(drained=True)),
            exact_process=lambda a,b:bool(a) and all(a.get(k)==b.get(k) for k in ('pid','start_ticks','boot_id','cmdline_sha256','cwd')),
            same_lifetime=lambda a,b:bool(a) and all(a.get(k)==b.get(k) for k in ('pid','start_ticks','boot_id')),
            systemd_seconds=lambda value:int(value)/1e6,
            cpu_guard=Mock(side_effect=AssertionError('observer must not measure its own CPU')),
            observe_waiter_cpu=Mock(return_value=dict(status='VERIFIED_EXTERNAL_MEASURED_WAITER_CPU',
                observer_CPU_used=False,numerical_CPU_included=False,within_CPU=True,within_wall=True,
                charged_CPU_upper_bound_seconds=130.,basis='verified_owner_budget')),
            boundary_state=Mock(return_value=dict(ready=False,status='waiting')))
        self.load.return_value=SimpleNamespace(api=lambda:self.api)
    def capsule(self,role):
        unit=self.authority['waiter_unit' if role=='waiter' else 'science_unit'];pid=11 if role=='waiter' else 22
        group='/system.slice/'+unit
        process=dict(pid=pid,start_ticks=7,boot_id='boot',cmdline_sha256='d'*64,cwd=str(self.source),
            argv=m.cz_argv(self.api,self.authority,self.cp,role),cgroups=[group],cpus=[29])
        props=dict(Id=unit,MainPID=str(pid),ActiveState='active',InvocationID='invocation-'+role,
            ControlGroup=group,Restart='no',KillMode='process',CPUAccounting='yes',WorkingDirectory=str(self.source),
            RuntimeMaxUSec='1000000000')
        self.system.units[unit]=deepcopy(props);self.system.processes[pid]=deepcopy(process)
        return dict(unit=unit,process=process,properties=props,actual_entry=str(self.api.ENTRY),
            delegated_entry=str(self.api.R144_ENTRY) if role=='science' else None,
            execution_source=self.src,scientific_source=self.authority['science_source'],epoch=950.)
    def waiting(self):
        self.cz();cap=self.capsule('waiter')
        write(self.runtime/'activation.json',dict(activation=1,authority_sha256=m.digest(self.cp),capsule=cap))
        write(self.runtime/'launch_claim.json',dict(claim=1,unit=self.authority['waiter_unit'],
            authority_sha256=m.digest(self.cp),expected_control_source=self.src,
            expected_argv=m.cz_argv(self.api,self.authority,self.cp,'waiter'),expected_RuntimeMaxSec=1000))
        write(self.runtime/'progress.json',dict(epoch=990.,authority_sha256=m.digest(self.cp),scientific_dispatches=0))
        return cap
    def delegated(self):
        self.cz();cap=self.capsule('science')
        write(self.runtime/'science_claim.json',dict(claim=1,authority_sha256=m.digest(self.cp),
            claimed_epoch=990.,boundary=dict(ready=True,status='whole_queue_drained'),unit=self.authority['science_unit']))
        write(self.runtime/'scientific_activation.json',dict(activation=1,authority_sha256=m.digest(self.cp),
            effective_config_sha256=self.authority['effective_config_sha256'],capsule=cap))
        return cap
    def terminal(self):
        cap=self.delegated()
        result=dict(status='R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED',region='CZ',fallback_rank=3,
            fallback_candidate=self.authority['effective_config']['fallback_candidate'],
            source={k:self.authority['science_source'][k] for k in ('branch','head')},
            source_r141_head='4cd92ac3654f16a84a67c8db6cfc7f381113aeb9',test_used_for_selection=False,
            authority_mutated=False,article_mutated=False,promotion_decided=False,full_fits=24,official_origin_region_pairs=365)
        campaign=self.data/'campaigns/frozen_cz';write(campaign/'terminal.json',result)
        closeout=campaign/'closeout';closeout.mkdir()
        with (closeout/'fold_comparison.csv').open('w') as stream:
            writer=csv.DictWriter(stream,fieldnames=['region','fold','operator','AQL']);writer.writeheader()
            for fold in (1,2,3):
                for op in ('cdf_pool_clipped','mean_feature','path_specific','normal_driver'):
                    writer.writerow(dict(region='CZ',fold=fold,operator=op,AQL=.1))
        write(closeout/'completed_evidence.json',dict(metadata=dict(source=result['source']),
            artifacts={'fold_comparison.csv':m.digest(closeout/'fold_comparison.csv')}))
        write(self.runtime/'science_terminal.json',dict(result=result,actual_control_capsule=cap,authority_sha256=m.digest(self.cp)))
        self.system.processes.pop(cap['process']['pid'])
        self.system.units['science.service']=dict(MainPID='0',ActiveState='inactive',ControlGroup=cap['properties']['ControlGroup'])
        return cap,campaign,result
    def edit(self,path,key,value):
        record=json.loads(path.read_text());record[key]=value;write(path,record)
    def assert_failed(self,lane):
        result=m.observe(lane,self.system);self.assertFalse(result['healthy']);return result


class RegistrationTests(Fixture):
    def test_missing_lanes_do_not_import_any_api(self):
        for lane in ('baseline','cz'):
            value=m.observe(lane,self.system);self.assertFalse(value['healthy']);self.assertFalse(value['registered'])
        self.load.assert_not_called()
    def test_baseline_healthy_ignores_historical_generation_three(self):
        self.baseline();write(self.legacy/'baseline/state.json',dict(phase='blocked',generation=3))
        result=m.observe('baseline',self.system)
        self.assertTrue(result['healthy']);self.assertTrue(result['legacy_generation_three_is_historical'])
        self.load.assert_called_once_with('baseline');self.owner.inspect_owner.assert_called_once_with(self.ba,system=self.system)
        self.assertFalse(result['global_campaign_complete'])
    def test_baseline_finished_is_not_global_scientific_completion(self):
        self.baseline(finished=True);result=m.observe('baseline',self.system)
        self.assertTrue(result['healthy']);self.assertTrue(result['baseline_tail_finished'])
        self.assertFalse(result['scientific_complete']);self.assertEqual(result['phase'],'complete')
    def test_baseline_bad_registration_never_calls_api(self):
        self.baseline()
        for key,value in [('kind','legacy'),('authority_path',str(self.ba.parent/'other.json')),
                ('runtime','/wrong'),('legacy_generations_spent',2),('explicit_additional_activation',2),
                ('cumulative_owner_count',5),('cached_restart_authorized',True),('authority_sha256','0'*64)]:
            write(self.bp,dict(self.registration,**{key:value}));self.load.reset_mock()
            with self.subTest(key=key):self.assert_failed('baseline');self.load.assert_not_called()
    def test_baseline_source_or_closure_mismatch_rejected(self):
        self.baseline();self.edit(self.bp,'source',dict(self.src,head='f'*40));self.assert_failed('baseline')
        self.baseline();self.owner.inspect_owner.return_value['cached_scope_closed']=False;self.assert_failed('baseline')
    def test_baseline_api_namespace_mismatch_rejected(self):
        self.baseline();self.release.RUNTIME=self.br/'other';self.assert_failed('baseline');self.owner.inspect_owner.assert_not_called()
    def test_baseline_symlink_registration_or_authority_rejected(self):
        self.baseline();target=self.bp.with_name('saved.json');self.bp.rename(target);self.bp.symlink_to(target)
        self.assert_failed('baseline');self.load.assert_not_called()
        self.bp.unlink();self.baseline();target=self.ba.with_name('saved.json');self.ba.rename(target);self.ba.symlink_to(target)
        self.assert_failed('baseline');self.load.assert_not_called()
    def test_cz_invalid_global_claim_never_imports_api(self):
        self.cz()
        for key,value in [('claim',2),('id','a/../b'),('authority_path',str(self.cp.parent/'other.json')),('authority_sha256','0'*64)]:
            write(self.cc,dict(self.global_claim,**{key:value}));self.load.reset_mock()
            with self.subTest(key=key):self.assert_failed('cz');self.load.assert_not_called()
    def test_cz_source_runtime_mismatch_rejected(self):
        self.cz();self.authority['runtime']='/wrong';self.assert_failed('cz')
        self.authority['runtime']=str(self.runtime);self.authority['execution_source']=dict(self.src,root='/wrong');self.assert_failed('cz')
    def test_selected_cz_imports_only_cz(self):
        self.cz();result=m.observe('cz',self.system)
        self.assertFalse(result['healthy']);self.assertEqual(result['phase'],'activation_pending')
        self.load.assert_called_once_with('cz');self.api.validate_authority.assert_called_once_with(self.cp,system=self.system,allow_expired=True)


class WaitingTests(Fixture):
    def test_attested_waiting_is_healthy_but_incomplete(self):
        self.waiting();result=m.observe('cz',self.system)
        self.assertTrue(result['healthy']);self.assertEqual(result['phase'],'waiting')
        self.assertFalse(result['scientific_complete']);self.assertEqual(result['scientific_dispatches'],0)
        self.assertEqual(result['service_actions'],0)
        self.api.observe_waiter_cpu.assert_called_once_with(self.authority,self.cp,self.system,
            json.loads((self.runtime/'activation.json').read_text())['capsule'])
        self.api.cpu_guard.assert_not_called()
        self.assertEqual(result['budget']['basis'],'verified_owner_budget')
    def test_boundary_ready_still_does_not_claim_dispatch(self):
        self.waiting();self.api.boundary_state.return_value=dict(ready=True);result=m.observe('cz',self.system)
        self.assertTrue(result['healthy']);self.assertEqual(result['phase'],'boundary_ready');self.assertEqual(result['scientific_dispatches'],0)
    def test_waiting_progress_stale_future_or_authority_mismatch(self):
        self.waiting();p=self.runtime/'progress.json'
        for epoch,sha in [(800,m.digest(self.cp)),(1001,m.digest(self.cp)),(990,'bad')]:
            write(p,dict(epoch=epoch,authority_sha256=sha));self.assert_failed('cz')
    def test_waiting_bad_unit_process_or_source_rejected(self):
        self.waiting();original=deepcopy(self.system.units['wait.service'])
        for key,value in [('MainPID','33'),('InvocationID','wrong'),('InvocationID',''),('ControlGroup',''),
                ('Restart','always'),('KillMode','control-group'),('CPUAccounting','no'),('WorkingDirectory','/wrong'),('RuntimeMaxUSec','2000000000')]:
            self.system.units['wait.service']=dict(original,**{key:value})
            with self.subTest(key=key,value=value):self.assert_failed('cz')
        self.system.units['wait.service']=original;self.system.processes[11]['argv']=['forged'];self.assert_failed('cz')
    def test_waiting_launch_scope_or_activation_identity_rejected(self):
        self.waiting();p=self.runtime/'launch_claim.json';record=json.loads(p.read_text())
        for key,value in [('claim',2),('unit','wrong.service'),('expected_control_source',dict(self.src,head='f'*40)),('expected_RuntimeMaxSec',-1)]:
            write(p,dict(record,**{key:value}));self.assert_failed('cz')
        write(p,record);self.edit(self.runtime/'activation.json','authority_sha256','bad');self.assert_failed('cz')
    def test_old_waiter_not_drained_rejects_health(self):
        self.waiting();self.api.old_waiter_drained.return_value=dict(drained=False);self.assert_failed('cz')
    def test_cpu_guard_failure_rejects_health(self):
        self.waiting();self.api.observe_waiter_cpu.side_effect=RuntimeError('finite allowance spent');self.assert_failed('cz')
        self.api.cpu_guard.assert_not_called()
    def test_missing_or_exhausted_budget_proof_rejects_health(self):
        self.waiting()
        good=deepcopy(self.api.observe_waiter_cpu.return_value)
        for proof in (None,[],{},dict(good,within_CPU=False),dict(good,within_wall=False),
                dict(good,observer_CPU_used=True),dict(good,numerical_CPU_included=True),
                dict(good,charged_CPU_upper_bound_seconds=float('nan')),
                dict(good,charged_CPU_upper_bound_seconds=1711.),
                dict(good,charged_CPU_upper_bound_seconds=1800.)):
            self.api.observe_waiter_cpu.return_value=proof
            with self.subTest(proof=proof):self.assert_failed('cz')
    def test_expired_waiter_is_not_healthy_or_renewed(self):
        self.waiting();self.system.clock=2000.;result=self.assert_failed('cz')
        self.assertEqual(result['phase'],'expired');self.api.boundary_state.assert_not_called()
    def test_blocked_record_overrides_fresh_progress(self):
        self.waiting();write(self.runtime/'waiter_blocked.json',dict(error='finite control exhausted'))
        result=self.assert_failed('cz');self.assertEqual(result['phase'],'blocked');self.api.boundary_state.assert_not_called()


class DelegationAndTerminalTests(Fixture):
    def test_delegated_models_do_not_require_empty_slot_again(self):
        self.delegated();self.api.boundary_state.side_effect=AssertionError('own models occupy slot')
        result=m.observe('cz',self.system);self.assertTrue(result['healthy']);self.assertEqual(result['phase'],'delegated')
        self.assertEqual(result['scientific_dispatches'],1);self.assertFalse(result['scientific_complete'])
        self.api.boundary_state.assert_not_called();self.api.cpu_guard.assert_not_called()
    def test_accepted_science_can_outlive_waiter_allowance(self):
        self.delegated();self.system.clock=2500.;result=m.observe('cz',self.system)
        self.assertTrue(result['healthy']);self.assertTrue(result['waiter_grant_expired'])
    def test_unattested_dispatch_is_not_declared_healthy(self):
        self.delegated();(self.runtime/'scientific_activation.json').unlink();result=self.assert_failed('cz')
        self.assertEqual(result['phase'],'delegation_pending');self.assertEqual(result['scientific_dispatches'],1)
    def test_late_claim_wrong_config_and_replaced_process_rejected(self):
        self.delegated();p=self.runtime/'science_claim.json';self.edit(p,'claimed_epoch',2000.);self.assert_failed('cz')
        self.edit(p,'claimed_epoch',990.);self.edit(self.runtime/'scientific_activation.json','effective_config_sha256','bad');self.assert_failed('cz')
        self.edit(self.runtime/'scientific_activation.json','effective_config_sha256',self.authority['effective_config_sha256'])
        self.system.processes[22]['start_ticks']=8;self.assert_failed('cz')
    def test_complete_requires_original_protocol_surface_and_drain(self):
        self.terminal();self.system.clock=3000.;result=m.observe('cz',self.system)
        self.assertTrue(result['healthy']);self.assertTrue(result['scientific_complete']);self.assertEqual(result['phase'],'complete')
        self.api.boundary_state.assert_not_called()
    def test_terminal_status_alone_is_insufficient(self):
        self.delegated();write(self.runtime/'science_terminal.json',dict(result=dict(status='R144_CZ_FALLBACK_COMPLETE_NOT_PROMOTED')))
        self.assert_failed('cz')
    def test_live_recorded_lifetime_or_cgroup_blocks_completion(self):
        cap,_,_=self.terminal();self.system.processes[22]=deepcopy(cap['process']);self.assert_failed('cz')
        self.system.processes.clear();self.system.groups[cap['properties']['ControlGroup']]=[55];self.assert_failed('cz')
    def test_terminal_without_recorded_cgroup_or_lifetime_is_unproven(self):
        self.terminal();path=self.runtime/'science_terminal.json';original=json.loads(path.read_text())
        for field in ('properties','process'):
            value=deepcopy(original)
            if field=='properties':value['actual_control_capsule'][field]['ControlGroup']=''
            else:value['actual_control_capsule'][field].pop('boot_id')
            write(path,value);self.assert_failed('cz')
    def test_terminal_still_checks_original_waiter_drain(self):
        self.terminal();self.api.old_waiter_drained.return_value=dict(drained=False);self.assert_failed('cz')
    def test_terminal_changed_source_or_protocol_rejected(self):
        _,campaign,result=self.terminal();p=self.runtime/'science_terminal.json';value=json.loads(p.read_text())
        for key,bad in [('source',dict(branch='wrong',head='f'*40)),('full_fits',25),('official_origin_region_pairs',364),
                ('test_used_for_selection',True),('promotion_decided',True),('fallback_candidate',dict(candidate_id='new'))]:
            write(p,dict(value,result=dict(result,**{key:bad})))
            with self.subTest(key=key):self.assert_failed('cz')
    def test_terminal_payload_tamper_or_unsealed_fold_surface_rejected(self):
        _,campaign,_=self.terminal();closeout=campaign/'closeout';p=closeout/'fold_comparison.csv';p.write_text(p.read_text()+'CZ,4,extra,0.1\n')
        self.assert_failed('cz');self.edit(closeout/'completed_evidence.json','artifacts',{'other.csv':'a'*64});self.assert_failed('cz')
    def test_terminal_original_campaign_mismatch_rejected(self):
        _,campaign,_=self.terminal();self.edit(campaign/'terminal.json','status','different');self.assert_failed('cz')
    def test_resealed_incomplete_or_nonfinite_operator_surface_rejected(self):
        _,campaign,_=self.terminal();closeout=campaign/'closeout';path=closeout/'fold_comparison.csv'
        original=path.read_text()
        for changed in (original.replace('CZ,1,cdf_pool_clipped,0.1','CZ,4,cdf_pool_clipped,0.1'),
                original.replace('CZ,1,cdf_pool_clipped,0.1','CZ,1,cdf_pool_clipped,nan'),
                original.replace('CZ,1,cdf_pool_clipped,0.1','LT,1,cdf_pool_clipped,0.1')):
            path.write_text(changed)
            seal=json.loads((closeout/'completed_evidence.json').read_text())
            seal['artifacts']['fold_comparison.csv']=m.digest(path);write(closeout/'completed_evidence.json',seal)
            self.assert_failed('cz')
    def test_blocked_after_terminal_does_not_claim_success(self):
        self.terminal();write(self.runtime/'science_blocked.json',dict(error='publication failed'))
        result=self.assert_failed('cz');self.assertEqual(result['phase'],'blocked')


class ExternalOwnerBudgetIntegrationTests(Fixture):
    """Exercise the real 515 read-only proof through the 518 waiting path."""
    def setUp(self):
        super().setUp();self.cap=self.waiting()
        self.authority.update(waiter_control_cpu=29,budget_heartbeat_max_age_seconds=90,
            final_publication_CPU_reserve_seconds=90.)
        # The authority is immutable before this prospective activation; bind
        # every synthetic registration/activation to its final exact bytes.
        write(self.cp,self.authority);self.global_claim['authority_sha256']=m.digest(self.cp);write(self.cc,self.global_claim)
        for name in ('activation.json','launch_claim.json','progress.json'):
            self.edit(self.runtime/name,'authority_sha256',m.digest(self.cp))
        entry=ENTRY.with_name('515_resolve_pricefm_stage_r153_cz_gate.py')
        spec=importlib.util.spec_from_file_location('r153_observer_real_cpu_api',entry)
        self.real=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.real)
        self.real.PYTHON=self.api.PYTHON;self.real.ENTRY=self.api.ENTRY
        self.api.observe_waiter_cpu=self.real.observe_waiter_cpu
        self.system.proc_cpu_snapshot=Mock(return_value=dict(self_CPU_seconds=2.5,reaped_child_CPU_seconds=.4,tick_seconds=.01))
        self.system.units['wait.service']['CPUUsageNSec']='[not set]'
        self.system.groups[self.cap['properties']['ControlGroup']]=[11]
        self.heartbeat=dict(schema_version=1,authority_sha256=m.digest(self.cp),execution_source=self.src,
            unit='wait.service',InvocationID='invocation-waiter',
            process={key:self.cap['process'][key] for key in ('pid','start_ticks','boot_id','cmdline_sha256','cwd')},
            heartbeat_epoch=990.,mode='self_plus_reaped_administrative_children',control_cpu=29,
            self_CPU_seconds=2.,reaped_admin_CPU_seconds=.3,admin_measurement_reserve_seconds=.5,
            waiter_CPU_seconds=2.8,prior_control_CPU_seconds=125.,charged_CPU_seconds=127.8,
            allowance_CPU_seconds=1800.,expires_epoch=2000.,native_cgroup_CPU_seconds=None,numerical_CPU_included=False)
        self.hb=self.runtime/'control_budget_heartbeat.json';write(self.hb,self.heartbeat)
    def test_missing_native_counter_accepts_bound_measured_owner_fallback(self):
        with (patch.object(self.real.time,'process_time',side_effect=AssertionError('observer CPU forbidden')),
                patch.object(self.real.os,'times',side_effect=AssertionError('observer child CPU forbidden'))):
            result=m.observe('cz',self.system)
        self.assertTrue(result['healthy']);self.assertFalse(result['budget']['observer_CPU_used'])
        self.assertFalse(result['budget']['numerical_CPU_included'])
        self.assertGreaterEqual(result['budget']['charged_CPU_upper_bound_seconds'],138.)
        self.system.proc_cpu_snapshot.assert_called_once_with(self.cap['process'])
        self.api.cpu_guard.assert_not_called()
    def test_missing_stale_or_future_heartbeat_fails(self):
        self.hb.unlink();self.assert_failed('cz')
        for epoch in (909.,1001.):
            write(self.hb,dict(self.heartbeat,heartbeat_epoch=epoch));self.assert_failed('cz')
    def test_wrong_authority_source_pid_unit_or_invocation_fails(self):
        cases=[('authority_sha256','0'*64),('execution_source',dict(self.src,head='f'*40)),
            ('unit','other.service'),('InvocationID','wrong'),('process',dict(self.heartbeat['process'],pid=999)),
            ('process',dict(self.heartbeat['process'],start_ticks=8)),('process',dict(self.heartbeat['process'],boot_id='other')),
            ('mode','observer_process_cpu'),('control_cpu',28),('numerical_CPU_included',True)]
        for field,value in cases:
            write(self.hb,dict(self.heartbeat,**{field:value}))
            with self.subTest(field=field,value=value):self.assert_failed('cz')
    def test_refund_changed_allowance_nonfinite_and_scope_fields_fail(self):
        for field,value in [('prior_control_CPU_seconds',0.),('charged_CPU_seconds',120.),
                ('allowance_CPU_seconds',1900.),('expires_epoch',3000.),('self_CPU_seconds',float('nan')),
                ('reaped_admin_CPU_seconds',-.1),('waiter_CPU_seconds',0.)]:
            write(self.hb,dict(self.heartbeat,**{field:value}))
            with self.subTest(field=field):self.assert_failed('cz')
    def test_fresh_proc_contradiction_or_admin_cpu_escape_fails(self):
        self.system.proc_cpu_snapshot.return_value['self_CPU_seconds']=0.;self.assert_failed('cz')
        self.system.proc_cpu_snapshot.return_value['self_CPU_seconds']=2.5
        self.system.processes[44]=dict(pid=44,cpus=[28,29])
        self.system.groups[self.cap['properties']['ControlGroup']]=[11,44];self.assert_failed('cz')
    def test_native_counter_is_an_additional_bound_not_a_waiver(self):
        self.system.units['wait.service']['CPUUsageNSec']='30000000000'
        result=m.observe('cz',self.system);self.assertTrue(result['healthy'])
        self.assertGreaterEqual(result['budget']['charged_CPU_upper_bound_seconds'],155.)
        self.edit(self.hb,'InvocationID','wrong');self.assert_failed('cz')
    def test_native_counter_rollback_and_exhausted_upper_bound_fail(self):
        self.system.units['wait.service']['CPUUsageNSec']='1000000000';self.edit(self.hb,'native_cgroup_CPU_seconds',3.)
        self.assert_failed('cz');write(self.hb,self.heartbeat)
        self.system.units['wait.service']['CPUUsageNSec']='1700000000000';self.assert_failed('cz')
    def test_remaining_final_publication_reserve_is_not_spendable_wait_cpu(self):
        self.system.units['wait.service']['CPUUsageNSec']='1600000000000'
        result=self.assert_failed('cz')
        self.assertEqual(result['phase'],'verification_failed')
    def test_real_fallback_is_read_only(self):
        before={str(path):path.read_bytes() for path in self.runtime.rglob('*') if path.is_file()}
        result=m.observe('cz',self.system);self.assertTrue(result['healthy'])
        self.assertEqual(before,{str(path):path.read_bytes() for path in self.runtime.rglob('*') if path.is_file()})


class ReadOnlyOutputTests(Fixture):
    def test_optional_output_only_new_outside_canonical_roots(self):
        output=self.root/'export/status.json';m.write_new_output(output,dict(ok=True))
        self.assertEqual(json.loads(output.read_text()),dict(ok=True))
        with self.assertRaises(RuntimeError):m.write_new_output(output,{})
        for target in (self.data/'forbidden.json',self.source/'forbidden.json',Path('relative.json')):
            with self.subTest(target=target),self.assertRaises(RuntimeError):m.write_new_output(target,{})
    def test_output_symlink_and_parent_alias_rejected(self):
        self.data.mkdir();alias=self.root/'alias';alias.symlink_to(self.data,target_is_directory=True)
        with self.assertRaises(RuntimeError):m.write_new_output(alias/'forbidden.json',{})
        actual=self.root/'actual.json';actual.write_text('{}');link=self.root/'link.json';link.symlink_to(actual)
        with self.assertRaises(RuntimeError):m.write_new_output(link,{})
    def test_default_main_writes_no_output_file(self):
        with patch.object(m.sys,'argv',['518','baseline']),patch.object(m,'write_new_output') as out,patch('sys.stdout',new_callable=io.StringIO) as stdout:
            self.assertEqual(m.main(),1)
        out.assert_not_called();self.assertFalse(json.loads(stdout.getvalue())['healthy'])
    def test_source_has_no_dispatch_or_service_actions(self):
        tree=ast.parse(ENTRY.read_text())
        imports={alias.name for node in ast.walk(tree) if isinstance(node,ast.Import) for alias in node.names}
        self.assertFalse(imports & {'subprocess','os','signal'})
        methods={node.func.attr for node in ast.walk(tree) if isinstance(node,ast.Call) and isinstance(node.func,ast.Attribute)}
        self.assertFalse(methods & {'start_science','sleep','terminate','kill','start','stop','run','prepare','launch','delegate'})
        self.assertTrue(m.sys.dont_write_bytecode)


if __name__=='__main__':unittest.main()
