"""Synthetic metadata regressions; no Slurm, R, arrays, targets or optimizer."""
import copy
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

from . import scientific_allocation as allocation
from . import scientific_namespace_contract as contract
from . import scientific_metadata_owner as owner
from . import scientific_code_install as installer
from . import scientific_batch as batch
from . import startup_batch_worker as common
from . import scientific_batch_worker as worker


class ScientificRegressionTests(unittest.TestCase):
    def namespace(self):
        root='/new';allowed={root+'/code/'+p:s for p,s in contract.REQUIRED_PACKAGE_DLLS.items()}
        return dict(package_versions=dict(contract.PACKAGE_VERSIONS),R_HOME=root+'/code/R_HOME',library=root+'/code/R_HOME/library',
            expected_stock_body_sha256=contract.STOCK_BODY_SHA,fixedpoint_helper=dict(path=root+'/science/fixedpoint_helper.R',sha256=contract.FIXEDPOINT_SHA),
            allowed_package_DLLs=allowed,required_package_DLLs={p:s for p,s in allowed.items() if Path(p).name in {'exdqlm.so','digest.so','jsonlite.so','Matrix.so','Rcpp.so','nimble.so'}})

    def test_original_empty_or_wrong_namespace_contract_is_rejected(self):
        contract.validate(self.namespace(),'/new')
        cases=[('package_versions',{}),('expected_stock_body_sha256','0'*64),('fixedpoint_helper',{'path':'/arbitrary.R','sha256':'c'*64}),
               ('library','/old/library'),('R_HOME','/old/R_HOME'),('allowed_package_DLLs',{}),('required_package_DLLs',{})]
        for key,value in cases:
            n=self.namespace();n[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):contract.validate(n,'/new')

    def test_versions_and_Dll_bytes_cannot_be_substituted(self):
        for field in ['package_versions','allowed_package_DLLs','required_package_DLLs']:
            n=self.namespace();key=next(iter(n[field]));n[field][key]='wrong'
            with self.subTest(field=field),self.assertRaises(ValueError):contract.validate(n,'/new')

    def test_cgroup_requires_exact_job_component_and_UID_without_contradictions(self):
        uid=os.getuid();good='0::/slurm/uid_'+str(uid)+'/job_999/step_batch\n'
        self.assertEqual(allocation.exact_cgroup(good,'999',uid),[good.strip().split(':',2)[2]])
        uidless='0::/system.slice/slurmstepd.scope/job_999/step_batch\n'
        self.assertEqual(allocation.exact_cgroup(uidless,'999',uid),[uidless.strip().split(':',2)[2]])
        for text in [good.replace('job_999/','job_9990/'),good.replace('uid_'+str(uid),'uid_1'),
                     good+'1:cpu:/slurm/uid_'+str(uid)+'/job_1000/step_batch\n',good+'1:cpu:/slurm/uid_1/job_999/step_batch\n',
                     'malformed',good.replace('job_999/','job_999/child/job_1000/'),good+'1:cpu:/slurm/uid_1\n']:
            with self.subTest(text=text),self.assertRaises(ValueError):allocation.exact_cgroup(text,'999',uid)

    def test_installer_requires_all_prospective_component_and_whole_funding(self):
        pins=[dict(path='/test/'+x,sha256=str(i)*64) for i,x in enumerate(['spec','authority','review'],1)]
        spec=dict(schema='r179_scientific_code_install_spec_v1',purpose=installer.n.PURPOSE,bounds=dict(files=4096,bytes=384*1024**2,one_file_bytes=64*1024**2),
                  R_executions=0,scientific_target_data=False,optimizer_invocations=0,job_id='999',node='node-13',affinity=[0],expires_epoch=7000)
        auth=dict(status='ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY',spec=pins[0],sources=installer.sources(),issued_epoch=1,expires_epoch=6000,
                  memory_MiB=8192,max_calls=1,install_CPU_seconds=60,install_wall_seconds=600,whole_CPU_seconds=600,whole_wall_seconds=1200)
        review=dict(status='PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC',spec=pins[0],authority=pins[1],sources=auth['sources'])
        def validate(a):
            with patch.object(installer.a,'read',side_effect=[spec,a,review]):
                return installer.validate(*pins,now=100,environment=dict(SLURM_JOB_ID='999',SLURMD_NODENAME='node-13',SLURM_CPUS_PER_TASK='1'),affinity={0},node='node-13')
        self.assertEqual(validate(auth),spec)
        for field in ['install_CPU_seconds','install_wall_seconds','whole_CPU_seconds','whole_wall_seconds']:
            a=dict(auth);del a[field]
            with self.subTest(field=field),self.assertRaises(ValueError):validate(a)
        a=dict(auth,expires_epoch=float('inf'))
        with self.assertRaises(ValueError):validate(a)

    def frame(self):
        n=self.namespace();return dict(status='PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY',nonce='a'*32,job_id='999',node='node-13',affinity=0,
            R_version='4.6.0',R_home=n['R_HOME'],package_library=n['library'],package_versions=contract.PACKAGE_VERSIONS,
            stock_body_sha256=contract.STOCK_BODY_SHA,loaded_DLLs=[dict(entry_name=Path(p).stem,name=Path(p).stem,path=p,sha256=s) for p,s in n['required_package_DLLs'].items()],
            builtin_DLLs=[contract.intrinsic_base(dict(path='/new/code/R_HOME/bin/exec/R',sha256=contract.NATIVE_R_SHA))],
            optimizer_invocations=0,scientific_data_read=False,models=0)

    def test_actual_frames_bind_job_nonce_runtime_versions_and_DLLs(self):
        spec=dict(role=batch.ROLES[0],job_id='999',node='node-13',nonce='a'*32,affinity=[0],R_native=dict(path='/new/code/R_HOME/bin/exec/R',sha256=contract.NATIVE_R_SHA));n=self.namespace()
        owner.validate_frames([self.frame()],spec,n)
        for key,value in [('job_id','998'),('nonce','b'*32),('R_version','4.5.0'),('package_versions',{}),('stock_body_sha256','0'*64),('models',1)]:
            f=self.frame();f[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):owner.validate_frames([f],spec,n)
        f=self.frame();f['loaded_DLLs'][0]['sha256']='0'*64
        with self.assertRaises(ValueError):owner.validate_frames([f],spec,n)
        f=self.frame();f['loaded_DLLs'].append(dict(path='/unreviewed/code.so',sha256='0'*64))
        with self.assertRaises(ValueError):owner.validate_frames([f],spec,n)

    def test_optional_packaged_cairo_is_allowed_without_manufactured_load_requirement(self):
        f=self.frame();n=self.namespace();spec=dict(role=batch.ROLES[0],job_id='999',node='node-13',nonce='a'*32,affinity=[0],R_native=dict(path='/new/code/R_HOME/bin/exec/R',sha256=contract.NATIVE_R_SHA))
        owner.validate_frames([f],spec,n)
        optional=next(p for p in n['allowed_package_DLLs'] if p.endswith('/cairo.so'))
        f['loaded_DLLs'].append(dict(entry_name='cairo',name='cairo',path=optional,sha256=n['allowed_package_DLLs'][optional]));owner.validate_frames([f],spec,n)

    def test_current_owner_receipt_cannot_be_swapped_from_other_lifetime_scope_or_authority(self):
        life=dict(pid=123,start_ticks=456,boot_id='boot',affinity=[0],uid=os.getuid())
        guard=dict(schema='r157_traced_bootstrap_guard_receipt_v1',status='EXITED',returncode=0,reaped=True,drained=True,
            CPU_accounting_complete=True,all_newborns_kernel_traced_before_execution=True,tracer_death_kernel_EXITKILL_enabled=True,
            remaining_owned_lifetimes=[],unexpected_untraced_child_waits=[],supervisor=life,maximum_combined_CPU_seconds=450,
            parent_plus_all_reaped_child_CPU_seconds=3,wall_seconds=1)
        auth=dict(path='/new/release/authority.json',sha256='a'*64)
        tree=dict(schema='r157_ptrace_owner_v1',state='CLOSED',scope='newscope',authority_pin=auth,source={'kind':'UNCHANGED_R157_TRACER_R179_METADATA_OWNER'},supervisor=life)
        spec=dict(role=batch.ROLES[0],scope_id='newscope');owner.validate_current_owner(guard,tree,spec,auth,life)
        for field,value in [('scope','oldscope'),('authority_pin',dict(path='/old/auth',sha256='b'*64)),('state','UNREAPED_BLOCKED')]:
            t=dict(tree);t[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):owner.validate_current_owner(guard,t,spec,auth,life)
        g=copy.deepcopy(guard);g['supervisor']=dict(life,start_ticks=455)
        with self.assertRaises(ValueError):owner.validate_current_owner(g,tree,spec,auth,life)

    def root(self,path):
        path.mkdir();batch.h.write_new(path/'PACKET.json',dict(role=batch.ROLES[0],scope_id='r181-namespace-abc',remote_root='/mnt/beegfs/home/jaguir26/pricefm_r181_test/r181-namespace-abc',spec_sha256='a'*64,sources={}))
        batch.append(path,'PREPARED',packet=batch.h.pin(path/'PACKET.json'));batch.append(path,'STAGED');return path

    def test_ambiguous_submission_is_spent_then_exact_forensic_drain_only(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            root=self.root(Path(tmp)/'role');site=dict(user='jaguir26',account='128x24',partition='128x24',qos='normal')
            config=dict(node='node-13');scope=dict(fixed_latest_submit_epoch=time.time()+3600,expires_epoch=time.time()+7200)
            with patch.object(batch,'run_native',side_effect=[dict(returncode=0,stdout=''),dict(returncode=0,stdout='AMBIGUOUS')]) as native:
                with self.assertRaises(ValueError):batch.submit(config,scope,site,root)
                self.assertEqual(native.call_count,2)
                with self.assertRaises(ValueError):batch.submit(config,scope,site,root)
                self.assertEqual(native.call_count,2)
            self.assertFalse((root/'JOB.json').exists());self.assertTrue((root/'submit.intent.json').exists())
            batch.h.write_new(root/'ROLE_FAILED_SPENT.json',dict(status='FAILED_ROLE_SPENT_DRAIN_OR_DIAGNOSIS_ONLY'))
            raw='887999|r181-namespace-abc|jaguir26|'+str(os.getuid())+'|128x24|128x24|RUNNING\n'
            with patch.object(batch,'run_native',return_value=dict(returncode=0,stdout=raw)):
                found=batch.reconcile(config,site,root)
            self.assertEqual(found['job_id'],'887999');self.assertIn('DRAIN_ONLY',found['status'])
            self.assertFalse((root/'JOB.json').exists());self.assertEqual(batch.known_job(root)['job_id'],'887999')
            with patch.object(batch,'run_native',return_value=dict(returncode=0,stdout='')) as native:
                batch.cancel(site,root)
                self.assertEqual(native.call_args.args[1],['scancel','--user','jaguir26','--name','r181-namespace-abc','887999'])

    def test_foreign_forensic_UID_cannot_become_a_known_job(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            root=self.root(Path(tmp)/'role');batch.h.write_new(root/'submit.intent.json',{})
            p=batch.packet(root);batch.append(root,'SUBMISSION_INTENT',argv=['sbatch','--job-name='+p['scope_id'],p['remote_root']+'/job.sbatch'])
            batch.h.write_new(root/'ROLE_FAILED_SPENT.json',{})
            raw='887999|r181-namespace-abc|jaguir26|1|128x24|128x24|RUNNING\n'
            with patch.object(batch,'run_native',return_value=dict(returncode=0,stdout=raw)),self.assertRaises(ValueError):batch.reconcile({},dict(user='jaguir26'),root)
            self.assertFalse((root/'RECONCILED_JOB.json').exists())

    def test_whole_budget_prices_failure_and_reconciliation_without_larger_action_caps(self):
        self.assertEqual(sum([60,450,30,30,30]),600);self.assertEqual(sum([120,600,300,180]),1200)
        native=sum((x['local_CPU']+x['remote_unknown_fee'])*x['maximum_calls'] for x in batch.ACTION_ENVELOPE.values())
        self.assertLessEqual(native+4+6+6+2,batch.NATIVE_CONTROL_TOTAL)
        self.assertEqual(batch.action_limits('submit')['local_CPU'],4)
        self.assertEqual(batch.action_limits('reconcile')['local_CPU'],3)

    def test_live_allocation_rejects_scheduler_UID_resources_or_foreign_cgroup(self):
        uid=os.getuid();text='0::/slurm/uid_'+str(uid)+'/job_999/step_batch\n'
        fields=dict(JobId='999',JobState='RUNNING',NumCPUs='1',NumTasks='1',NumNodes='1',Requeue='0',NodeList='node-13',
                    Partition='128x24',Account='128x24',QOS='normal',UserId='jaguir26('+str(uid)+')',MinMemoryNode='8G',TimeLimit='00:20:00',EndTime='2026-10-31T23:59:59')
        def live(record,cgroup=text):
            reply=type('Reply',(),{'stdout':' '.join(k+'='+v for k,v in record.items())})()
            with (patch.dict(os.environ,dict(SLURM_JOB_ID='999',SLURMD_NODENAME='node-13',SLURM_CPUS_PER_TASK='1',TZ='UTC')),
                 patch.object(os,'sched_getaffinity',return_value={0}),patch.object(Path,'read_text',return_value=cgroup),
                 patch.object(allocation.subprocess,'run',return_value=reply),patch.object(allocation.admission,'cgroup_memory_limit',return_value=8*1024**3),
                 patch.object(allocation.time,'mktime',return_value=time.time()+1500)):
                return allocation.live('999','node-13',[0],minimum_remaining=600)
        self.assertEqual(live(fields)['uid'],uid)
        self.assertEqual(live(fields,'0::/system.slice/slurmstepd.scope/job_999/step_batch\n')['uid'],uid)
        for key,value in [('UserId','other(1)'),('NumCPUs','2'),('Requeue','1'),('NodeList','node-12'),('MinMemoryNode','16G')]:
            f=dict(fields);f[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):live(f)
        with self.assertRaises(ValueError):live(fields,text.replace('job_999','job_9990'))
        wrong=dict(fields,UserId='other(1)')
        with self.assertRaises(ValueError):live(wrong,'0::/system.slice/slurmstepd.scope/job_999/step_batch\n')

    def test_direct_batch_accounting_requires_primary_and_batch_without_fabricated_srun_step(self):
        def row(job):return job+'|COMPLETED|0:0|00:00:01|4|1|scope|128x24|128x24|8Gn|\n'
        account=batch.parse_accounting(row('999')+row('999.batch'),'999','scope')
        self.assertTrue(account['terminal']);self.assertTrue(account['complete']);self.assertEqual(account['canonical_primary_CPU_seconds'],1)
        self.assertFalse(batch.parse_accounting(row('999'),'999','scope')['complete'])
        with self.assertRaises(ValueError):batch.parse_accounting(row('999')+row('999.batch')+row('999.0'),'999','scope')

    def test_failed_action_acknowledgment_does_not_require_fictitious_SUBMITTED_record(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            registry=Path(tmp);root=self.root(registry/batch.ROLES[0])
            start=registry/'control_0000.started.json';batch.h.write_new(start,dict(role=batch.ROLES[0],source_sha256=batch.digest(batch.__file__),command_pid=123,command_birth_ticks=456))
            guard=registry/'failed.json';batch.h.write_new(guard,dict(returncode=125,all_owned_descendants_reaped=True,independent_guardian=True,session_id=123,leader_start_ticks=456))
            batch.acknowledge_failed_previous(registry,batch.ROLES[0],guard)
            self.assertTrue((root/'ROLE_FAILED_SPENT.json').exists());self.assertFalse((root/'JOB.json').exists())
            self.assertTrue((registry/'control_0000.failed_ack.json').exists())

    def test_crash_before_failed_ack_keeps_role_spent_before_any_successor(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            registry=Path(tmp);root=self.root(registry/batch.ROLES[0]);start=registry/'control_0000.started.json'
            batch.h.write_new(start,dict(role=batch.ROLES[0],source_sha256=batch.digest(batch.__file__),command_pid=123,command_birth_ticks=456))
            guard=registry/'failed.json';batch.h.write_new(guard,dict(returncode=125,all_owned_descendants_reaped=True,independent_guardian=True,session_id=123,leader_start_ticks=456))
            original=batch.h.write_new
            def interrupted(path,value):
                if str(path).endswith('.failed_ack.json'):raise OSError('injected interrupted durable ack')
                return original(path,value)
            with patch.object(batch.h,'write_new',side_effect=interrupted),self.assertRaises(OSError):
                batch.acknowledge_failed_previous(registry,batch.ROLES[0],guard)
            self.assertTrue((root/'ROLE_FAILED_SPENT.json').exists());self.assertFalse((registry/'control_0000.failed_ack.json').exists())

    def test_pre_READY_admission_failure_seals_truthful_metadata_without_payload(self):
        with tempfile.TemporaryDirectory(dir='/dev/shm') as tmp:
            root=Path(tmp);code=root/'package/pricefm_hb/scientific_batch_worker.py';code.parent.mkdir(parents=True)
            code.write_text('synthetic source placeholder, never executed');(root/'result').mkdir()
            spec=dict(remote_root=str(root),role=batch.ROLES[0],scope_id='synthetic-failure',sources={},maximum_return_files=4096,maximum_return_bytes=32*1024**2)
            path=root/'SPEC.json';common.write_new(path,spec)
            with (patch.object(worker,'__file__',str(code)),patch.object(worker,'bootstrap',side_effect=ValueError('synthetic UID mismatch')),
                 patch.dict(os.environ,dict(SLURM_JOB_ID='999'))):
                self.assertEqual(worker.run(common.pin(path)),1)
            result=common.read_json((root/'result/RESULT.json').read_bytes());manifest=common.read_json((root/'result/RETURN_MANIFEST.json').read_bytes())
            self.assertEqual(result['status'],'FAILED_SCIENTIFIC_METADATA_WORKER');self.assertFalse(result['allocation_admitted'])
            self.assertIsNone(result['ready']);self.assertIsNone(result['outcome']);self.assertFalse((root/'READY.json').exists())
            batch.validate_manifest(manifest,spec,'999')


if __name__=='__main__':unittest.main()
