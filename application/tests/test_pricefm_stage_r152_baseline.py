"""Focused resource-boundary faults; no model, benchmark or live service runs."""
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import types
import unittest
from unittest.mock import patch

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'
spec=importlib.util.spec_from_file_location('r152_baseline',ENTRY)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


def proc(pid,argv=None,cpus=None,session=None):
    return dict(pid=pid,start_ticks=pid*100,boot_id='test-boot',cmdline_sha256='cmd-'+str(pid),
        cwd=str(m.ROOT),argv=argv or [str(ENTRY),'run'],state='S',
        cpus=cpus or list(range(30)),session_id=session or pid,cgroups=['/test/'+str(pid)])


class FakeSystem:
    boot_id='test-boot'
    def __init__(self):
        self.procs={}; self.props={}; self.groups={}; self.stopped=[]; self.started=[]; self.next_pid=10000
    def host(self): return 'muscat'
    def process(self,pid): return copy.deepcopy(self.procs.get(int(pid)))
    def processes(self): return copy.deepcopy(list(self.procs.values()))
    def unit(self,name):
        return copy.deepcopy(self.props.get(name,dict(Id=name,LoadState='not-found',MainPID='0',
            ActiveState='inactive',SubState='dead',ControlGroup='')))
    def units(self): return list(self.props)
    def members(self,path): return list(self.groups.get(path,[]))
    def stop(self,name):
        self.stopped.append(name); unit=self.props[name]; oldpid=int(unit.get('MainPID',0))
        self.procs.pop(oldpid,None); self.groups[unit.get('ControlGroup','')]=[]
        unit.update(MainPID='0',ActiveState='inactive',SubState='dead')
    def start(self,name): self.started.append(name)
    def sleep(self,seconds): pass
    def launch(self,argv,env,log,cpus):
        self.next_pid+=1; pid=self.next_pid
        self.procs[pid]=proc(pid,list(argv),list(cpus),pid)
        return type('Popen',(),{'pid':pid})()


