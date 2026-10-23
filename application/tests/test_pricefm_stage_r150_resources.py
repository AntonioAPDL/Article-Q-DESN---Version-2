"""Ownership fault tests: foreign units must never be stopped; own exits drain."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ENTRY = Path(__file__).resolve().parents[1] / 'scripts/pricefm/498_supervise_pricefm_stage_r150_resources.py'
SPEC = importlib.util.spec_from_file_location('r150_resources_tested', ENTRY)
M = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)


def fixture():
    name = 'pricefm-r150-test-worker-012345.service'
    props = {key: '' for key in M.UNIT_PROPERTIES}
    props.update(Id=name, LoadState='loaded', ActiveState='active', SubState='running',
        MainPID='101', InvocationID='invocation-original',
        ControlGroup='/user.slice/user-1.slice/user@1.service/' + name,
        ExecStart='{ path=/python ; argv[]=/python /entry bootstrap --spec /owned/spec ; ignore_errors=no ; start_time=first ; pid=101 ; }',
        Description='R150 owned UUID source frozen', WorkingDirectory=str(M.ROOT),
        BindsTo='pricefm-r150-controller-test.service', After='pricefm-r150-controller-test.service',
        RuntimeMaxUSec='2h', CPUAffinity='8000', CPUSchedulingPolicy='5',
        IOSchedulingClass='3', KillMode='control-group', Restart='no')
    saved = dict(unit=name, description=props['Description'], argv=['/python', '/entry', 'bootstrap', '--spec', '/owned/spec'],
                 attested=copy.deepcopy(props))
    return saved, props


class FakeSystem:
    def __init__(self, props, members=None):
        self.props = copy.deepcopy(props); self.member_list = [101] if members is None else members
        self.stops = []; self.reads = 0

    def unit(self, name):
        self.reads += 1
        return copy.deepcopy(self.props)

    def members(self, cgroup):
        return list(self.member_list)

    def stop(self, name):
        self.stops.append(name); self.props.update(ActiveState='inactive', MainPID='0', ControlGroup='')
        self.member_list = []


class OwnershipFaultTests(unittest.TestCase):
    def test_rapid_exit_checks_prestart_expected_cgroup_without_attestation(self):
        saved, props = fixture(); saved['expected_cgroup']=props['ControlGroup'];saved.pop('attested')
        props.update(LoadState='not-found',ActiveState='inactive',MainPID='0',ControlGroup='')
        system=FakeSystem(props,[202])
        with self.assertRaisesRegex(RuntimeError,'did not drain'):
            M.stop_and_drain(system,saved,timeout=0)
        self.assertEqual(system.stops,[])

    def test_own_active_unit_manager_stop_and_drain(self):
        saved, props = fixture(); system = FakeSystem(props)
        proof = M.stop_and_drain(system, saved, timeout=.01)
        self.assertTrue(proof['drained']); self.assertEqual(system.stops, [saved['unit']])

    def test_invocation_reuse_refuses_every_signal(self):
        saved, props = fixture(); props['InvocationID'] = 'replacement-lifetime'; system = FakeSystem(props)
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            M.stop_and_drain(system, saved, timeout=.01)
        self.assertEqual(system.stops, [])

    def test_foreign_unit_even_matching_command_refused(self):
        saved, props = fixture(); saved['unit'] = 'pricefm-r146-muscat-resource-handoff.service'
        system = FakeSystem(props)
        with self.assertRaisesRegex(RuntimeError, 'namespace'):
            M.stop_and_drain(system, saved)
        self.assertEqual(system.stops, [])

    def test_live_cgroup_drift_refuses_stop(self):
        saved, props = fixture(); props['ControlGroup'] += '/different'; system = FakeSystem(props)
        with self.assertRaisesRegex(RuntimeError, 'ControlGroup'):
            M.stop_and_drain(system, saved)
        self.assertEqual(system.stops, [])

    def test_execstart_drift_refuses_stop(self):
        saved, props = fixture(); props['ExecStart'] = props['ExecStart'].replace('/owned/spec', '/foreign/spec')
        system = FakeSystem(props)
        with self.assertRaisesRegex(RuntimeError, 'ExecStart'):
            M.stop_and_drain(system, saved)
        self.assertEqual(system.stops, [])

    def test_exit_metadata_changes_do_not_change_exec_identity(self):
        saved, props = fixture(); props['ExecStart'] += ' stop_time=now code=exited;'
        self.assertEqual(M.verify_owned(saved, props), 'owned')

    def test_fresh_proc_root_release_is_irrelevant_to_unit_ownership(self):
        saved, props = fixture(); system = FakeSystem(props)
        with mock.patch.object(M, 'process', side_effect=AssertionError('cleanup must not read a mixed /proc snapshot')):
            self.assertTrue(M.stop_and_drain(system, saved)['drained'])

    def test_own_inactive_empty_cgroup_is_safe(self):
        saved, props = fixture(); props.update(ActiveState='inactive', MainPID='0', ControlGroup='')
        system = FakeSystem(props, [])
        self.assertTrue(M.stop_and_drain(system, saved)['drained']); self.assertEqual(system.stops, [])

    def test_unloaded_but_old_cgroup_populated_is_not_drained(self):
        saved, props = fixture(); props.update(LoadState='not-found', ActiveState='inactive', MainPID='0')
        system = FakeSystem(props)
        with self.assertRaisesRegex(RuntimeError, 'did not drain'):
            M.stop_and_drain(system, saved, timeout=0)
        self.assertEqual(system.stops, [])

    def test_unloaded_and_old_cgroup_absent_is_drained(self):
        saved, props = fixture(); props.update(LoadState='not-found', ActiveState='inactive', MainPID='0')
        self.assertTrue(M.stop_and_drain(FakeSystem(props, []), saved)['drained'])

    def test_interrupted_start_intent_is_sufficient_only_exact_match(self):
        saved, props = fixture(); saved.pop('attested')
        self.assertEqual(M.verify_owned(saved, props), 'owned')
        props['Description'] = 'foreign same-named unit'
        with self.assertRaisesRegex(RuntimeError, 'intent mismatch'):
            M.verify_owned(saved, props)

    def test_no_pid_or_group_signal_api(self):
        text = ENTRY.read_text()
        self.assertNotIn('os.kill(', text); self.assertNotIn('os.killpg(', text)
        self.assertFalse(hasattr(M.System, 'signal'))


class LeaseAndAdmissionTests(unittest.TestCase):
    def test_active_sealed_worker_accounting_tail_blocks_phase_transition_until_drain(self):
        saved,props=fixture();system=FakeSystem(props)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);runtime=root/'wave_1'
            saved.update(ledger_path=str(runtime/'workers/token/ownership.json'),policy_receipt=str(runtime/'workers/token/policy_receipt.json'),task='science_task',estimated_cpu_seconds=10,cpu=15)
            M.atomic(root/'admission.json',{'source':{'head':'frozen'},'handoff':{}})
            lease={'wave':'1','lease_id':'lease','expires_epoch':M.time.time()+7200,'started_epoch':M.time.time(),'seconds':7200}
            science=mock.Mock();science.task_complete.return_value=True
            task={'name':'science_task','kind':'S','estimated_cpu_seconds':10,'estimated_wall_seconds':10}
            science.queue_state.side_effect=[{'terminal':False,'ready':[task]},
                {'terminal':True,'ready':[]},{'terminal':True,'ready':[]}]
            launched=[False];advance_states=[];sleeps=[0]
            def advance():
                if launched[0]:
                    self.assertEqual(system.props['ActiveState'],'inactive','CPU tail must exit before irreversible decision')
                advance_states.append(system.props['ActiveState'])
            science.advance.side_effect=advance
            def launch(*args,**kwargs):
                launched[0]=True;M.atomic(saved['ledger_path'],saved);return saved
            def sleep(_seconds):
                sleeps[0]+=1
                if sleeps[0]==2:
                    system.props.update(ActiveState='inactive',MainPID='0',ControlGroup='');system.member_list=[]
            c={'runtime':str(root),'max_workers':2,'cpus':list(range(15,30)),'benchmark_seconds':1200,
               'poll_seconds':0,'cooperative_grace_seconds':0,'wave_cleanup_buffer_seconds':1800,
               'projection_cpu_seconds':5400,'starvation_observation_seconds':300,'starvation_min_cpu_share':.1}
            controller={'ControlGroup':'/user.slice/controller','RuntimeMaxUSec':'2h'}
            with mock.patch.object(M,'System',return_value=system),mock.patch.object(M,'controller_proof',return_value=controller),mock.patch.object(M,'verify_source'),mock.patch.object(M,'lease_once',return_value=lease),mock.patch.object(M,'load_science',return_value=science),mock.patch.object(M,'guard',return_value={'handoff':{}}),mock.patch.object(M,'least_busy_cpus',return_value=c['cpus']),mock.patch.object(M,'start_worker',side_effect=launch),mock.patch.object(M.signal,'signal'),mock.patch.object(M.time,'sleep',side_effect=sleep):
                self.assertEqual(M.run(c,'1','pricefm-r150-controller-test.service'),0)
            self.assertEqual(advance_states,['active','inactive'])
            self.assertEqual(science.queue_state.call_count,3)
            result=M.read(runtime/'terminal.json')
            self.assertEqual(result['status'],'R150_WAVE_COMPLETE');self.assertTrue(result['cleanup_verified'])

    def test_imported_original_benchmark_is_read_only_and_old_wave_duplication_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);runtime=root/'old_runtime';bench=root/'old_benchmark'
            lease_path=runtime/'wave_benchmark/lease.json';terminal_path=runtime/'wave_benchmark/terminal.json'
            drain_path=runtime/'wave_benchmark/workflow_independent_drain.json'
            lease={'source_head':M.PRIOR_HEAD,'wave':'benchmark','seconds':1200,'nonrenewing':True,'lease_id':'sole-old-benchmark'}
            M.atomic(lease_path,lease)
            M.atomic(terminal_path,{'lease':lease,'status':'R150_WAVE_COMPLETE','cleanup_verified':True,'source':{'head':M.PRIOR_HEAD},'baseline_worker_signals':0})
            M.atomic(drain_path,{'cleanup_verified':True,'errors':[],'controller':{'drained':True},'workers':[{'drained':True}]})
            M.atomic(runtime/'workflow_terminal.json',{'completed_admissions':['benchmark'],'cleanup_failures':[]})
            M.atomic(bench/'timings.json',{'rows':[{} for _ in range(18)],'source':{'head':M.PRIOR_HEAD},'new_model_fits':0,'no_new_candidate_AQL_computed':True})
            files={str(p):M.digest(p) for p in root.rglob('*.json')}
            receipt={'status':'PASS_IMMUTABLE_ORIGINAL_BENCHMARK_IMPORT','original_science_source':{'head':M.PRIOR_HEAD,'root':'/immutable-old-root'},
                'new_benchmark_lease_authorized':False,'old_numerical_leases_absent':['1','2','3'],'original_benchmark_calls':18,
                'immutable_file_sha256':files,'original_runtime':str(runtime),'original_wave':{'lease_path':str(lease_path),'terminal_path':str(terminal_path),'independent_drain_path':str(drain_path)},
                'original_benchmark':{'folder':str(bench)},'original_available_cpu_seconds':21786.141934839827}
            receipt_path=root/'benchmark_import.json';M.atomic(receipt_path,receipt)
            c={'benchmark_import':{'path':str(receipt_path),'sha256':M.digest(receipt_path)}}
            original_lease_bytes=lease_path.read_bytes()
            with mock.patch.object(M.subprocess,'check_output',return_value=M.PRIOR_HEAD+'\n'):
                self.assertEqual(M.verify_benchmark_import(c),receipt)
                M.atomic(runtime/'wave_1/lease.json',{'unexpected_duplicate_wave':True})
                with self.assertRaisesRegex(RuntimeError,'duplicate admissions'):
                    M.verify_benchmark_import(c)
            self.assertEqual(lease_path.read_bytes(),original_lease_bytes)

    def test_import_receipt_tamper_stops_before_old_runtime_is_read(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'import.json';M.atomic(path,{'tampered':True})
            with self.assertRaisesRegex(RuntimeError,'import receipt changed'):
                M.verify_benchmark_import({'benchmark_import':{'path':str(path),'sha256':'wrong-pinned-digest'}})

    def test_controller_launch_intent_precedes_start_and_failed_start_drains(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime=Path(directory);system=FakeSystem({})
            admission={'source':{'head':'frozen'},'baseline':{'units':{
                'baseline':{'properties':{'ControlGroup':'/user.slice/user-1.slice/user@1.service/baseline.service'}}}}}
            lease={'wave':'1','lease_id':'lease','source_head':'frozen','expires_epoch':M.time.time()+1200}
            c={'runtime':directory,'cpus':list(range(15,30)),'python_runtime':'/python'}
            def fault(name,description,argv,**kwargs):
                record=M.read(runtime/'wave_1/controller_launch.json')
                self.assertEqual(record['unit'],name)
                self.assertEqual(record['expected_cgroup'],'/user.slice/user-1.slice/user@1.service/'+name)
                system.props=dict(Id=name,Description=description,ExecStart='{ argv[]='+' '.join(argv)+' ; ignore_errors=no ; }',
                    WorkingDirectory=str(M.ROOT),KillMode='control-group',Restart='no',LoadState='loaded',
                    ActiveState='active',MainPID='101',ControlGroup=record['expected_cgroup'])
                raise RuntimeError('injected failure after manager start')
            system.start=mock.Mock(side_effect=fault)
            with mock.patch.object(M,'assert_parent_policy'),mock.patch.object(M,'System',return_value=system),mock.patch.object(M,'admit',return_value=admission),mock.patch.object(M,'lease_once',return_value=lease):
                with self.assertRaisesRegex(RuntimeError,'injected failure after manager start'):
                    M.launch(c,'1')
            self.assertEqual(len(system.stops),1)
            receipt=M.read(next((runtime/'wave_1').glob('controller_launch_failure_*.json')))
            self.assertTrue(receipt['cleanup_verified'])

    def test_wave_guard_counts_workflow_coordinator_and_descendants_in_owned_rss(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime=Path(directory);release_path=runtime/'release.json'
            M.atomic(release_path,{'status':'PASS_PROTECTED_SOURCES_MANIFESTS_AND_R150_RELEASE','source':{'head':'frozen','remote_head':'frozen'}})
            workflow_entry=M.ENTRY.with_name('499_execute_pricefm_stage_r150_finite_workflow.py')
            name='pricefm-r150-workflow-'+'a'*32+'.service'
            command=['/python','-B',str(workflow_entry),'run','--release',str(release_path)]
            record={'unit':name,'command':command,'source_head':'frozen','source_entry_sha256':M.digest(workflow_entry),
                'release_sha256':M.digest(release_path),'admitted_order':['1','2','3'],'runtime_seconds':365*60}
            M.atomic(runtime/'workflow_launch.json',record)
            controller={'ControlGroup':'/user.slice/user-1.slice/user@1.service/controller.service'}
            workflow_cg='/user.slice/user-1.slice/user@1.service/'+name
            props=dict(Id=name,Description=M.WORKFLOW_DESCRIPTION,
                ExecStart='{ argv[]='+' '.join(command)+' ; ignore_errors=no ; }',WorkingDirectory=str(M.ROOT),
                KillMode='control-group',Restart='no',LoadState='loaded',ActiveState='active',MainPID='201',
                InvocationID='workflow-invocation',ControlGroup=workflow_cg,CPUSchedulingPolicy='0')
            system=mock.Mock();system.unit.return_value=props
            system.members.side_effect=lambda cg:[101] if cg==controller['ControlGroup'] else [201,202]
            c={'runtime':directory,'python_runtime':'/python','disk_path':directory,'AT_terminal':'unused',
               'min_available_memory_gib':192,'min_disk_gib':80,'max_owned_rss_gib':24}
            admission={'source':{'head':'frozen'},'handoff':{},'baseline':{'units':{},'AT_terminal_sha256':'AT-hash'}}
            lease={'expires_epoch':M.time.time()+1200,'boot_id':Path('/proc/sys/kernel/random/boot_id').read_text().strip()}
            with mock.patch.object(M,'verify_source'),mock.patch.object(M,'verify_baseline_sources'),mock.patch.object(M,'verify_benchmark_import'),mock.patch.object(M,'assert_parent_policy'),mock.patch.object(M,'handoff_snapshot',return_value={}),mock.patch.object(M,'memory_available_gib',return_value=400),mock.patch.object(M.shutil,'disk_usage',return_value=mock.Mock(free=200*1024**3)),mock.patch.object(M,'rss_gib',return_value=.01) as rss,mock.patch.object(M,'digest',side_effect=lambda p:'AT-hash' if str(p)=='unused' else __import__('hashlib').sha256(Path(p).read_bytes()).hexdigest()):
                result=M.guard(c,system,admission,lease,[],controller)
            rss.assert_called_once_with([101,201,202]);self.assertEqual(result['owned_rss_gib'],.01)
            for key,value in [('source_head','tampered'),('unit','foreign.service'),('command',command+['--extra'])]:
                bad=dict(record);bad[key]=value;M.atomic(runtime/'workflow_launch.json',bad)
                with self.assertRaisesRegex(RuntimeError,'launch record'):
                    M.workflow_members(c,system,'frozen',controller)

    def test_lease_never_renews_and_expired_lease_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);M.atomic(root/'admission.json',{'source':'frozen'})
            M.atomic(root/'old_benchmark_lease.json',{'lease_id':'original-sole-benchmark'})
            imported={'original_science_source':{'head':M.PRIOR_HEAD},'original_wave':{'lease_path':str(root/'old_benchmark_lease.json')}}
            c={'wave_seconds':7200,'benchmark_import':{'sha256':'immutable-import'}}
            admission={'source':{'head':'frozen'}}
            with mock.patch.object(M,'verify_benchmark_import',return_value=imported):
                with mock.patch.object(M.time,'time',return_value=1000):first=M.lease_once(c,root,'1',admission)
                with mock.patch.object(M.time,'time',return_value=1500):second=M.lease_once(c,root,'1',admission)
                self.assertEqual(first,second)
                self.assertEqual(first['original_benchmark_lease_id'],'original-sole-benchmark')
                with mock.patch.object(M.time,'time',return_value=8201):
                    with self.assertRaisesRegex(RuntimeError,'expired lease'):M.lease_once(c,root,'1',admission)
                self.assertEqual(M.read(root/'wave_1/lease.json'),first)
                self.assertFalse((root/'wave_benchmark/lease.json').exists())

    def test_unknown_or_fourth_wave_refused(self):
        for value in ('benchmark', '0', '4', 'unlimited'):
            with self.assertRaisesRegex(RuntimeError, 'three.*finite'):
                M.lease_once({}, '/unused', value, {})

    def test_guard_stopped_previous_wave_never_auto_restarts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); M.atomic(root/'admission.json', {'source':'frozen'})
            M.atomic(root/'wave_1/terminal.json', {'cleanup_verified':True,'status':'R150_GUARD_STOPPED'})
            with self.assertRaisesRegex(RuntimeError, 'explicit review'):
                M.lease_once({'wave_seconds':7200}, root, '2', {'source':{'head':'frozen'}})

    def test_budget_rejects_unknown_timing_or_oversize(self):
        c={'projection_cpu_seconds':5400,'wave_cleanup_buffer_seconds':1800,'projection_cpu_seconds':5400}
        lease={'wave':'1','expires_epoch':10000}
        with mock.patch.object(M.time,'time',return_value=1000):
            self.assertTrue(M.projection_fits({'estimated_cpu_seconds':5000,'estimated_wall_seconds':6000},c,lease,0))
            self.assertFalse(M.projection_fits({'estimated_cpu_seconds':5401,'estimated_wall_seconds':6000},c,lease,0))
            with self.assertRaisesRegex(RuntimeError,'timing estimate'):
                M.projection_fits({},c,lease,0)
            with self.assertRaisesRegex(RuntimeError,'wall estimate'):
                M.projection_fits({'estimated_cpu_seconds':5000},c,lease,0)
            self.assertFalse(M.projection_fits({'estimated_cpu_seconds':2000,'estimated_wall_seconds':9000},c,lease,0))

    def test_starvation_is_checkpoint_deferral_not_priority_lift(self):
        saved={'task':'task','unit':'pricefm-r150-test-worker.service',
               'cpu_sample':{'epoch':100,'pid':101,'start_ticks':2,'boot_id':'boot','cpu_seconds':1}}
        c={'starvation_observation_seconds':300,'starvation_min_cpu_share':.1}
        with mock.patch.object(M,'process',return_value={'start_ticks':2,'boot_id':'boot'}),mock.patch.object(M,'cpu_seconds',return_value=3):
            self.assertIsNone(M.starvation_predicate(saved,c,now=399))
            result=M.starvation_predicate(saved,c,now=400)
            self.assertTrue(result['starved']); self.assertIn('without_requeue',result['action'])

    def test_early_cpu_burst_cannot_hide_later_full_starvation_window(self):
        saved={'task':'task','unit':'pricefm-r150-test-worker.service',
               'cpu_sample':{'epoch':100,'pid':101,'start_ticks':2,'boot_id':'boot','cpu_seconds':1}}
        c={'starvation_observation_seconds':300,'starvation_min_cpu_share':.1}
        with mock.patch.object(M,'process',return_value={'start_ticks':2,'boot_id':'boot'}),mock.patch.object(M,'cpu_seconds',return_value=101):
            first=M.starvation_predicate(saved,c,now=400)
            self.assertFalse(first['starved']);self.assertEqual(saved['cpu_sample']['epoch'],400)
            second=M.starvation_predicate(saved,c,now=700)
            self.assertTrue(second['starved']);self.assertEqual(second['delivered_cpu_share'],0)

    def test_started_unit_fault_before_active_insert_is_discovered_and_drained(self):
        saved,props=fixture();system=FakeSystem(props)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);runtime=root/'wave_1'
            saved.update(ledger_path=str(runtime/'workers/token/ownership.json'),policy_receipt=str(runtime/'workers/token/policy_receipt.json'),task='science_task')
            admission={'source':{'head':'frozen'},'handoff':{}}
            M.atomic(root/'admission.json',admission)
            lease={'wave':'1','lease_id':'lease','expires_epoch':M.time.time()+7200,'started_epoch':M.time.time(),'seconds':7200}
            science=mock.Mock();science.queue_state.return_value={'terminal':False,'ready':[{'name':'science_task','kind':'D','estimated_cpu_seconds':10,'estimated_wall_seconds':10}]}
            science.task_complete.return_value=False
            def fault(*args,**kwargs):
                M.atomic(saved['ledger_path'],saved)
                raise RuntimeError('injected fault after unit start before active insertion')
            c={'runtime':str(root),'max_workers':2,'cpus':list(range(15,30)),'benchmark_seconds':1200,'poll_seconds':0,'cooperative_grace_seconds':0,'wave_cleanup_buffer_seconds':1800,'projection_cpu_seconds':5400}
            controller={'ControlGroup':'/user.slice/controller','RuntimeMaxUSec':'2h'}
            with mock.patch.object(M,'System',return_value=system),mock.patch.object(M,'controller_proof',return_value=controller),mock.patch.object(M,'verify_source'),mock.patch.object(M,'lease_once',return_value=lease),mock.patch.object(M,'load_science',return_value=science),mock.patch.object(M,'guard',return_value={'handoff':{}}),mock.patch.object(M,'least_busy_cpus',return_value=c['cpus']),mock.patch.object(M,'start_worker',side_effect=fault),mock.patch.object(M.signal,'signal'):
                self.assertEqual(M.run(c,'1','pricefm-r150-controller-test.service'),2)
            terminal=M.read(runtime/'terminal.json')
            self.assertIn('injected fault',terminal['original_stop_reason'])
            self.assertTrue(terminal['cleanup_verified']);self.assertEqual(system.stops,[saved['unit']])

    def test_no_new_benchmark_task_or_lease_allowed(self):
        with self.assertRaisesRegex(RuntimeError,'benchmark'):
            M.projection_fits({'name':'__benchmark__'}, {}, {'wave':'benchmark'},0)
        with self.assertRaisesRegex(RuntimeError,'benchmark'):
            M.projection_fits({'name':'__benchmark__'}, {}, {'wave':'1'},0)

    def test_handoff_normal_advancement_allowed_regression_stops(self):
        owner={'pid':1,'start_ticks':2,'boot_id':'boot','cmdline_sha256':'owner'}
        guardian={'pid':3,'start_ticks':4,'boot_id':'boot','cmdline_sha256':'guard'}
        state={'owner':owner,'attempt':'attempt','phase':'waiting_boundary','heartbeat':95.,'guardian_unit':'guard.service'}
        system=mock.Mock(); system.unit.return_value={'MainPID':'3','ActiveState':'active','InvocationID':'guardian-lifetime'}
        c={'handoff_state':'unused','handoff_fresh_seconds':30}
        with mock.patch.object(M,'read',return_value=state),mock.patch.object(M,'process',side_effect=lambda pid:owner if pid==1 else guardian):
            first=M.handoff_snapshot(c,system,now=100)
            state['heartbeat']=99.; second=M.handoff_snapshot(c,system,first,now=100)
            self.assertEqual(second['heartbeat'],99.)
            state['heartbeat']=94.
            with self.assertRaisesRegex(RuntimeError,'regressed'):
                M.handoff_snapshot(c,system,first,now=100)

    def test_handoff_transition_and_staleness_stop(self):
        c={'handoff_state':'unused','handoff_fresh_seconds':30}
        for state in ({'phase':'draining','heartbeat':99.},{'phase':'waiting_boundary','heartbeat':60.}):
            with mock.patch.object(M,'read',return_value=state):
                with self.assertRaisesRegex(RuntimeError,'phase/freshness'):
                    M.handoff_snapshot(c,mock.Mock(),now=100)

    def test_duration_and_bitmask_systemd239(self):
        self.assertEqual(M.parse_duration('1h 30min 2s'),5402)
        self.assertEqual(M.parse_cpu_affinity('8000'),[15])
        self.assertEqual(M.parse_cpu_affinity('3fff8000'),list(range(15,30)))

    def test_original_reason_survives_cleanup_event(self):
        with tempfile.TemporaryDirectory() as directory:
            item=M.event(directory,'terminal',epoch=10,original_stop_reason='guard-failed',cleanup_errors=['later-cleanup-failed'])
            self.assertEqual(item['original_stop_reason'],'guard-failed')
            self.assertEqual(item['cleanup_errors'],['later-cleanup-failed'])
            self.assertEqual(item['epoch'],10)


if __name__ == '__main__':
    unittest.main()
