"""CZ resource-boundary faults; no model imports, services or scientific dispatch."""
import copy
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'application/scripts/pricefm'
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
GATE=load('r153_cz_gate_test','515_resolve_pricefm_stage_r153_cz_gate.py')
RELEASE=load('r153_cz_release_test','516_release_pricefm_stage_r153_cz_gate.py')


def put(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')


def process(pid=100,cpus=None,argv=None):
    return dict(pid=pid,start_ticks=pid*10,boot_id='boot',cwd='/frozen',
                cmdline_sha256='hash'+str(pid),argv=argv or ['python','metadata'],
                cpus=cpus or [0],cgroups=['/user.slice/fake.service'])


class FakeSystem:
    def __init__(self):
        self.time=200.;self.procs={};self.units={};self.groups={};self.sources={};self.dispatches=[]
    def host(self):return 'jerez'
    def now(self):return self.time
    def source(self,root):return self.sources[str(root)]
    def unit(self,name):return self.units.get(name,dict(Id=name,ActiveState='inactive',MainPID='0',ControlGroup=''))
    def process(self,pid):return self.procs.get(pid)
    def processes(self):return list(self.procs.values())
    def members(self,group):return self.groups.get(group,[])
    def sleep(self,seconds):self.time+=seconds
    def start_science(self,authority,path):
        self.dispatches.append(authority['science_unit']);return ['truthful','new-wrapper','--delegated-entry',str(GATE.R144_ENTRY)]


class CZGateTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.data=self.root/'data'
        self.patch=mock.patch.multiple(GATE,DATA=self.data,RUNTIME=self.data/'launch_prep/r153/cz');self.patch.start()
        self.system=FakeSystem();self.identifier='1'*32;self.runtime=GATE.RUNTIME/self.identifier
        self.runtime.mkdir(parents=True)
        original=json.loads(GATE.R144_CONFIG.read_text());self.config=copy.deepcopy(original)
        self.config['predecessor_terminal_status']=GATE.DEGRADED
        config_path=self.root/'original_config.json';put(config_path,original)
        self.authority=dict(schema_version=1,kind='R153_CZ_RESOURCE_RESOLUTION',id=self.identifier,
            runtime=str(self.runtime),created_epoch=100.,expires_epoch=604900.,
            control_CPU_allowance_seconds=1800.,activation_limit=1,scientific_dispatch_limit=1,
            approved_quarantined_regions=['NO_3'],predecessor_queue=GATE.QUEUE,
            resource_only=True,cached_restart_authorized=False,fit_cap_changes=0,
            certificate_limit_changes=0,scientific_source_changes=0,
            waiter_unit='pricefm-r153-cz-gate-'+self.identifier+'.service',
            science_unit='pricefm-r153-cz-science-'+self.identifier+'.service',
            science_config_path=str(config_path),science_config_sha256=GATE.sha(config_path),
            effective_config=self.config,effective_config_sha256=GATE.sha_bytes(json.dumps(self.config,indent=2,sort_keys=True)+'\n'),
            frozen_sha256={},approved_NO3_evidence_sha256={},
            old_waiter=dict(unit=GATE.OLD_WAITER_UNIT,process=process(11),cgroup='/user.slice/old-waiter.service'),
            predecessor=dict(unit=GATE.R143_UNIT,process=process(12),cgroup='/user.slice/r143.service'),
            approved_predecessor_failures=[dict(region='NO_3',returncode=1,reason='certification stop')],
            prior_control_CPU_charged_seconds=125.)
        for key in ['execution_source','science_source','predecessor_source','process_adapter_source','resource_core_source']:
            path=str(self.root/key);identity=dict(root=path,branch='frozen-'+key,head='a'*40)
            self.authority[key]=identity;self.system.sources[path]=identity
        for name in GATE.APPROVED_NO3_TASKS:
            base=self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks_done'/name
            put(self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks'/(name+'.json'),dict(name=name,kind='internal_al'))
            put(base/'completed_evidence.json',dict(metadata=dict(certified=False)))
            put(base/'fit/fixedpoint_certificate.json',dict(certified=False))
            for p in [self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks'/(name+'.json'),base/'completed_evidence.json',base/'fit/fixedpoint_certificate.json']:
                self.authority['approved_NO3_evidence_sha256'][str(p)]=GATE.sha(p)
        self.reviewed_patch=mock.patch.object(GATE,'APPROVED_NO3_REVIEWED_SHA',{name:{
            'task':GATE.sha(self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks'/(name+'.json')),
            'seal':GATE.sha(self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks_done'/name/'completed_evidence.json'),
            'certificate':GATE.sha(self.data/'campaigns'/(self.config['source_tag']+'__NO_3')/'tasks_done'/name/'fit/fixedpoint_certificate.json')}
            for name in GATE.APPROVED_NO3_TASKS});self.reviewed_patch.start()
        put(self.runtime/'effective_config.json',self.config)
        self.path=self.runtime/'authority.json';self.save()
        self.predecessor=self.data/'launch_prep'/self.config['predecessor_tag']/'jerez'
        put(self.predecessor/'progress.json',dict(failures=self.authority['approved_predecessor_failures']))
    def tearDown(self):self.reviewed_patch.stop();self.patch.stop();self.temp.cleanup()
    def save(self):put(self.path,self.authority)
    def ready_terminal(self,**updates):
        value=dict(status=GATE.DEGRADED,source={k:self.config[k] for k in []},assigned_count=7,
            active_region=None,pending=[],quarantined_region='CZ',
            completed=[r for r in GATE.QUEUE if r!='NO_3'],failures=self.authority['approved_predecessor_failures'])
        value['source']=dict(branch=self.config['source_branch'],head=self.config['source_head'])
        value.update(updates);put(self.predecessor/'terminal.json',value);return value
    def boundary(self):return GATE.boundary_state(self.authority,self.system,complete=lambda c,r:dict(certified=True))
    def waiter_capsule(self):
        unit=self.authority['waiter_unit'];pid=os.getpid();group='/user.slice/'+unit
        argv=[str(GATE.PYTHON),'-B',str(GATE.ENTRY),'run','--authority',str(self.path),'--unit',unit]
        p=process(pid,argv=argv);p['cwd']=str(GATE.ROOT);p['cgroups']=[group];self.system.procs[pid]=p
        self.system.units[unit]=dict(Id=unit,MainPID=str(pid),ActiveState='active',ControlGroup=group,
            InvocationID='invocation',Restart='no',KillMode='process',CPUAccounting='yes',CPUUsageNSec='100000000',
            WorkingDirectory=str(GATE.ROOT),RuntimeMaxUSec='7d')
        put(self.runtime/'launch_claim.json',dict(authority_sha256=GATE.sha(self.path),expected_argv=argv,expected_RuntimeMaxSec=604800))
        put(self.runtime/'old_waiter_fence.json',dict(authority_sha256=GATE.sha(self.path)))
        put(GATE.RUNTIME/'single_activation_claim.json',dict(id=self.authority['id'],authority_sha256=GATE.sha(self.path)))
        (self.data/'launch_prep'/self.config['tag']/'jerez').mkdir(parents=True,exist_ok=True)
    def test_effective_config_changes_only_honest_resource_status(self):
        original=json.loads(GATE.R144_CONFIG.read_text());new=GATE.effective_config(original)
        self.assertEqual({k for k in original if original[k]!=new[k]},{'predecessor_terminal_status'})
        self.assertEqual(original['predecessor_terminal_status'],GATE.CLEAN)
        self.assertEqual(new['predecessor_terminal_status'],GATE.DEGRADED)
        self.assertEqual(new['al_max_iter'],300);self.assertEqual(new['fallback_rank'],3)
    def test_valid_authority_keeps_scope_one_activation_and_source_pins(self):
        self.assertEqual(GATE.validate_authority(self.path,system=self.system),self.authority)
    def test_wrong_effective_numerical_parameter_rejected(self):
        self.authority['effective_config']['al_max_iter']=301;self.save()
        with self.assertRaisesRegex(RuntimeError,'effective configuration'):GATE.validate_authority(self.path,system=self.system)
    def test_unbounded_activation_or_new_quarantine_rejected(self):
        for key,value in [('activation_limit',2),('approved_quarantined_regions',['NO_3','PT']),('cached_restart_authorized',True)]:
            original=self.authority[key];self.authority[key]=value;self.save()
            with self.assertRaisesRegex(RuntimeError,'scope differs'):GATE.validate_authority(self.path,system=self.system)
            self.authority[key]=original
    def test_expired_authority_does_not_renew(self):
        self.system.time=self.authority['expires_epoch']
        with self.assertRaisesRegex(RuntimeError,'expired'):GATE.validate_authority(self.path,system=self.system)
    def test_source_adapter_change_rejected(self):
        root=self.authority['process_adapter_source']['root'];self.system.sources[root]=dict(self.system.sources[root],head='b'*40)
        with self.assertRaisesRegex(RuntimeError,'source identity'):GATE.validate_authority(self.path,system=self.system)
    def test_different_false_certificate_cannot_replace_exact_reviewed_target(self):
        path=next(Path(name) for name in self.authority['approved_NO3_evidence_sha256'] if name.endswith('fixedpoint_certificate.json'))
        put(path,dict(certified=False,new_failure=True))
        self.authority['approved_NO3_evidence_sha256'][str(path)]=GATE.sha(path);self.save()
        with self.assertRaisesRegex(RuntimeError,'exact reviewed'):GATE.validate_authority(self.path,system=self.system)
    def test_effective_config_archive_is_not_an_unchecked_document(self):
        put(self.runtime/'effective_config.json',dict(al_max_iter=301))
        with self.assertRaisesRegex(RuntimeError,'effective configuration'):GATE.validate_authority(self.path,system=self.system)
    def test_other_authority_cannot_reuse_single_global_activation(self):
        put(GATE.RUNTIME/'single_activation_claim.json',dict(id='2'*32,authority_sha256='other'))
        with self.assertRaisesRegex(RuntimeError,'already belongs'):GATE.validate_authority(self.path,system=self.system)
    def test_positive_pid_reuse_proof_does_not_read_protected_unrelated_metadata(self):
        reader=GATE.System.__new__(GATE.System)
        reader.adapter=mock.Mock(boot_id='boot')
        reader.adapter.stat_sample.return_value=dict(pid=12,start_ticks=999,state='R')
        reader.adapter.terminal_or_gone.return_value=False
        with mock.patch.object(reader,'process',side_effect=PermissionError('unrelated protected PID')) as protected:
            self.assertIsNone(reader.recorded(process(12)))
            protected.assert_not_called()
    def test_changed_no3_certificate_or_pin_rejected(self):
        path=Path(next(iter(self.authority['approved_NO3_evidence_sha256'])))
        path.write_text('changed')
        with self.assertRaisesRegex(RuntimeError,'pinned'):GATE.validate_authority(self.path,system=self.system)
    def test_missing_terminal_waits_without_dispatch(self):
        self.assertFalse(self.boundary()['ready']);self.assertEqual(self.system.dispatches,[])
    def test_truthful_degraded_terminal_ready_only_with_exact_approved_failure(self):
        self.ready_terminal();value=self.boundary()
        self.assertTrue(value['ready']);self.assertEqual(value['predecessor_status'],GATE.DEGRADED)
        self.assertEqual(GATE.read(self.predecessor/'terminal.json')['status'],GATE.DEGRADED)
    def test_clean_terminal_is_not_forged_or_accepted_as_this_exception(self):
        self.ready_terminal(status=GATE.CLEAN)
        with self.assertRaisesRegex(RuntimeError,'final disposition'):self.boundary()
    def test_new_pt_or_se3_quarantine_fails_closed(self):
        put(self.predecessor/'progress.json',dict(failures=self.authority['approved_predecessor_failures']+[dict(region='PT')]))
        with self.assertRaisesRegex(RuntimeError,'unapproved'):self.boundary()
    def test_incomplete_queue_or_region_cannot_release(self):
        self.ready_terminal(completed=['ES','HR','IT_SARD','LV','PT'])
        with self.assertRaisesRegex(RuntimeError,'final disposition'):self.boundary()
        self.ready_terminal()
        with self.assertRaisesRegex(RuntimeError,'required completed'):
            GATE.boundary_state(self.authority,self.system,complete=lambda c,r:False if r=='SE_3' else True)
    def test_inactive_predecessor_with_live_orphan_cgroup_still_waits(self):
        self.ready_terminal();group=self.authority['predecessor']['cgroup'];self.system.groups[group]=[999]
        value=self.boundary();self.assertFalse(value['ready']);self.assertIn('CGROUP_DRAIN',value['status'])
    def test_live_or_restarted_predecessor_still_waits(self):
        self.ready_terminal();self.system.units[GATE.R143_UNIT]=dict(ActiveState='active',MainPID='42',ControlGroup='/user.slice/new')
        self.assertFalse(self.boundary()['ready'])
    def test_own_lifetime_still_live_defeats_inactive_unit(self):
        self.ready_terminal();self.system.procs[12]=self.authority['predecessor']['process']
        self.assertFalse(self.boundary()['ready'])
    def test_r143_terminal_changed_during_census_rejected(self):
        self.ready_terminal();before=self.system.processes
        def racing():
            value=GATE.read(self.predecessor/'terminal.json');value['epoch']=12345;put(self.predecessor/'terminal.json',value);return before()
        self.system.processes=racing
        with self.assertRaisesRegex(RuntimeError,'changed during'):self.boundary()
    def test_numerical_conflict_not_hidden_by_empty_predecessor_unit(self):
        self.ready_terminal();self.system.procs[31]=process(31,[16],['/R','--file=/frozen/model.R'])
        value=self.boundary();self.assertFalse(value['ready']);self.assertIn('NUMERICAL_DRAIN',value['status'])
    def test_jerez_wide_dispatcher_not_misclassified_as_model(self):
        p=process(31,list(range(64)),[str(Path(self.config['source_worktree'])/'application/scripts/pricefm/480_run_pricefm_stage_r141_region.py'),'controller','--region','NO_1'])
        self.assertEqual(GATE.numerical_conflicts(self.authority,[p]),[])
        p['argv']=[str(GATE.R144_ENTRY),'worker','--region','CZ'];self.assertTrue(GATE.numerical_conflicts(self.authority,[p]))
    def test_single_cpu_slot_a_R_does_not_block_slot_b(self):
        self.assertEqual(GATE.numerical_conflicts(self.authority,[process(31,[0],['R','--file=/fit.R'])]),[])
    def test_empty_live_metadata_cannot_be_omitted(self):
        p=process(31,[15]);p['argv']=[]
        with self.assertRaisesRegex(RuntimeError,'empty metadata'):GATE.numerical_conflicts(self.authority,[p])
    def test_original_waiter_inactive_does_not_hide_orphan(self):
        self.system.groups[self.authority['old_waiter']['cgroup']]=[999]
        self.assertFalse(GATE.old_waiter_drained(self.authority,self.system)['drained'])
    def test_systemd_expiry_parse_is_bounded_and_explicit(self):
        self.assertEqual(GATE.systemd_seconds('6d 23h 59min 59s'),604799)
        self.assertEqual(GATE.systemd_seconds('604800000000'),604800)
        for value in ['infinity','','nonsense']:
            with self.assertRaises(RuntimeError):GATE.systemd_seconds(value)
    def test_self_attestation_checks_real_new_entry_and_launch_timeout(self):
        self.waiter_capsule();self.assertEqual(GATE.self_attestation(self.authority,self.path,self.system,role='waiter')['actual_entry'],str(GATE.ENTRY))
        self.system.units[self.authority['waiter_unit']]['RuntimeMaxUSec']='8d'
        with self.assertRaisesRegex(RuntimeError,'expiry'):GATE.self_attestation(self.authority,self.path,self.system,role='waiter')
    def test_cpu_accounting_unavailable_or_exhausted_fails_closed(self):
        unit=self.authority['waiter_unit'];self.system.units[unit]=dict(CPUUsageNSec='[not set]')
        with self.assertRaisesRegex(RuntimeError,'unavailable'):GATE.cpu_guard(self.authority,self.system)
        self.system.units[unit]=dict(CPUUsageNSec=str(1800*10**9))
        with self.assertRaisesRegex(RuntimeError,'exhausted'):GATE.cpu_guard(self.authority,self.system)
    def test_expiry_guard_does_not_depend_only_on_systemd(self):
        self.waiter_capsule();self.system.time=self.authority['expires_epoch']
        with self.assertRaisesRegex(RuntimeError,'expired'):GATE.cpu_guard(self.authority,self.system)
    def test_create_once_record_never_overwrites(self):
        p=self.runtime/'claim.json';GATE.immutable(p,dict(once=True))
        with self.assertRaises(FileExistsError):GATE.immutable(p,dict(once=False))
        self.assertTrue(GATE.read(p)['once'])
    def test_real_dispatch_claim_once_and_no_worker_signals(self):
        self.waiter_capsule();states=[dict(ready=False,status='waiting'),dict(ready=True,status='ready'),dict(ready=True,status='ready')]
        with mock.patch.object(GATE,'validate_authority',return_value=self.authority),mock.patch.object(GATE,'boundary_state',side_effect=states):
            value=GATE.run(self.path,self.authority['waiter_unit'],system=self.system,poll_seconds=1)
        self.assertEqual(len(self.system.dispatches),1);self.assertEqual(value['scientific_dispatches'],1)
        self.assertTrue((self.runtime/'science_claim.json').exists())
        with mock.patch.object(GATE,'validate_authority',return_value=self.authority):
            with self.assertRaises(FileExistsError):GATE.run(self.path,self.authority['waiter_unit'],system=self.system)
        self.assertEqual(len(self.system.dispatches),1)
    def test_launch_failure_keeps_claim_spent_and_no_automatic_retry(self):
        self.waiter_capsule()
        def broken(*args):raise RuntimeError('injected launch failure')
        self.system.start_science=broken
        with mock.patch.object(GATE,'validate_authority',return_value=self.authority),mock.patch.object(GATE,'boundary_state',return_value=dict(ready=True,status='ready')):
            with self.assertRaisesRegex(RuntimeError,'injected'):GATE.run(self.path,self.authority['waiter_unit'],system=self.system)
        self.assertTrue((self.runtime/'science_claim.json').exists())
        self.assertFalse(GATE.read(self.runtime/'waiter_blocked.json')['models_signalled'])
    def test_missing_fence_proof_prevents_activation(self):
        self.waiter_capsule();(self.runtime/'old_waiter_fence.json').unlink()
        with mock.patch.object(GATE,'validate_authority',return_value=self.authority):
            with self.assertRaisesRegex(RuntimeError,'fence receipt'):GATE.run(self.path,self.authority['waiter_unit'],system=self.system)
        self.assertFalse((self.runtime/'activation.json').exists())
    def test_prepare_uses_one_epoch_for_exact_seven_day_allowance(self):
        class Clock(FakeSystem):
            def now(self):self.time+=.01;return self.time
        system=Clock();system.sources=self.system.sources
        old=copy.deepcopy(self.authority['old_waiter']);old['invocation_id']='old'
        prior=copy.deepcopy(self.authority['predecessor']);prior['invocation_id']='r143'
        system.groups[old['cgroup']]=[old['process']['pid']]
        original_runtime=self.data/'launch_prep'/self.config['tag']/'jerez'
        put(original_runtime/'progress.json',dict(status='R144_WAITING_FOR_R143_SLOT_B'))
        probe=self.root/'private_proof.json';put(probe,dict(exact_cleanup=True,control_CPU_charged_seconds=5.,
            status='PASS_R153_CZ_PRIVATE_CONTROL_LIFECYCLE',execution_source=self.authority['execution_source']))
        records={key:self.authority[key] for key in ['execution_source','science_source','predecessor_source','process_adapter_source','resource_core_source']}
        with mock.patch.object(RELEASE,'api',return_value=GATE),mock.patch.object(RELEASE,'source_records',return_value=(records,{})),mock.patch.object(RELEASE,'verify_probe_history',return_value=5.),mock.patch.object(RELEASE,'control_snapshot',side_effect=[old,prior]),mock.patch.object(RELEASE,'no3_failure_pins',return_value=self.authority['approved_NO3_evidence_sha256']):
            result=RELEASE.prepare(probe_receipts=[probe],system=system)
        authority=GATE.read(result['authority_path'])
        self.assertEqual(authority['expires_epoch']-authority['created_epoch'],604800.)
        self.assertEqual(authority['prior_control_CPU_charged_seconds'],125.)
        self.assertFalse((GATE.RUNTIME/'single_activation_claim.json').exists())
    def git_probe_fixture(self):
        repo=self.root/'probe_git';repo.mkdir()
        def git(*args):
            return subprocess.check_output(['git','-C',str(repo),'-c','user.name=Test','-c','user.email=test@example.invalid',*args],text=True,stderr=subprocess.DEVNULL).strip()
        git('init','-q');folder=repo/'application/scripts/pricefm';folder.mkdir(parents=True)
        names=['515_resolve_pricefm_stage_r153_cz_gate.py','516_release_pricefm_stage_r153_cz_gate.py']
        for name in names:(folder/name).write_text('old '+name)
        git('add','.');git('commit','-qm','first private proof');first=git('rev-parse','HEAD')
        payload={str((folder/name).relative_to(repo)):hashlib.sha256((folder/name).read_bytes()).hexdigest() for name in names}
        for name in names:(folder/name).write_text('new '+name)
        git('add','.');git('commit','-qm','fixed source');last=git('rev-parse','HEAD')
        receipt=dict(status='FAILED_R153_CZ_PRIVATE_CONTROL_LIFECYCLE',exact_cleanup=True,
            control_CPU_charged_seconds=17.,production_unit_actions=0,model_dispatches=0,source_or_runtime_changes=0,
            execution_source=dict(root=str(repo),branch='work/pricefm-r153-control-lifecycle-test',head=first),runtime_source_sha256=payload)
        current=dict(root=str(repo),branch='work/pricefm-r153-control-lifecycle-test',head=last)
        return repo,git,receipt,current
    def test_failed_ancestor_private_probe_is_fully_charged_after_source_fix(self):
        repo,git,receipt,current=self.git_probe_fixture()
        self.assertEqual(RELEASE.verify_probe_history(receipt,current,root=repo),17.)
    def test_private_history_rejects_negative_credit_or_wrong_committed_bytes(self):
        repo,git,receipt,current=self.git_probe_fixture()
        receipt['control_CPU_charged_seconds']=-1
        with self.assertRaisesRegex(RuntimeError,'cost scope'):RELEASE.verify_probe_history(receipt,current,root=repo)
        receipt['control_CPU_charged_seconds']=17.
        receipt['runtime_source_sha256'][next(iter(receipt['runtime_source_sha256']))]='0'*64
        with self.assertRaisesRegex(RuntimeError,'runtime bytes'):RELEASE.verify_probe_history(receipt,current,root=repo)
    def test_unrelated_committed_private_probe_is_not_a_new_grant(self):
        repo,git,receipt,current=self.git_probe_fixture()
        receipt['execution_source']['head']=git('commit-tree','HEAD^{tree}','-m','unrelated history')
        with self.assertRaisesRegex(RuntimeError,'not a committed ancestor'):RELEASE.verify_probe_history(receipt,current,root=repo)
    def test_release_claim_requires_existing_exact_fence(self):
        with mock.patch.object(RELEASE,'api',return_value=GATE),mock.patch.object(GATE,'validate_authority',return_value=self.authority):
            with self.assertRaisesRegex(RuntimeError,'fence proof'):RELEASE.launch(self.path,system=self.system)
    def test_fence_refuses_numerical_child_before_any_stop(self):
        old=self.authority['old_waiter'];old['invocation_id']='old'
        self.system.units[old['unit']]=dict(ActiveState='active',MainPID=str(old['process']['pid']),InvocationID='old',ControlGroup=old['cgroup'])
        self.system.procs[old['process']['pid']]=old['process'];self.system.groups[old['cgroup']]=[old['process']['pid'],999]
        with mock.patch.object(RELEASE,'api',return_value=GATE),mock.patch.object(GATE,'validate_authority',return_value=self.authority),mock.patch.object(RELEASE.subprocess,'run') as stop:
            with self.assertRaisesRegex(RuntimeError,'sole control'):RELEASE.fence(self.path,system=self.system)
            stop.assert_not_called()

if __name__=='__main__':unittest.main()
