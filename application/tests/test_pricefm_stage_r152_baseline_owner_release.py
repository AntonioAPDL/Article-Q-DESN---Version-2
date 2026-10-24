"""Generation2 baseline authority and adoption tests; temporary metadata only."""
import copy
from contextlib import ExitStack,nullcontext
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import Mock,patch

ROOT=Path(__file__).resolve().parents[2]
ENTRY=ROOT/'application/scripts/pricefm/512_release_pricefm_stage_r152_baseline_owner.py'
spec=importlib.util.spec_from_file_location('r152_baseline_release_tests',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def process(pid,argv,cpus,session=None):
    raw='\0'.join(argv).encode()
    return dict(pid=pid,start_ticks=pid*10,boot_id='boot',cmdline_sha256=hashlib.sha256(raw).hexdigest(),
        argv=argv,cwd=str(m.OLD_ROOT),cpus=cpus,affinity=cpus,scheduler=0,session_id=session or pid,state='S',cgroups=[])


class MembersContract(unittest.TestCase):
    def test_inactive_unit_empty_cgroup_is_absence(self):
        system=object.__new__(m.System);system.unit_api=Mock()
        self.assertEqual(system.members(''),[])
        system.unit_api.members.assert_not_called()

    def test_nonempty_cgroup_retains_strict_ownership_reader(self):
        system=object.__new__(m.System);system.unit_api=Mock()
        system.unit_api.members.return_value=[123]
        self.assertEqual(system.members('/user.slice/owned.service'),[123])
        system.unit_api.members.assert_called_once_with('/user.slice/owned.service')


class FakeSystem:
    def __init__(self,test):
        self.test=test;self.procs={};self.props={};self.groups={};self.started=[];self.stopped=[]
    def process(self,pid):return copy.deepcopy(self.procs.get(pid))
    def processes(self):return copy.deepcopy(list(self.procs.values()))
    def unit(self,unit):return copy.deepcopy(self.props.get(unit,dict(Id=unit,MainPID='0',ActiveState='inactive',ControlGroup='')))
    def members(self,group):return list(self.groups.get(group,[]))
    def uid(self,pid):return os.getuid()
    def control_process(self,pid):return self.process(pid)
    def start_control(self,intent,stdout):
        self.started.append(intent['unit']);self.intent=intent
        proc=process(500,intent['argv'],list(range(30)));self.procs[500]=proc
        self.props[intent['unit']]=dict(Id=intent['unit'],Description=intent['description'],MainPID='500',ActiveState='active',
            InvocationID='new-inv',KillMode='process',Restart='on-failure',WorkingDirectory=str(m.OLD_ROOT),
            argv_string=' '.join(intent['argv']),IOSchedulingClass='3',CPUAccounting='yes',ControlGroup='/user.slice/test/'+intent['unit'])
    def publish_generation_two(self):
        t=self.test;state=t.read(t.runtime/'state.json');epoch=t.read(t.runtime/'resource_ownership_epoch.json')
        state['guardian_unit']='new-guardian';t.write(t.runtime/'state.json',state)
        epoch.update(generation=2,phase='running',owner=self.procs[500],guardian_unit='new-guardian',
            predecessor_sha256=t.sha(t.runtime/'owner_epochs/001.json'))
        t.write(t.runtime/'resource_ownership_epoch.json',epoch);t.write(t.runtime/'owner_epochs/002.json',epoch)
    def stop_owner(self,intent):
        self.state_phase_at_stop=self.test.read(self.test.runtime/'state.json')['phase']
        self.stopped.append(intent['unit']);self.procs.pop(500,None)
        if intent['unit'] in self.props:self.props[intent['unit']].update(MainPID='0',ActiveState='inactive')


class BaselineReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.shared=Path(self.temp.name);self.runtime=self.shared/'baseline';self.runtime.mkdir()
        self.sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
        self.write=lambda path,value:self._write(path,value)
        self.read=lambda path:json.loads(Path(path).read_text())
        original=m.core();self.core=types.SimpleNamespace(**{name:getattr(original,name) for name in dir(original) if not name.startswith('__')})
        self.core.fences=lambda *args,**kwargs:nullcontext()
        original_release=m.release_api()
        self.release=types.SimpleNamespace(immutable=original_release.immutable,locked=original_release.locked,digest=self.sha,
            verify_source=Mock(),validate_probe_receipts=lambda paths,source,master:copy.deepcopy(self.probes),original_master=self.original_master)
        self.pool=types.SimpleNamespace(legacy=lambda:types.SimpleNamespace(exec_arguments=lambda props:props.get('argv_string','')))
        self.adapter=types.SimpleNamespace(verify_baseline=Mock(return_value=dict(healthy=True)))
        self.system=FakeSystem(self);self.unit='pricefm-r152-muscat-baseline.service';self.guardian='old-guardian'
        self.group='/user.slice/test/'+self.unit
        self.owner=process(100,[str(m.OLD_ENTRY),'run'],list(range(30)));self.owner['cgroups']=[self.group]
        self.root=process(200,['python','-B','480_run_pricefm_stage_r141_region.py','controller','--region','IT_CALA'],list(range(15)))
        self.child=process(201,['Rscript','470_fit_pricefm_stage_r137_certified_al_300.R','--config','original-contract'],list(range(15)),session=200)
        self.system.procs={200:copy.deepcopy(self.root),201:copy.deepcopy(self.child)}
        self.system.groups={self.group:[200,201]}
        self.system.props[self.unit]=dict(Id=self.unit,MainPID='0',ActiveState='failed',KillMode='process',WorkingDirectory=str(m.OLD_ROOT),
            ExecStart=str(m.OLD_ENTRY)+' run',ControlGroup=self.group)
        config=original.read_config();self.original_config=self.runtime/'original_config.json';self.write(self.original_config,config)
        source=dict(root=str(m.OLD_ROOT),head='cba0b6c861f20ebdffcd970d59b0fa38afd80a42',branch='work/pricefm-r152-parallel-recovery-20261024')
        self.master=dict(schema_version=1,stage='R152',scope_id='scope',start_epoch=1000.,started_epoch=1000.,expires_epoch=44200.,source=source,
            baseline_runtime=str(self.runtime),baseline_owner=self.owner,baseline_guardian_unit=self.guardian)
        self.write(self.shared/'master.json',self.master)
        self.state=dict(schema_version=1,scope_id='scope',attempt='original-attempt',phase='blocked',source=source,
            config_path=str(self.original_config),config_sha256=self.sha(self.original_config),new_unit=self.unit,master_sha256=self.sha(self.shared/'master.json'),
            guardian_unit=self.guardian,max_owner_generations=3,active=dict(A=dict(region='IT_CALA',phase='controller',session_id=200,
                cpus=list(range(15)),process=self.root,observed_children=[self.child])),completed=dict(A=[],B=[]),quarantined=dict(A=[],B=[]))
        self.epoch=dict(scope_id='scope',source=source,generation=1,phase='blocked',expires_epoch=44200.,owner=self.owner,guardian_unit=self.guardian)
        for path,value in [('state.json',self.state),('resource_ownership_epoch.json',self.epoch),('blocked.json',dict(self.state,error='prior protected metadata')),('owner_epochs/001.json',self.epoch),('partition_release.json',dict(original=True))]:self.write(self.runtime/path,value)
        for name in ('master_pending.json','orchestrator.json','blocked.json','terminal.json'):self.write(self.shared/name,dict(original=name))
        self.execution=dict(root=str(ROOT),head='new',branch='work/pricefm-r152-parent-recovery-20261024',runtime_sha256={})
        self.probes=[dict(path='failed-old-probe',sha256='preserved',charged_CPU_seconds=44.4537544,status='FAIL'),
            dict(path='new-probe',sha256='passed',charged_CPU_seconds=20.,status='PASS')]
        self.release_path=self.shared/'source_release.json'
        self.write(self.release_path,dict(execution_source=self.execution,original_master=self.identity()))
        self.stack=ExitStack();self.addCleanup(self.stack.close)
        for item in (patch.object(m,'SHARED',self.shared),patch.object(m,'RUNTIME',self.runtime),patch.object(m,'core',return_value=self.core),
                patch.object(m,'pool',return_value=self.pool),patch.object(m,'release_api',return_value=self.release),patch.object(m,'adapter',return_value=self.adapter)):
            self.stack.enter_context(item)

    def _write(self,path,value):
        path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
    def identity(self):return dict(path=str(self.shared/'master.json'),sha256=self.sha(self.shared/'master.json'),scope_id='scope',start_epoch=1000.,started_epoch=1000.,expires_epoch=44200.,source=self.master['source'])
    def original_master(self,identity=None,allow_expired=False):
        current=self.identity()
        if identity is not None and identity!=current:raise RuntimeError('original master differs')
        return copy.deepcopy(self.master),current
    def prepared(self):
        return m.prepare(self.release_path,['failed-old-probe','new-probe'],system=self.system)
    def staged(self,authority_path):
        auth=self.read(authority_path);state=self.read(self.runtime/'state.json')
        state.update(phase='running',new_unit=auth['new_unit'],config_path=auth['config_path'],config_sha256=auth['config_sha256'],
            owner_recovery_authority_path=authority_path,owner_recovery_authority_sha256=self.sha(authority_path),execution_control_source=auth['execution_source'])
        self.write(self.runtime/'state.json',state);return auth

    def test_exact_archives_and_no_current_state_change_during_prepare(self):
        paths=[self.runtime/name for name in ('blocked.json','state.json','resource_ownership_epoch.json')]
        before={str(path):path.read_bytes() for path in paths};master=(self.shared/'master.json').read_bytes()
        result=self.prepared();authority=self.read(result['authority_path'])
        for name in ('state','epoch','blocked','config'):
            row=authority['snapshots'][name]
            self.assertEqual(Path(row['archive_path']).read_bytes(),Path(row['original_path']).read_bytes())
        self.assertEqual(before,{str(path):path.read_bytes() for path in paths});self.assertEqual((self.shared/'master.json').read_bytes(),master)
        self.assertEqual(authority['expected_generation'],2);self.assertEqual(authority['probe_receipts'],self.probes)
        self.assertEqual(self.system.started,[]);self.assertEqual(self.system.stopped,[])

    def test_new_config_changes_only_unit_and_delegation_is_literal(self):
        result=self.prepared();auth=self.read(result['authority_path']);config=self.read(auth['config_path'])
        expected=self.read(self.original_config);expected['new_unit']=auth['new_unit']
        self.assertEqual(config,expected)
        argv=auth['control_intent']['argv'];self.assertEqual(argv[argv.index('--delegated-entry')+1],str(m.OLD_ENTRY))
        self.assertIn(str(m.OWNER),argv)

    def test_old_model_cgroup_may_remain_occupied_without_signals(self):
        result=self.prepared();proof=self.read(result['authority_path'])['predecessor_proof']
        self.assertEqual(proof['preserved_live_old_group_members'],[200,201]);self.assertEqual(proof['numerical_worker_signals'],0)
        self.assertEqual(self.system.stopped,[])

    def test_unclassified_old_cgroup_member_blocks_adoption(self):
        self.system.procs[300]=process(300,['unknown'],list(range(15)));self.system.groups[self.group].append(300)
        with self.assertRaisesRegex(RuntimeError,'unclassified'):self.prepared()

    def test_live_original_owner_or_guardian_blocks_adoption(self):
        self.system.procs[100]=copy.deepcopy(self.owner)
        with self.assertRaisesRegex(RuntimeError,'owner is still live'):self.prepared()
        self.system.procs.pop(100);self.system.props[self.guardian]=dict(MainPID='400',ActiveState='active',ControlGroup='/user.slice/test/'+self.guardian)
        with self.assertRaisesRegex(RuntimeError,'guardian is still live'):self.prepared()

    def test_new_cached_claim_blocks_initial_baseline_recovery(self):
        self.write(self.shared/'development/admissions/EE/EE-C1/lease.json',dict(claim=True))
        with self.assertRaisesRegex(RuntimeError,'no cached admissions'):self.prepared()

    def test_archive_hash_and_original_scope_bytes_are_enforced(self):
        result=self.prepared();auth=self.read(result['authority_path'])
        Path(auth['snapshots']['blocked']['archive_path']).write_text('{}')
        with self.assertRaisesRegex(RuntimeError,'snapshot changed'):m.validate_authority(result['authority_path'],system=self.system,require_staged=False)

    def test_root_failure_receipt_remains_immutable(self):
        result=self.prepared();self.write(self.shared/'blocked.json',dict(changed=True))
        with self.assertRaisesRegex(RuntimeError,'immutable scope receipt'):m.validate_authority(result['authority_path'],system=self.system,require_staged=False)

    def test_staged_validator_allows_later_cached_claims_without_reopening_them(self):
        result=self.prepared();auth=self.staged(result['authority_path'])
        self.write(self.shared/'development/admissions/EE/EE-C1/lease.json',dict(existing=True))
        self.assertEqual(m.validate_authority(result['authority_path'],system=self.system)['new_unit'],auth['new_unit'])

    def test_configuration_change_beyond_unit_is_rejected(self):
        result=self.prepared();auth=self.read(result['authority_path']);config=self.read(auth['config_path']);config['fit_max_iter']=301;self.write(auth['config_path'],config)
        with self.assertRaises(RuntimeError):m.validate_authority(result['authority_path'],system=self.system,require_staged=False)

    def _publish_after_handshake(self,path,value):
        result=self.release.immutable(path,value)
        if Path(path).name=='controller_attestation.json':self.system.publish_generation_two()
        return result

    def test_launch_handshake_adopts_generation_two_and_preserves_fit_sessions(self):
        result=self.prepared();before=copy.deepcopy(self.system.procs);master=(self.shared/'master.json').read_bytes()
        with patch.object(m,'immutable',side_effect=self._publish_after_handshake):
            receipt=m.launch(result['authority_path'],system=self.system)
        self.assertEqual(receipt['status'],'R152_BASELINE_OWNER_ADOPTED_GENERATION_TWO')
        self.assertEqual(self.read(self.runtime/'resource_ownership_epoch.json')['generation'],2)
        for pid in (200,201):self.assertEqual(self.system.procs[pid],before[pid])
        self.assertEqual(self.system.stopped,[]);self.assertEqual((self.shared/'master.json').read_bytes(),master)
        self.assertEqual(self.read(self.runtime/'state.json')['active'],self.state['active'])
        self.adapter.verify_baseline.assert_called_once()

    def test_failed_new_owner_check_stops_only_new_process_and_never_rolls_back(self):
        result=self.prepared();self.adapter.verify_baseline.side_effect=RuntimeError('new health failure')
        with patch.object(m,'immutable',side_effect=self._publish_after_handshake),self.assertRaisesRegex(RuntimeError,'health failure'):
            m.launch(result['authority_path'],system=self.system)
        auth=self.read(result['authority_path']);self.assertEqual(self.system.stopped,[auth['new_unit']])
        self.assertIn(200,self.system.procs);self.assertIn(201,self.system.procs)
        failure=self.read(Path(result['authority_path']).parent/'launch_failure.json')
        self.assertFalse(failure['state_rollback_attempted']);self.assertFalse(failure['old_baseline_unit_stopped'])
        self.assertEqual(self.read(self.runtime/'state.json')['new_unit'],auth['new_unit'])
        self.assertEqual(self.system.state_phase_at_stop,'blocked')
        self.assertTrue(failure['current_owner_marked_blocked_before_stop'])
        self.assertTrue((Path(result['authority_path']).parent/'launch_failure_current_state.json').exists())

    def test_partial_guardian_start_failure_blocks_before_owner_exit(self):
        result=self.prepared()
        def partial_guardian_failure(path,value):
            answer=self._publish_after_handshake(path,value)
            if Path(path).name=='controller_attestation.json':
                self.system.props['new-guardian']=dict(MainPID='600',ActiveState='active')
                state=self.read(self.runtime/'state.json');state['error']='guardian first-exec failure';self.write(self.runtime/'state.json',state)
            return answer
        self.adapter.verify_baseline.side_effect=RuntimeError('partial guardian startup')
        with patch.object(m,'immutable',side_effect=partial_guardian_failure),self.assertRaisesRegex(RuntimeError,'partial guardian'):
            m.launch(result['authority_path'],system=self.system)
        self.assertEqual(self.system.state_phase_at_stop,'blocked')
        self.assertEqual(self.read(self.runtime/'state.json')['active'],self.state['active'])
        self.assertNotIn(self.unit,self.system.stopped)

    def test_duplicate_preparation_and_launch_are_rejected(self):
        result=self.prepared()
        with self.assertRaisesRegex(RuntimeError,'already claimed'):self.prepared()
        with patch.object(m,'immutable',side_effect=self._publish_after_handshake):m.launch(result['authority_path'],system=self.system)
        with self.assertRaises(RuntimeError):m.launch(result['authority_path'],system=self.system)


if __name__=='__main__':unittest.main()
