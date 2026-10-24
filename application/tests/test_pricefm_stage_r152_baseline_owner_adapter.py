"""Exit/exec races and explicit cba delegation; no services or model work."""
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch,Mock

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/511_recover_pricefm_stage_r152_baseline_owner.py'
spec=importlib.util.spec_from_file_location('r152_baseline_owner_adapter_test',ENTRY)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);c=m.core()
def stat(state='R',start=100):return dict(pid=123,state=state,start_ticks=start)
def process(pid=123,raw=b'python\0worker\0',cwd='/source',session=123):
    return dict(pid=pid,start_ticks=100,boot_id='boot',cmdline_sha256=hashlib.sha256(raw).hexdigest(),cwd=cwd,
        argv=[str(m.ENTRY),'--delegated-entry',str(m.CORE_ENTRY)],cpus=[24],session_id=session,state='R')

class BoundedProcReads(unittest.TestCase):
    def setUp(self):self.system=object.__new__(m.RecoverySystem);self.system.boot_id='boot'
    def test_permission_denial_with_fresh_terminal_proof_is_absent(self):
        for state in ('Z','X','x'):
            with self.subTest(state=state),patch.object(self.system,'stat_sample',side_effect=[stat(),stat(state)]),\
                    patch.object(c.System,'process',side_effect=PermissionError('exec transition')):
                self.assertIsNone(self.system.process(123))
    def test_permission_denial_with_fresh_gone_proof_is_absent(self):
        with patch.object(self.system,'stat_sample',side_effect=[stat(),None]),patch.object(c.System,'process',side_effect=PermissionError('exited')):
            self.assertIsNone(self.system.process(123))
    def test_stable_live_protected_direct_PID_still_fails_closed(self):
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',side_effect=PermissionError('stable denial')) as read,patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(PermissionError,'stable denial'):self.system.process(123)
            self.assertEqual(read.call_count,3)
    def test_old_core_missing_exec_metadata_is_not_live_process_absence(self):
        value=process()
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',side_effect=[None,value]) as read,\
                patch.object(Path,'read_bytes',return_value=b'python\0worker\0'),patch.object(m.os,'readlink',return_value='/source'),patch.object(m.time,'sleep'):
            self.assertEqual(self.system.process(123),value);self.assertEqual(read.call_count,2)
    def test_PID_reuse_after_metadata_reread_cannot_return_old_identity(self):
        with patch.object(self.system,'stat_sample',side_effect=[stat(),stat(),stat(start=101)]),\
                patch.object(c.System,'process',return_value=process()),patch.object(Path,'read_bytes',return_value=b'python\0worker\0'),\
                patch.object(m.os,'readlink',return_value='/source'):
            with self.assertRaisesRegex(RuntimeError,'after process metadata reread'):self.system.process(123)
    def test_exec_cmdline_change_is_reread_to_a_stable_snapshot(self):
        old=process();new=process(raw=b'R\0fit.R\0')
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',side_effect=[old,new]),\
                patch.object(Path,'read_bytes',side_effect=[b'R\0fit.R\0',b'R\0fit.R\0']),\
                patch.object(m.os,'readlink',return_value='/source'),patch.object(m.time,'sleep'):
            self.assertEqual(self.system.process(123),new)
    def test_original_session_check_retires_empty_exiting_observed_worker(self):
        parent=process(999,raw=b'python\0parent\0',session=999);parent['start_ticks']=200
        worker=process(123,session=999);empty=dict(worker,argv=[],cmdline_sha256=hashlib.sha256(b'').hexdigest())
        for mode in ('empty_value','missing_cwd','denied_cwd'):
            child_samples=iter([stat(),stat(),stat('S'),stat('Z')])
            def sample(pid):return dict(pid=999,start_ticks=200,state='R') if pid==999 else next(child_samples)
            def read(pid):
                if pid==999:return parent
                if mode=='denied_cwd':raise PermissionError('cwd released while state still R')
                return empty if mode=='empty_value' else None
            def raw(path,*args,**kwargs):return b'python\0parent\0' if path.parent.name=='999' else b''
            system=object.__new__(m.RecoverySystem);system.boot_id='boot'
            job=dict(process=parent,session_id=999,cpus=[24],observed_children=[worker]);system.seed_expected(dict(active=dict(A=job)))
            with self.subTest(mode=mode),patch.object(system,'stat_sample',side_effect=sample),patch.object(c.System,'process',side_effect=read),\
                    patch.object(Path,'read_bytes',new=raw),patch.object(m.os,'readlink',return_value='/source'),\
                    patch.object(system,'processes',return_value=[parent]),patch.object(m.time,'sleep'):
                self.assertEqual(c.session_members(job,system),[parent])
            events=[row for row in system.metadata_events if row['pid']==123]
            self.assertTrue(any(row['kind']=='EMPTY_EXIT_OR_EXEC' for row in events))
            self.assertTrue(any(row['kind']=='EMPTY_THEN_TERMINAL_OR_GONE' for row in events))
    def test_stable_live_empty_command_never_returns_a_process(self):
        value=process(raw=b'');value['argv']=[]
        self.system.seed_expected(dict(active=dict(A=dict(process=process(),observed_children=[]))))
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',return_value=value) as read,\
                patch.object(Path,'read_bytes',return_value=b''),patch.object(m.os,'readlink',return_value='/source'),patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'stable live empty command metadata') as error:self.system.process(123)
        self.assertEqual(read.call_count,21);self.assertIn('"pid": 123',str(error.exception))
        self.assertIn('old_cmdline_sha256',str(error.exception));self.assertIn('new_cmdline_sha256',str(error.exception))
    def test_empty_command_can_restore_same_lifetime_nonempty_snapshot(self):
        empty=process(raw=b'');empty['argv']=[];ready=process()
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',side_effect=[empty,ready]),\
                patch.object(Path,'read_bytes',side_effect=[b'',b'python\0worker\0']),patch.object(m.os,'readlink',return_value='/source'),patch.object(m.time,'sleep'):
            self.assertEqual(self.system.process(123),ready)
    def ownership(self,path,*args,**kwargs):return types.SimpleNamespace(st_uid=0 if path.name=='cmdline' else os.getuid())
    def test_census_live_to_protected_terminal_race_is_bounded(self):
        with patch.object(Path,'stat',new=lambda path,*a,**kw:self.ownership(path,*a,**kw)),patch.object(Path,'read_text',return_value='python\n'),\
                patch.object(self.system,'stat_sample',side_effect=[stat(),stat('Z')]),patch.object(self.system,'process') as read:
            self.assertIsNone(self.system.census_process(Path('/proc/123')));read.assert_not_called()
    def test_census_stable_live_unknown_protected_process_blocks(self):
        with patch.object(Path,'stat',new=lambda path,*a,**kw:self.ownership(path,*a,**kw)),patch.object(Path,'read_text',return_value='python\n'),\
                patch.object(self.system,'stat_sample',return_value=stat()) as sample,patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(PermissionError,'stable live protected'):self.system.census_process(Path('/proc/123'))
            self.assertEqual(sample.call_count,4)
    def test_census_foreign_UID_is_filtered_before_metadata_reads(self):
        with patch.object(Path,'stat',return_value=types.SimpleNamespace(st_uid=os.getuid()+1)),patch.object(self.system,'stat_sample') as sample:
            self.assertIsNone(self.system.census_process(Path('/proc/123')));sample.assert_not_called()
    def test_census_only_known_administrative_sd_pam_is_exempt(self):
        with patch.object(Path,'stat',new=lambda path,*a,**kw:self.ownership(path,*a,**kw)),patch.object(Path,'read_text',return_value='(sd-pam)\n'),\
                patch.object(self.system,'stat_sample',return_value=stat()):
            self.assertIsNone(self.system.census_process(Path('/proc/123')))
    def test_census_protected_exec_becomes_readable_same_lifetime(self):
        calls=[]
        def ownership(path,*args,**kwargs):
            if path.name=='cmdline':calls.append(1);return types.SimpleNamespace(st_uid=0 if len(calls)==1 else os.getuid())
            return types.SimpleNamespace(st_uid=os.getuid())
        value=process()
        with patch.object(Path,'stat',new=ownership),patch.object(Path,'read_text',return_value='python\n'),\
                patch.object(self.system,'stat_sample',return_value=stat()),patch.object(self.system,'process',return_value=value),patch.object(m.time,'sleep'):
            self.assertEqual(self.system.census_process(Path('/proc/123')),value)
    def ssh_rows(self):
        group='/user.slice/user-'+str(os.getuid())+'.slice/session-88.scope'
        child=dict(stat=dict(pid=123,start_ticks=100,ppid=500,process_group=500,session_id=500,comm='sshd'),
            uid=(os.getuid(),)*4,status_pid=123,status_ppid=500,status_name='sshd',command='sshd: researcher@notty',comm='sshd',
            groups=[group],owners={key:0 for key in ('stat','status','comm','cmdline','cgroup','cwd')},directory_uid=os.getuid())
        parent=dict(stat=dict(pid=500,start_ticks=50,ppid=1,process_group=500,session_id=500,comm='sshd'),
            uid=(0,)*4,status_pid=500,status_ppid=1,status_name='sshd',command='sshd: researcher [priv]',comm='sshd',
            groups=[group],owners={key:0 for key in ('stat','status','comm','cmdline','cgroup','cwd')},directory_uid=0)
        return child,parent
    def test_verified_ssh_administration_requires_stable_privileged_parent_chain(self):
        child,parent=self.ssh_rows()
        with patch.object(m.pwd,'getpwuid',return_value=types.SimpleNamespace(pw_name='researcher')),\
                patch.object(self.system,'administrative_snapshot',side_effect=[child,parent,copy.deepcopy(child),copy.deepcopy(parent)]):
            self.assertTrue(self.system.verified_administrative_ssh(Path('/proc/123'),stat()))
    def test_ssh_names_alone_cannot_exempt_a_model_or_unprivileged_parent(self):
        for fault in ('username','parent_uid','metadata_uid','cgroup','session','parent_command'):
            child,parent=self.ssh_rows()
            if fault=='username':child['command']='sshd: somebody_else@notty'
            elif fault=='parent_uid':parent['uid']=(os.getuid(),)*4
            elif fault=='metadata_uid':child['owners']['cmdline']=os.getuid()
            elif fault=='cgroup':child['groups']=['/user.slice/user-'+str(os.getuid())+'.slice/user@service']
            elif fault=='session':parent['stat']['session_id']=501
            else:parent['command']='python fit.py'
            with self.subTest(fault=fault),patch.object(m.pwd,'getpwuid',return_value=types.SimpleNamespace(pw_name='researcher')),\
                    patch.object(self.system,'administrative_snapshot',side_effect=[child,parent]):
                self.assertFalse(self.system.verified_administrative_ssh(Path('/proc/123'),stat()))
    def test_ssh_lifetime_change_between_role_snapshots_is_not_exempt(self):
        child,parent=self.ssh_rows();changed=copy.deepcopy(child);changed['stat']['start_ticks']=101
        with patch.object(m.pwd,'getpwuid',return_value=types.SimpleNamespace(pw_name='researcher')),\
                patch.object(self.system,'administrative_snapshot',side_effect=[child,parent,changed]):
            self.assertFalse(self.system.verified_administrative_ssh(Path('/proc/123'),stat()))
    def test_recorded_ssh_PID_is_not_exempt_from_direct_permission_checks(self):
        with patch.object(self.system,'stat_sample',return_value=stat()),patch.object(c.System,'process',side_effect=PermissionError('protected ssh cwd')),\
                patch.object(self.system,'verified_administrative_ssh') as classify,patch.object(m.time,'sleep'):
            with self.assertRaisesRegex(PermissionError,'protected ssh cwd'):self.system.process(123)
            classify.assert_not_called()
    def test_census_uses_ssh_role_proof_only_for_sshd_comm(self):
        with patch.object(Path,'stat',new=lambda path,*a,**kw:self.ownership(path,*a,**kw)),patch.object(Path,'read_text',return_value='sshd\n'),\
                patch.object(self.system,'stat_sample',return_value=stat()),patch.object(self.system,'verified_administrative_ssh',return_value=True) as classify:
            self.assertIsNone(self.system.census_process(Path('/proc/123')));classify.assert_called_once()
    def test_ssh_metadata_snapshot_reads_no_protected_cwd_target(self):
        uid=os.getuid();group='/user.slice/user-'+str(uid)+'.slice/session-88.scope'
        snapshot=dict(stat(),ppid=500,process_group=500,session_id=500,comm='sshd')
        def text(path,*a,**kw):
            return {'status':'Name:\tsshd\nPid:\t123\nPPid:\t500\nUid:\t'+'\t'.join([str(uid)]*4)+'\n',
                'comm':'sshd\n','cgroup':'1:name=systemd:'+group+'\n'}[path.name]
        def ownership(path,*a,**kw):return types.SimpleNamespace(st_uid=uid if path.name=='123' else 0)
        with patch.object(self.system,'stat_sample',side_effect=[snapshot,dict(snapshot,state='S')]),patch.object(Path,'read_text',new=text),\
                patch.object(Path,'read_bytes',return_value=b'sshd: researcher@notty    \0'),patch.object(Path,'stat',new=ownership),\
                patch.object(m.os,'readlink',side_effect=PermissionError('protected cwd')) as cwd:
            row=self.system.administrative_snapshot(Path('/proc/123'))
        self.assertEqual(row['command'],'sshd: researcher@notty');self.assertEqual(row['groups'],[group]);cwd.assert_not_called()