class BaselineBoundary(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.path=Path(self.temp.name); self.shared=self.path/'scope'; self.runtime=self.shared/'baseline'
        self.runtime.mkdir(parents=True)
        self.config=m.read_config(); self.config['data']=str(self.path/'data')
        self.config['legacy_locks']=[str(self.path/'old1.lock'),str(self.path/'old2.lock')]
        for name in self.config['legacy_locks']: Path(name).touch()
        self.system=FakeSystem(); self.owner=proc(os.getpid()); self.system.procs[os.getpid()]=self.owner
        self.source=dict(root=str(m.ROOT),head='new-head',branch=self.config['required_branch'])

    def write(self,path,value): m.atomic(path,value); return path

    def block(self):
        return dict(status='blocked',host='muscat',active={},source={'head':self.config['source_head']},
            failures=[dict(slot='slot_a',region='AT'),dict(slot='slot_b',region='LT')])

    def old_controls(self):
        name=self.config['legacy_handoff_unit']
        self.system.props[name]=dict(Id=name,MainPID='0',WorkingDirectory=self.config['legacy_worktree'],
            ExecStart=self.config['legacy_entry']+' run --runtime '+self.config['old_runtime'],
            KillMode='process',Restart='on-failure',ActiveState='activating',ControlGroup='',InvocationID='old')
        guardian=self.config['legacy_guardian_prefix']+'test.service'
        argv=[self.config['legacy_entry'],'guard','--attempt',self.config['old_attempt'],
            '--runtime',self.config['old_runtime'],'--config',self.config['legacy_config']]
        value=proc(200,argv); value['cwd']=self.config['legacy_worktree']; value['cgroups']=['/guard']
        self.system.procs[200]=value
        self.system.props[guardian]=dict(Id=guardian,MainPID='200',ActiveState='active',ControlGroup='/guard',
            WorkingDirectory=self.config['legacy_worktree'],InvocationID='guardian-a')
        self.system.groups['/guard']=[200]
        return guardian

    def runtime_fixture(self):
        config_path=self.write(self.path/'config.json',self.config)
        now=time.time(); master=dict(scope_id='scope',started_epoch=now-10,start_epoch=now-10,
            expires_epoch=now+43200-10,source_head=self.source['head'],source=self.source,
            partition=self.config['partition'])
        self.write(self.shared/'master.json',master)
        guardian='pricefm-r152-baseline-guardian-test.service'
        gp=proc(201,[str(ENTRY),'guard','--runtime',str(self.runtime),'--attempt','attempt',
            '--unit',self.config['new_unit']])
        self.system.procs[201]=gp
        self.system.props[guardian]=dict(MainPID='201',ActiveState='active',WorkingDirectory=str(m.ROOT),
            KillMode='process',Restart='no',ControlGroup=gp['cgroups'][0])
        self.system.props[self.config['new_unit']]=dict(MainPID=str(os.getpid()),KillMode='process',
            WorkingDirectory=str(m.ROOT),ExecStart=str(ENTRY)+' run')
        state=dict(scope_id='scope',attempt='attempt',source=self.source,phase='running',
            guardian_unit=guardian,max_owner_generations=3,active={},config_path=str(config_path),
            config_sha256=m.sha(config_path),new_unit=self.config['new_unit'])
        self.write(self.runtime/'state.json',state)
        self.write(self.runtime/'partition_release.json',dict(scope_id='scope',master_sha256=m.sha(self.shared/'master.json'),
            expires_epoch=master['expires_epoch']))
        m.publish_owner(self.runtime,state,self.system,master)
        return state,master

    def drained_fixture(self,master):
        self.write(self.shared/'development/drained.json',dict(scope_id=master['scope_id'],
            master_sha256=m.sha(self.shared/'master.json'),cleanup_verified=True,owned_pids=[],
            source_head=self.source['head'],owned_units=[],cleanup=[]))

    def armed_fixture(self):
        parent=proc(400);self.system.procs[400]=parent
        self.system.props['master.service']=dict(MainPID='400',InvocationID='v1')
        pending=dict(scope_id='scope',source=self.source,precommit_expires_epoch=time.time()+300,
            orchestrator=dict(unit='master.service',process=parent,invocation_id='v1'))
        state=dict(scope_id='scope',attempt='attempt',source=self.source,phase='armed',
            guardian_unit='guardian.service',max_owner_generations=3)
        self.write(self.runtime/'state.json',state);m.publish_owner(self.runtime,state,self.system)
        return state,pending

    def fake_commit(self,pending,shared_runtime,partition_release_fields):
        start=time.time()
        value=dict(pending,**partition_release_fields,started_epoch=start,start_epoch=start,expires_epoch=start+43200)
        self.write(Path(shared_runtime)/'master.json',value);return value

    def test_census_skips_foreign_UID_before_process_read(self):
        system=object.__new__(m.System);system.boot_id='test-boot'
        with patch.object(m.Path,'iterdir',return_value=iter([Path('/proc/123')])),\
                patch.object(m.Path,'stat',return_value=types.SimpleNamespace(st_uid=os.getuid()+1)),\
                patch.object(system,'process',side_effect=PermissionError('foreign metadata')) as inspect:
            self.assertEqual(system.processes(),[]);inspect.assert_not_called()

    def test_census_skips_protected_foreign_metadata_with_own_directory_UID(self):
        system=object.__new__(m.System);system.boot_id='test-boot'
        def ownership(path,*args,**kwargs):
            return types.SimpleNamespace(st_uid=0 if path.name=='cmdline' else os.getuid())
        def metadata(path,*args,**kwargs):
            return '123 ((sd-pam)) S 1 1 1\n' if path.name=='stat' else '(sd-pam)\n'
        with patch.object(m.Path,'iterdir',return_value=iter([Path('/proc/123')])),\
                patch.object(m.Path,'stat',new=ownership),\
                patch.object(m.Path,'read_text',new=metadata),\
                patch.object(m.Path,'read_bytes',side_effect=PermissionError('protected cmdline')) as read:
            self.assertEqual(system.processes(),[]);read.assert_not_called()

    def test_protected_terminal_process_is_skipped_before_metadata_access(self):
        system=object.__new__(m.System);system.boot_id='test-boot'
        def ownership(path,*args,**kwargs):
            if path.name!='2096340':raise AssertionError('terminal protected metadata was accessed')
            return types.SimpleNamespace(st_uid=os.getuid())
        for state in ('Z','X','x'):
            with self.subTest(state=state),\
                    patch.object(m.Path,'iterdir',return_value=iter([Path('/proc/2096340')])),\
                    patch.object(m.Path,'stat',new=ownership),\
                    patch.object(m.Path,'read_text',return_value='2096340 (xargs) '+state+' 1 1 1\n'),\
                    patch.object(system,'process',side_effect=PermissionError('terminal protected cwd')) as inspect:
                self.assertEqual(system.processes(),[]);inspect.assert_not_called()

    def test_members_observes_exact_v1_and_v2_cgroups_with_descendants(self):
        system=object.__new__(m.System)
        for hierarchy in ('v1','v2'):
            with self.subTest(hierarchy=hierarchy):
                base=self.path/hierarchy
                group=(base/'systemd' if hierarchy=='v1' else base)/'user.slice/owned.service'
                (group/'child').mkdir(parents=True)
                (group/'cgroup.procs').write_text('17\n19\n17\n');(group/'child/cgroup.procs').write_text('23\n')
                def mapped(path):
                    if str(path)=='/sys/fs/cgroup':return base
                    if str(path)=='/sys/fs/cgroup/systemd':return base/'systemd'
                    return Path(path)
                with patch.object(m,'Path',side_effect=mapped):
                    self.assertEqual(system.members('/user.slice/owned.service'),[17,19,23])

    def test_ambiguous_v1_v2_membership_blocks_drain_proof(self):
        system=object.__new__(m.System);base=self.path/'cgroup'
        for group in (base/'user.slice/owned.service',base/'systemd/user.slice/owned.service'):
            group.mkdir(parents=True);(group/'cgroup.procs').write_text('17\n')
        def mapped(path):
            if str(path)=='/sys/fs/cgroup':return base
            if str(path)=='/sys/fs/cgroup/systemd':return base/'systemd'
            return Path(path)
        with patch.object(m,'Path',side_effect=mapped):
            with self.assertRaisesRegex(RuntimeError,'ambiguous'):system.members('/user.slice/owned.service')

    def test_persistent_partial_cgroup_visibility_cannot_prove_empty(self):
        system=object.__new__(m.System);base=self.path/'cgroup';group=base/'systemd/user.slice/owned.service'
        group.mkdir(parents=True);(group/'cgroup.procs').write_text('17\n')
        def mapped(path):
            if str(path)=='/sys/fs/cgroup':return base
            if str(path)=='/sys/fs/cgroup/systemd':return base/'systemd'
            return Path(path)
        with patch.object(m,'Path',side_effect=mapped),\
                patch.object(Path,'read_text',side_effect=FileNotFoundError('draining descendant')) as read:
            with self.assertRaisesRegex(RuntimeError,'after3 snapshots'):system.members('/user.slice/owned.service')
            self.assertEqual(read.call_count,3)

    def test_disappeared_cgroup_is_empty_after_bounded_read_race(self):
        system=object.__new__(m.System);base=self.path/'cgroup';group=base/'systemd/user.slice/owned.service'
        group.mkdir(parents=True);(group/'cgroup.procs').write_text('17\n')
        def mapped(path):
            if str(path)=='/sys/fs/cgroup':return base
            if str(path)=='/sys/fs/cgroup/systemd':return base/'systemd'
            return Path(path)
        def vanished(path,*args,**kwargs):
            path.unlink();group.rmdir();raise FileNotFoundError('whole cgroup drained')
        with patch.object(m,'Path',side_effect=mapped),patch.object(Path,'read_text',new=vanished):
            self.assertEqual(system.members('/user.slice/owned.service'),[])

    def test_unknown_protected_own_UID_process_blocks_census(self):
        system=object.__new__(m.System);system.boot_id='test-boot'
        def ownership(path,*args,**kwargs):
            return types.SimpleNamespace(st_uid=0 if path.name=='cmdline' else os.getuid())
        def metadata(path,*args,**kwargs):
            return '123 (python) S 1 1 1\n' if path.name=='stat' else 'python\n'
        with patch.object(m.Path,'iterdir',return_value=iter([Path('/proc/123')])),\
                patch.object(m.Path,'stat',new=ownership),\
                patch.object(m.Path,'read_text',new=metadata),\
                patch.object(m.Path,'read_bytes') as read:
            with self.assertRaisesRegex(PermissionError,'unrecognized protected own-UID process'):
                system.processes()
            read.assert_not_called()

    def test_own_unreadable_process_metadata_fails_closed(self):
        system=object.__new__(m.System);system.boot_id='test-boot'
        with patch.object(m.Path,'stat',return_value=types.SimpleNamespace(st_uid=os.getuid())),\
                patch.object(m.Path,'read_bytes',side_effect=PermissionError('own cmdline')):
            with self.assertRaisesRegex(PermissionError,'own cmdline'):system.process(123)

    def test_recorded_protected_child_fails_closed_even_if_census_filters_it(self):
        child=proc(301,session=300);parent=proc(300)
        job=dict(process=parent,session_id=300,cpus=list(range(30)),observed_children=[child])
        def inspect(pid):
            if pid==301:raise PermissionError('recorded protected cwd')
            return None
        with patch.object(self.system,'process',side_effect=inspect),\
                patch.object(self.system,'processes',return_value=[]) as census:
            with self.assertRaisesRegex(PermissionError,'recorded protected cwd'):
                m.session_members(job,self.system)
            census.assert_not_called()

    def test_recorded_live_child_cannot_disappear_in_filtered_census(self):
        child=proc(301,session=300);parent=proc(300)
        job=dict(process=parent,session_id=300,cpus=list(range(30)),observed_children=[child])
        self.system.procs[301]=child
        with patch.object(self.system,'processes',return_value=[]):
            self.assertEqual(m.session_members(job,self.system),[child])

    def test_probe_census_failure_finally_drains_exact_disposable_child(self):
        with tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-',dir='/tmp') as temporary:
            folder=Path(temporary);child=proc(300);publisher=proc(200)
            job=dict(disposable=True,process=publisher,child=child,observed_children=[child],
                session_id=200,cpus=list(range(30)))
            self.system.procs[300]=child;signals=[]
            class Publisher:
                returncode=0
                def communicate(inner,timeout):
                    m.immutable(folder/'orphan_job.json',job);return '',''
            def kill(pid,number):signals.append((pid,number));self.system.procs.pop(pid,None)
            with patch.object(m,'source_identity',return_value=self.source),\
                    patch.object(m,'System',return_value=self.system),\
                    patch.object(m.tempfile,'mkdtemp',return_value=temporary),\
                    patch.object(m.subprocess,'run',return_value=types.SimpleNamespace(returncode=0)),\
                    patch.object(m.subprocess,'Popen',return_value=Publisher()),\
                    patch.object(m,'guard_once',return_value='wait'),\
                    patch.object(m,'session_members',side_effect=PermissionError('own census denied')),\
                    patch.object(m.os,'kill',side_effect=kill):
                self.system.host=lambda:'muscat'
                with self.assertRaisesRegex(PermissionError,'own census denied'):
                    m.capability_probe(self.path/'failed_probe.json')
            self.assertEqual(signals,[(300,m.signal.SIGTERM)])
            self.assertTrue(m.read(folder/'cleanup.json')['cleanup_verified'])
            self.assertFalse((self.path/'failed_probe.json').exists())

    def test_disposable_cleanup_never_signals_reused_PID(self):
        with tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-',dir='/tmp') as temporary:
            folder=Path(temporary);child=proc(300);publisher=proc(200)
            m.immutable(folder/'authority.json',dict(owner=self.owner))
            current=copy.deepcopy(child);current['start_ticks']+=1;self.system.procs[300]=current
            job=dict(disposable=True,process=publisher,child=child)
            with patch.object(m.os,'kill') as kill:
                result=m.cleanup_disposable_probe(folder,self.system,job)
            kill.assert_not_called();self.assertTrue(result['cleanup_verified'])

    def test_partition_valid_and_exactly_thirty(self):
        m.validate_config(self.config)
        sets=[set(self.config['partition'][key]) for key in ('baseline_A','baseline_B','development_base')]
        self.assertEqual(sum(map(len,sets)),30); self.assertEqual(len(set.union(*sets)),30)

    def test_partition_or_science_changes_rejected(self):
        changes=[('scope_seconds',43201),('repair_fits_authorized',True),('signal_numerical_workers',True),
            ('resume_old_R145',True),('fit_max_iter',600),('max_owner_generations',4)]
        for key,value in changes:
            with self.subTest(key=key):
                config=copy.deepcopy(self.config); config[key]=value
                with self.assertRaises(RuntimeError):m.validate_config(config)

    def test_unreviewed_cpu_or_queue_change_rejected(self):
        for field,value in [('partition',dict(self.config['partition'],development_base=list(range(30,36)))),
                ('queues',dict(self.config['queues'],B=['LT','NO_2','PL','SE_2']))]:
            config=copy.deepcopy(self.config); config[field]=value
            with self.assertRaises(RuntimeError):m.validate_config(config)

    def test_only_exact_mixed_failure_boundary_accepted(self):
        m.validate_block(self.block(),self.config)
        for mutation in ('missing','extra','active','source','slot','host'):
            value=self.block()
            if mutation=='missing':value['failures'].pop()
            elif mutation=='extra':value['failures'].append(dict(slot='slot_b',region='PL'))
            elif mutation=='active':value['active']={'slot_a':'FI'}
            elif mutation=='source':value['source']['head']='other'
            elif mutation=='slot':value['failures'][1]['slot']='slot_a'
            else:value['host']='jerez'
            with self.subTest(mutation=mutation),self.assertRaises(RuntimeError):m.validate_block(value,self.config)

    def test_duplicate_failure_pair_rejected(self):
        value=self.block();value['failures']=[value['failures'][0]]*2
        with self.assertRaises(RuntimeError):m.validate_block(value,self.config)

    def test_dispatch_fences_release_acquired_subset_when_busy(self):
        held=Path(self.config['legacy_locks'][1]).open('a+')
        fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            with self.assertRaises(BlockingIOError):
                with m.fences(self.runtime,self.config):pass
            with Path(self.config['legacy_locks'][0]).open('a+') as free:
                fcntl.flock(free,fcntl.LOCK_EX|fcntl.LOCK_NB)
        finally:held.close()
        with m.fences(self.runtime,self.config):pass

    def test_changed_lock_inode_rejected(self):
        expected=[]
        for name in self.config['legacy_locks']:
            st=Path(name).stat();expected.append(dict(path=name,device=st.st_dev,inode=st.st_ino))
        original=Path(self.config['legacy_locks'][0]);original.rename(original.with_suffix('.old'));original.touch()
        with self.assertRaises(RuntimeError):
            with m.fences(self.runtime,self.config,expected):pass

    def test_symlink_lock_rejected(self):
        path=Path(self.config['legacy_locks'][0]);path.unlink();path.symlink_to(self.path/'target')
        with self.assertRaises(RuntimeError):
            with m.fences(self.runtime,self.config):pass

    def test_only_exact_legacy_controls_stopped(self):
        guardian=self.old_controls()
        receipt=m.quiesce_legacy(self.config,self.system,{'worker_free':True})
        self.assertEqual(self.system.stopped,[self.config['legacy_handoff_unit'],guardian])
        self.assertEqual(self.system.started,[])
        self.assertEqual(receipt['numerical_worker_signals'],0)

    def test_live_numerical_child_prevents_control_cutover(self):
        self.old_controls();self.system.procs[300]=proc(300,[self.config['source_controller'],'worker'])
        with self.assertRaises(RuntimeError):m.quiesce_legacy(self.config,self.system,{'worker_free':True})
        self.assertEqual(self.system.stopped,[])

    def test_wrong_guardian_attempt_is_never_stopped(self):
        name=self.old_controls();self.system.procs[200]['argv'][3]='another-attempt'
        with self.assertRaises(RuntimeError):m.quiesce_legacy(self.config,self.system,{'worker_free':True})
        self.assertEqual(self.system.stopped,[])

    def test_changed_handoff_service_is_never_stopped(self):
        self.old_controls();self.system.props[self.config['legacy_handoff_unit']]['KillMode']='control-group'
        with self.assertRaises(RuntimeError):m.quiesce_legacy(self.config,self.system,{'worker_free':True})
        self.assertEqual(self.system.stopped,[])

    def test_guardian_exit_between_unit_and_process_reads_requires_drain(self):
        guardian=self.old_controls();self.system.procs.pop(200)
        original=self.system.unit;seen={'count':0}
        def unit(name):
            value=original(name)
            if name==guardian:
                seen['count']+=1
                if seen['count']>1:
                    value.update(MainPID='0',ActiveState='inactive');self.system.groups['/guard']=[]
            return value
        with patch.object(self.system,'unit',side_effect=unit):
            self.assertEqual(m.legacy_guardians(self.config,self.system),[])
        self.system.props[guardian].update(MainPID='200',ActiveState='active')
        self.system.groups['/guard']=[999]
        with self.assertRaises(RuntimeError):m.legacy_guardians(self.config,self.system)

    def test_immutable_receipt_cannot_be_rewritten(self):
        path=self.path/'seal.json';m.immutable(path,{'a':1});m.immutable(path,{'a':1})
        with self.assertRaises(RuntimeError):m.immutable(path,{'a':2})

    def test_packet_tamper_and_escape_rejected(self):
        folder=self.path/'packet';folder.mkdir();(folder/'value').write_text('retained')
        self.write(folder/'completed_evidence.json',{'artifacts':{'value':m.sha(folder/'value')}})
        m.verify_packet(folder)
        (folder/'value').write_text('changed')
        with self.assertRaises(RuntimeError):m.verify_packet(folder)
        outside=self.path/'outside';outside.write_text('x')
        self.write(folder/'completed_evidence.json',{'artifacts':{'../outside':m.sha(outside)}})
        with self.assertRaises(RuntimeError):m.verify_packet(folder)

    def test_original_controller_command_and_scope(self):
        argv=m.command(self.config,'NO_2','controller',list(range(15,24)))
        self.assertIn(self.config['source_controller'],argv)
        self.assertEqual(argv[-2:],['--cpus','15,16,17,18,19,20,21,22,23'])
        self.assertIn('9',argv)
        for region in ('AT','LT','LV'):
            with self.assertRaises(RuntimeError):m.command(self.config,region,'controller',list(range(15)))

    def test_orphan_session_is_adopted_without_duplicate_launch(self):
        parent=proc(300,cpus=list(range(15,24)));child=proc(301,cpus=[16],session=300)
        job=dict(process=parent,session_id=300,cpus=list(range(15,24)),observed_children=[child])
        self.system.procs[301]=child
        self.assertEqual(m.session_members(job,self.system),[child])
        state=dict(active={'B':dict(job,region='NO_2',phase='controller')},completed={'A':[],'B':[]},quarantined={'A':[],'B':[]})
        # Guard the active B job separately; source must not invent its death because root PID is gone.
        self.assertTrue(m.session_members(state['active']['B'],self.system))

    def test_reused_child_pid_and_partition_escape_rejected(self):
        expected=proc(300,cpus=list(range(15,24)))
        self.system.procs[300]=dict(expected,start_ticks=1)
        with self.assertRaises(RuntimeError):m.session_members(dict(process=expected,session_id=300,cpus=list(range(15,24))),self.system)

    def test_unknown_orphan_is_not_adopted_from_session_id_alone(self):
        expected=proc(300,cpus=list(range(15,24)))
        self.system.procs[301]=proc(301,cpus=[16],session=300)
        with self.assertRaises(RuntimeError):
            m.session_members(dict(process=expected,session_id=300,cpus=list(range(15,24))),self.system)

    def test_known_Rscript_exec_preserves_exact_contract_role(self):
        script='/source/470_fit_pricefm_stage_r137_certified_al_300.R'
        expected=proc(301,['Rscript',script,'--config','/data/task.json'],[16],300)
        current=dict(expected,argv=['R','--file='+script,'--args','--config','/data/task.json'],cmdline_sha256='native')
        self.assertTrue(m.same_owned_child(current,expected))
        current['argv'][-1]='/data/different.json'
        self.assertFalse(m.same_owned_child(current,expected))
        self.system.procs.clear();self.system.procs[301]=proc(301,cpus=[24],session=300)
        with self.assertRaises(RuntimeError):m.session_members(dict(process=expected,session_id=300,cpus=list(range(15,24))),self.system)

    def test_master_ownership_and_guardian_epoch(self):
        state,master=self.runtime_fixture()
        value=m.baseline_ownership(self.runtime,master,self.system)
        self.assertEqual(value['generation'],1)
        self.assertEqual(value['guardian']['pid'],201)

    def test_stale_owner_epoch_fails_cached_guard(self):
        state,master=self.runtime_fixture();epoch=m.read(self.runtime/'resource_ownership_epoch.json')
        epoch['heartbeat']=time.time()-181;self.write(self.runtime/'resource_ownership_epoch.json',epoch)
        with self.assertRaises(RuntimeError):m.baseline_ownership(self.runtime,master,self.system)

    def test_mismatched_master_or_guardian_fails_cached_guard(self):
        state,master=self.runtime_fixture();self.system.procs[201]['argv']=[str(ENTRY),'guard','another-attempt']
        with self.assertRaises(RuntimeError):m.baseline_ownership(self.runtime,master,self.system)

    def test_owner_recovery_preserves_sealed_predecessor(self):
        state,master=self.runtime_fixture();old=m.read(self.runtime/'owner_epochs/001.json')
        self.system.procs[os.getpid()]['start_ticks']+=1
        epoch=m.publish_owner(self.runtime,state,self.system,master)
        self.assertEqual(epoch['generation'],2)
        self.assertEqual(epoch['predecessor_sha256'],m.sha(self.runtime/'owner_epochs/001.json'))
        self.assertEqual(m.read(self.runtime/'owner_epochs/001.json'),old)

    def test_owner_recovery_is_bounded(self):
        state,master=self.runtime_fixture()
        for _ in range(2):
            self.system.procs[os.getpid()]['start_ticks']+=1;m.publish_owner(self.runtime,state,self.system,master)
        self.system.procs[os.getpid()]['start_ticks']+=1
        with self.assertRaises(RuntimeError):m.publish_owner(self.runtime,state,self.system,master)

    def test_completed_terminal_is_idempotent_across_owner_restart(self):
        state,master=self.runtime_fixture()
        state.update(completed={'A':list(m.A_QUEUE),'B':list(m.B_QUEUE)},
            quarantined={'A':[],'B':[]},master_sha256=m.sha(self.shared/'master.json'))
        first=m.seal_terminal(self.runtime,state,self.source)
        before=(self.runtime/'terminal.json').read_bytes()
        with patch.object(m.time,'time',return_value=time.time()+500):
            second=m.seal_terminal(self.runtime,state,self.source)
        self.assertEqual(first,second);self.assertEqual(before,(self.runtime/'terminal.json').read_bytes())
        state['completed']['A'].pop()
        with self.assertRaises(RuntimeError):m.seal_terminal(self.runtime,state,self.source)

    def test_guard_waits_for_live_exact_owner(self):
        state,master=self.runtime_fixture()
        self.assertEqual(m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system),'wait')
        self.assertEqual(self.system.started,[])

    def test_guard_never_revives_old_R145(self):
        state,master=self.runtime_fixture();self.system.procs.pop(os.getpid())
        self.system.props[self.config['new_unit']].update(ActiveState='inactive',Restart='on-failure')
        m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system)
        self.assertEqual(self.system.started,[self.config['new_unit']])

    def test_guard_does_not_duplicate_live_stale_owner(self):
        state,master=self.runtime_fixture();epoch=m.read(self.runtime/'resource_ownership_epoch.json')
        self.assertEqual(m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system,now=epoch['heartbeat']+181),'blocked')
        self.assertEqual(self.system.started,[])

    def test_guard_precommit_death_never_starts_any_supervisor(self):
        state,master=self.runtime_fixture();state['phase']='armed';self.write(self.runtime/'state.json',state)
        self.system.procs.pop(os.getpid())
        self.assertEqual(m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system),'blocked')
        self.assertEqual(self.system.started,[])

    def test_complete_baseline_keeps_guardian_until_loan_finishes(self):
        state,master=self.runtime_fixture();state['phase']='complete';self.write(self.runtime/'state.json',state)
        self.assertEqual(m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system),'wait')
        self.assertEqual(m.guard_once(self.config,self.runtime,self.shared,'attempt',self.system,now=master['expires_epoch']+1),'complete')

    def test_expiry_without_cleanup_does_not_expand_B(self):
        state,master=self.runtime_fixture();master['expires_epoch']=time.time()-1
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,24)))

    def test_expiry_plus_verified_cleanup_allows_next_B_region(self):
        state,master=self.runtime_fixture();master['expires_epoch']=time.time()-1
        self.drained_fixture(master)
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,30)))

    def test_cleanup_receipt_missing_unit_coverage_rejected(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        path=self.shared/'development/drained.json';value=m.read(path);value['owned_units']=['uncovered'];self.write(path,value)
        self.assertFalse(m.cached_drained(self.shared,master,self.system))

    def test_live_cached_child_prevents_B_restoration(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        self.system.procs[300]=proc(300,['/test/500_run_pricefm.py','worker','--policy-receipt',str(self.shared/'development/policy.json')],cpus=[24])
        self.assertFalse(m.cached_drained(self.shared,master,self.system))

    def test_cached_drain_independently_checks_old_worker_lifetime(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        worker=proc(300,['python','-B','/source/payload.py'],cpus=[24])
        self.write(self.shared/'development/attempts/EE/abc/ownership.json',dict(
            unit='worker.service',process=worker,expected_cgroup='/worker'))
        receipt=self.shared/'development/drained.json';value=m.read(receipt)
        # A receipt omitting a registered worker cannot return the loan.
        self.assertFalse(m.cached_drained(self.shared,master,self.system))
        value.update(owned_units=['worker.service'],cleanup=[dict(unit='worker.service',
            drained=True,pids=[],expected_cgroup='/worker')]);self.write(receipt,value)
        # Even inactive/empty unit metadata cannot hide the original live PID.
        self.system.procs[300]=worker
        self.assertFalse(m.cached_drained(self.shared,master,self.system))
        self.system.procs[300]['start_ticks']+=1
        self.assertTrue(m.cached_drained(self.shared,master,self.system))

    def test_worker_drain_alone_does_not_release_live_cached_controller(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        controller=proc(300,cpus=list(range(15,30)))
        self.write(self.shared/'development/controller.json',dict(unit='pool.service',process=controller,expected_cgroup='/pool'))
        self.system.procs[300]=controller
        self.system.props['pool.service']=dict(MainPID='300',ActiveState='active',ControlGroup='/pool')
        self.system.groups['/pool']=[300]
        self.assertFalse(m.cached_drained(self.shared,master,self.system))
        self.system.procs.pop(300);self.system.props['pool.service'].update(MainPID='0',ActiveState='inactive')
        self.system.groups['/pool']=[]
        self.assertTrue(m.cached_drained(self.shared,master,self.system))

    def test_live_early_closure_publisher_blocks_loan_return(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        self.write(self.shared/'development/final_drained.json',m.read(self.shared/'development/drained.json'))
        terminal=self.write(self.shared/'development/terminal.json',{'status':'closed'})
        publisher=proc(400,cpus=list(range(15,30)))
        self.write(self.shared/'orchestrator.json',dict(capsule=dict(unit='master.service',
            process=publisher,expected_cgroup='/master')))
        self.system.procs[400]=publisher
        self.system.props['master.service']=dict(MainPID='400',ActiveState='active',ControlGroup='/master')
        self.system.groups['/master']=[400]
        self.write(self.shared/'development_closed.json',dict(scope_id=master['scope_id'],
            master_sha256=m.sha(self.shared/'master.json'),source_head=self.source['head'],
            future_admissions_closed=True,cleanup_verified=True,terminal_sha256=m.sha(terminal),
            final_drained_sha256=m.sha(self.shared/'development/final_drained.json')))
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,24)))
        self.assertFalse((self.runtime/'loan_return_verified.json').exists())
        self.system.procs.pop(400);self.system.props['master.service'].update(MainPID='0',ActiveState='inactive')
        self.system.groups['/master']=[]
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,30)))
        self.assertTrue(m.read(self.runtime/'loan_return_verified.json')['publisher_actual_drain_checked'])

    def test_early_return_requires_closed_admissions_and_sealed_terminal(self):
        state,master=self.runtime_fixture();self.drained_fixture(master)
        self.write(self.shared/'development/final_drained.json',m.read(self.shared/'development/drained.json'))
        terminal=self.write(self.shared/'development/terminal.json',{'status':'closed'})
        closed=dict(scope_id=master['scope_id'],master_sha256=m.sha(self.shared/'master.json'),
            source_head=self.source['head'],future_admissions_closed=True,cleanup_verified=True,terminal_sha256=m.sha(terminal),
            final_drained_sha256=m.sha(self.shared/'development/final_drained.json'))
        self.write(self.shared/'development_closed.json',closed)
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,30)))
        with self.assertRaises(RuntimeError):m.baseline_ownership(self.runtime,master,self.system)
        closed['future_admissions_closed']=False;self.write(self.shared/'development_closed.json',closed)
        self.assertEqual(m.choose_cpus(self.config,'B',self.shared,master,self.system),list(range(15,24)))

    def test_precommit_clock_and_actual_orchestrator_are_required(self):
        parent=proc(400);self.system.procs[400]=parent
        self.system.props['master.service']=dict(MainPID='400',InvocationID='v1')
        pending=dict(precommit_expires_epoch=time.time()+300,orchestrator=dict(unit='master.service',process=parent,invocation_id='v1'))
        m.pending_gate(pending,self.system,45)
        self.system.props['master.service']['InvocationID']='v2'
        with self.assertRaises(RuntimeError):m.pending_gate(pending,self.system)

    def test_one_clock_is_published_before_any_dispatch(self):
        state,pending=self.armed_fixture()
        master=m.commit_scope(self.config,self.runtime,self.shared,state,pending,self.system,self.fake_commit)
        release=m.read(self.runtime/'partition_release.json')
        self.assertEqual(release['start_epoch'],master['start_epoch'])
        self.assertEqual(release['expires_epoch'],master['expires_epoch'])
        self.assertEqual(release['master_sha256'],m.sha(self.shared/'master.json'))
        self.assertEqual(state['phase'],'running');self.assertEqual(self.system.next_pid,10000)
        self.assertEqual(m.read(self.runtime/'owner_epochs/001.json')['expires_epoch'],master['expires_epoch'])

    def test_parent_death_prevents_atomic_commit(self):
        state,pending=self.armed_fixture();self.system.procs.pop(400)
        callback=unittest.mock.Mock()
        with self.assertRaises(RuntimeError):
            m.commit_scope(self.config,self.runtime,self.shared,state,pending,self.system,callback)
        callback.assert_not_called();self.assertFalse((self.shared/'master.json').exists())

    def test_crash_after_master_publication_recovers_original_clock(self):
        state,pending=self.armed_fixture();original_owner=self.system.process(os.getpid())
        master=self.fake_commit(pending,self.shared,dict(partition=self.config['partition'],
            baseline_owner=original_owner,baseline_runtime=str(self.runtime.resolve()),baseline_guardian_unit=state['guardian_unit']))
        before=(self.shared/'master.json').read_bytes()
        self.system.procs[os.getpid()]['start_ticks']+=1
        recovered=m.recover_committed_scope(self.config,self.runtime,self.shared,state,pending,self.system)
        self.assertEqual(before,(self.shared/'master.json').read_bytes());self.assertEqual(master,recovered)
        self.assertEqual(m.publish_owner(self.runtime,state,self.system,master)['generation'],2)
        self.assertEqual(m.read(self.runtime/'owner_epochs/001.json')['owner'],original_owner)
        self.assertEqual(self.system.next_pid,10000)

    def test_different_clock_cannot_be_adopted_after_partial_commit(self):
        state,pending=self.armed_fixture()
        master=self.fake_commit(pending,self.shared,dict(partition=self.config['partition'],
            baseline_owner=self.owner,baseline_runtime=str(self.runtime.resolve()),baseline_guardian_unit=state['guardian_unit']))
        master['expires_epoch']+=1;self.write(self.shared/'master.json',master)
        with self.assertRaises(RuntimeError):
            m.recover_committed_scope(self.config,self.runtime,self.shared,state,pending,self.system)
        self.system.props['master.service']['InvocationID']='v1';pending['precommit_expires_epoch']=time.time()-1
        with self.assertRaises(RuntimeError):m.pending_gate(pending,self.system)

    def test_all_readonly_source_markers_identify_own_numerical_actions(self):
        self.assertTrue(m.numerical_process(proc(300,[self.config['source_controller'],'prepare']),self.config))
        self.assertFalse(m.numerical_process(proc(301,[str(m.ROOT/'application/scripts/pricefm/490_closeout_pricefm_stage_r146_all_region.py'),'wait']),self.config))


if __name__=='__main__':unittest.main()