class DelegationBridge(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.home=Path(self.temp.name)
        self.runtime=self.home/'baseline';self.runtime.mkdir();self.shared=self.home
        self.owner=process(os.getpid(),cwd=str(m.OLD_ROOT));self.owner['argv']=[str(m.ENTRY),'--delegated-entry',str(m.CORE_ENTRY)]
        self.source=dict(root=str(m.ROOT),head='adapter-head',branch='recovery')
        self.oldsource=dict(root=str(m.OLD_ROOT),head='cba',branch='old')
        self.master=dict(scope_id='scope',start_epoch=1000.,expires_epoch=44200.)
        self.write(self.shared/'master.json',self.master)
        self.path=self.home/'authority/authority.json';self.bridge=self.path.parent/'execution_bridge.json'
        self.authority=dict(execution_source=self.source,execution_bridge_path=str(self.bridge),expected_generation=2)
        self.write(self.path,self.authority)
        self.state=dict(owner_recovery_authority_path=str(self.path),owner_recovery_authority_sha256=c.sha(self.path),
            execution_control_source=self.source,new_unit='unit',config_sha256='cfg')
        self.write(self.runtime/'state.json',self.state)
        self.proof=dict(owner=self.owner,master_sha256=c.sha(self.shared/'master.json'),generation=2)
        self.bridge_value=dict(execution_control_source=self.source,authority_sha256=c.sha(self.path),master_sha256=self.proof['master_sha256'],
            new_unit='unit',config_sha256='cfg',delegated_core_path=str(m.CORE_ENTRY),delegated_core_sha256=c.sha(m.CORE_ENTRY),actual_process=self.owner,expected_generation=2)
        self.write(self.bridge,self.bridge_value);m._SOURCE_CACHE.clear()
    def write(self,path,value):c.atomic(path,value)
    def test_health_reader_injects_recovery_system_and_checks_truthful_bridge(self):
        verify=Mock();system=object()
        with patch.object(c,'baseline_ownership',return_value=self.proof) as health,\
                patch.object(m,'module',return_value=types.SimpleNamespace(verify_source=verify)):
            self.assertEqual(m.verify_baseline(self.runtime,self.master,system),self.proof)
            health.assert_called_once_with(self.runtime,self.master,system=system,allow_expired=False)
            verify.assert_called_once_with(self.source)
    def test_health_reader_source_cache_is_bounded_to_five_seconds(self):
        verify=Mock()
        with patch.object(c,'baseline_ownership',return_value=self.proof),patch.object(m,'module',return_value=types.SimpleNamespace(verify_source=verify)),\
                patch.object(m.time,'monotonic',side_effect=[100.,101.,106.]):
            for _ in range(3):m.verify_baseline(self.runtime,self.master,object())
        self.assertEqual(verify.call_count,2)
    def test_health_reader_rejects_changed_authority_bytes(self):
        self.write(self.path,dict(self.authority,changed=True))
        with patch.object(c,'baseline_ownership',return_value=self.proof):
            with self.assertRaisesRegex(RuntimeError,'authority bytes changed'):m.verify_baseline(self.runtime,self.master,object())
    def test_health_reader_rejects_other_owner_under_the_same_unit(self):
        value=copy.deepcopy(self.bridge_value);value['actual_process']['start_ticks']+=1;self.write(self.bridge,value)
        with patch.object(c,'baseline_ownership',return_value=self.proof):
            with self.assertRaisesRegex(RuntimeError,'owner bridge differs'):m.verify_baseline(self.runtime,self.master,object())
    def test_health_reader_requires_delegated_core_argument(self):
        self.proof['owner']['argv']=[str(m.ENTRY)]
        with patch.object(c,'baseline_ownership',return_value=self.proof):
            with self.assertRaisesRegex(RuntimeError,'owner bridge differs'):m.verify_baseline(self.runtime,self.master,object())
    def test_generation_three_health_uses_explicit_baseline_only_loan_mode(self):
        self.authority['expected_generation']=3;self.write(self.path,self.authority)
        self.state['owner_recovery_authority_sha256']=c.sha(self.path);self.write(self.runtime/'state.json',self.state)
        self.bridge_value.update(expected_generation=3,authority_sha256=c.sha(self.path));self.write(self.bridge,self.bridge_value)
        self.proof['generation']=3
        with patch.object(c,'baseline_ownership',return_value=self.proof) as health,\
                patch.object(m,'module',return_value=types.SimpleNamespace(verify_source=lambda source:None)):
            self.assertEqual(m.verify_baseline(self.runtime,self.master,object(),allow_expired=True)['generation'],3)
            self.assertTrue(health.call_args.kwargs['allow_expired'])
    def test_run_executes_old_core_with_explicit_adapter_and_same_clock(self):
        unit='pricefm-r152-muscat-baseline-'+'a'*32+'.service';config=c.read_config();config['new_unit']=unit
        config_path=self.home/'append_only_config.json';self.write(config_path,config)
        self.bridge.unlink()
        authority=dict(self.authority,new_unit=unit,expected_generation=2,config_path=str(config_path),config_sha256=c.sha(config_path),
            baseline_runtime=str(self.runtime),shared_runtime=str(self.shared),original_master=dict(sha256=c.sha(self.shared/'master.json')),
            attestation_path=str(self.home/'attestation.json'),pending_path=str(self.home/'original_pending.json'))
        self.write(self.path,authority)
        state=dict(new_unit=unit,config_path=str(config_path),scope_id='scope',source=self.oldsource,execution_control_source=self.source)
        state.update(phase='running',owner_recovery_authority_path=str(self.path),owner_recovery_authority_sha256=c.sha(self.path),
            active=dict(A=dict(region='IT_CALA',pid=42)))
        self.write(self.runtime/'state.json',state);self.write(self.runtime/'resource_ownership_epoch.json',dict(generation=1))
        capsule=dict(unit=unit,attested=dict(InvocationID='inv'),process=self.owner,source_head=self.source['head'],
            source_entry_path=str(m.ENTRY),source_entry_sha256=c.sha(m.ENTRY))
        self.write(authority['attestation_path'],capsule)
        system=types.SimpleNamespace(process=lambda pid:self.owner)
        with patch.object(c,'require_own_service',return_value=dict(InvocationID='inv')),patch.object(c,'source_identity',return_value=self.oldsource),\
                patch.object(c,'run',return_value=dict(delegated=True)) as delegate:
            before=(self.shared/'master.json').read_bytes()
            result=m.run(self.path,unit,m.CORE_ENTRY,validator=lambda *args,**kwargs:authority,system=system)
            prior_state=(self.runtime/'state.json').read_bytes()
            delegate.side_effect=RuntimeError('stable live protected metadata')
            with self.assertRaisesRegex(RuntimeError,'stable live protected metadata'):
                m.run(self.path,unit,m.CORE_ENTRY,validator=lambda *args,**kwargs:authority,system=system)
        self.assertEqual(result,dict(delegated=True));self.assertIs(delegate.call_args.kwargs['system'],system)
        self.assertEqual(delegate.call_args.args[1:4],(self.runtime,self.shared,Path(authority['pending_path'])))
        self.assertEqual((self.shared/'master.json').read_bytes(),before)
        self.assertEqual(c.read(self.bridge)['original_start_epoch'],1000.)
        failed=c.read(self.runtime/'state.json');self.assertEqual(failed['phase'],'blocked')
        self.assertEqual(failed['active'],state['active'])
        self.assertEqual((self.path.parent/('wrapper_before_failure.'+str(os.getpid())+'.json')).read_bytes(),prior_state)

class PrivateProbeCleanup(unittest.TestCase):
    def test_adoption_census_failure_does_not_invalidate_exact_owned_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-',dir='/tmp') as temporary:
            folder=Path(temporary);master_path=folder/'original_master.json';output=folder/'result.json'
            c.atomic(master_path,dict(scope_id='scope',start_epoch=1000.,expires_epoch=44200.))
            source=dict(head='recovery-source');oldsource=dict(head='cba')
            owner=process(os.getpid());publisher=process(501);child=process(502,session=501)
            job=dict(disposable=True,process=publisher,child=child,observed_children=[child],session_id=501,cpus=[24])
            class Publisher:
                returncode=0
                def communicate(self,timeout):c.immutable(folder/'orphan_job.json',job);return '',''
            def cleanup(*args):
                value=dict(cleanup_verified=True,signals=[],owned_pids=[]);c.immutable(folder/'cleanup.json',value);return value
            release=types.SimpleNamespace(source_identity=lambda:source,MASTER=master_path)
            with patch.object(m,'module',return_value=release),patch.object(m,'RecoverySystem',return_value=types.SimpleNamespace(process=lambda pid:owner)),\
                    patch.object(m.tempfile,'mkdtemp',return_value=temporary),patch.object(c,'source_identity',return_value=oldsource),\
                    patch.object(m.subprocess,'Popen',return_value=Publisher()),patch.object(c,'session_members',side_effect=PermissionError('unrelated protected sshd')) as census,\
                    patch.object(c,'cleanup_disposable_probe',side_effect=cleanup):
                with self.assertRaisesRegex(RuntimeError,'cleanup/debit receipt preserved'):m.capability_probe(output)
            result=c.read(output);self.assertEqual(result['status'],'FAIL_R152_PRIVATE_BASELINE_ADOPTION_PROBE')
            self.assertTrue(result['exact_cleanup']);self.assertEqual(result['cleanup_errors'],[])
            self.assertEqual(census.call_count,1)
            self.assertEqual(result['owned_cleanup_receipt_sha256'],c.sha(folder/'cleanup.json'))
    def generation_three_case(self,folder,timeout=False):
        master_path=folder/'original_master.json';c.atomic(master_path,dict(scope_id='scope',start_epoch=1000.,expires_epoch=44200.))
        source=dict(head='new-generation-three');oldsource=dict(head='cba')
        outer=process(os.getpid(),cwd=str(m.OLD_ROOT));old=process(501,cwd=str(m.OLD_ROOT));orphan=process(502,session=501,cwd=str(m.OLD_ROOT))
        class System:
            boot_id='boot'
            def __init__(self):self.current=os.getpid();self.procs={os.getpid():outer,502:orphan}
            def process(self,pid):return copy.deepcopy(self.procs.get(self.current if pid==os.getpid() else pid))
            def stat_sample(self,pid):
                row=self.procs.get(pid)
                return dict(pid=pid,start_ticks=row['start_ticks'],state='R') if row else None
            def terminal_or_gone(self,row):return row is None or row['state'] in ('Z','X','x')
        system=System();job=dict(disposable=True,process=old,child=orphan,observed_children=[orphan],session_id=501,cpus=[24])
        def popen(argv,**kwargs):
            role='old' if str(m.CORE_ENTRY) in argv else 'publish' if 'publish-two' in argv else 'stress';pid={'old':501,'publish':503,'stress':504}[role]
            if role!='old':
                system.procs[pid]=process(pid,cwd=str(m.OLD_ROOT));system.procs[pid]['argv']=list(argv)
            class Child:
                returncode=0
                def communicate(self,timeout):
                    if role=='old':c.immutable(folder/'orphan_job.json',job)
                    elif role=='publish':
                        if fail_timeout:raise m.subprocess.TimeoutExpired(argv,timeout)
                        system.current=503;second=c.publish_owner(folder,c.read(folder/'private_state.json'),system,c.read(master_path));system.current=os.getpid()
                        c.immutable(folder/'generation_two_receipt.json',second);system.procs.pop(503)
                    else:
                        c.immutable(folder/'exit_stress.json',dict(status='PASS_PRIVATE_EXIT_STRESS',iterations=[dict(ready_snapshot=True,exit_confirmed=True)],strict_session_checks=1))
                        system.procs.pop(504)
                    return '',''
            fail_timeout=timeout;child=Child();child.pid=pid;return child
        def cleanup(*args):
            system.procs.pop(502,None);value=dict(cleanup_verified=True,signals=[],owned_pids=[]);c.immutable(folder/'cleanup.json',value);return value
        return system,source,oldsource,types.SimpleNamespace(source_identity=lambda:source,MASTER=master_path),popen,cleanup
    def test_private_child_publishes_two_then_dead_predecessor_allows_three_same_clock(self):
        with tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-',dir='/tmp') as temporary:
            folder=Path(temporary);system,source,oldsource,release,popen,cleanup=self.generation_three_case(folder);output=folder/'result.json'
            with patch.object(m,'module',return_value=release),patch.object(m,'RecoverySystem',return_value=system),\
                    patch.object(m.tempfile,'mkdtemp',return_value=temporary),patch.object(c,'source_identity',return_value=oldsource),\
                    patch.object(m.subprocess,'Popen',side_effect=popen),patch.object(c,'session_members',return_value=[system.procs[502]]),\
                    patch.object(c,'cleanup_disposable_probe',side_effect=cleanup):
                result=m.capability_probe(output,generation=3)
            self.assertEqual(result['status'],'PASS_R152_PRIVATE_BASELINE_GENERATION_THREE_PROBE')
            self.assertTrue(result['generation_two_predecessor_absent']);self.assertTrue(result['generation_three_predecessor_sha256_matches'])
            self.assertEqual(c.read(folder/'owner_epochs/003.json')['predecessor_sha256'],c.sha(folder/'owner_epochs/002.json'))
            self.assertEqual(result['original_start_epoch'],1000.);self.assertEqual(result['original_expires_epoch'],44200.)
            self.assertEqual(result['baseline_control_charged_CPU_seconds'],result['probe_driver_CPU_seconds']+result['orphan_CPU_bound_seconds'])
    def test_private_publisher_timeout_cannot_claim_whole_probe_cleanup(self):
        with tempfile.TemporaryDirectory(prefix='pricefm-r152-baseline-probe-',dir='/tmp') as temporary:
            folder=Path(temporary);system,source,oldsource,release,popen,cleanup=self.generation_three_case(folder,timeout=True);output=folder/'result.json'
            signals=[]
            def kill(pid,number):signals.append(pid);system.procs.pop(pid,None)
            with patch.object(m,'module',return_value=release),patch.object(m,'RecoverySystem',return_value=system),\
                    patch.object(m.tempfile,'mkdtemp',return_value=temporary),patch.object(c,'source_identity',return_value=oldsource),\
                    patch.object(m.subprocess,'Popen',side_effect=popen),patch.object(c,'session_members',return_value=[system.procs[502]]),\
                    patch.object(c,'cleanup_disposable_probe',side_effect=cleanup),patch.object(m.os,'kill',side_effect=kill):
                with self.assertRaisesRegex(RuntimeError,'receipt preserved'):m.capability_probe(output,generation=3)
            result=c.read(output);self.assertFalse(result['exact_cleanup']);self.assertIn(503,signals)
            self.assertTrue(any('coverage not inferred' in error for error in result['cleanup_errors']))

if __name__=='__main__':unittest.main()
