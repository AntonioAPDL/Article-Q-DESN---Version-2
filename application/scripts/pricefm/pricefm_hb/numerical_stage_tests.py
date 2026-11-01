"""Metadata regression and failure tests. They execute no R or science arrays."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from . import numerical_stage_contract as c
from . import numerical_batch as batch
from . import numerical_stage_owner as owner
from . import numerical_physical_admission as physical
from . import numerical_stage_prepare as preparation
from . import numerical_independent_peer as independent_peer
from . import numerical_critical_driver as driver


def limits(role):
    value=dict(production_fits=0,production_acceptance=False,scientific_target_data=role!='TOY_PARITY',optimizer_invocations=8 if role=='TOY_PARITY' else 0)
    if role=='TOY_PARITY':value.update(combined_iterations=30,maximum_n=128,maximum_p=32)
    else:value.update(optimizer_updates=0,target_name=c.TARGET,n=48576,p=417,tau=.75,tau0=.0022915214919211734,certificate_limits=c.LIMITS,both_RHS_starts=True)
    return value


class RoleTests(unittest.TestCase):
    def test_two_closed_roles(self):
        for role in c.ROLES:self.assertTrue(c.validate_role(role,limits(role)))
    def test_pilot_rejected(self):
        with self.assertRaises(ValueError):c.validate_role('NO3_AL300_PILOT',limits('ZERO_UPDATE_BRIDGE'))
    def test_toy_does_not_expand(self):
        for field,value in [('optimizer_invocations',9),('combined_iterations',31),('maximum_n',129),('maximum_p',33),('scientific_target_data',True)]:
            case=limits('TOY_PARITY');case[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):c.validate_role('TOY_PARITY',case)
    def test_boolean_counter_not_integer(self):
        case=limits('TOY_PARITY');case['production_fits']=False
        with self.assertRaises(ValueError):c.validate_role('TOY_PARITY',case)
    def test_bridge_no_update_or_target_swap(self):
        for field,value in [('optimizer_updates',1),('target_name','AT'),('p',577),('both_RHS_starts',False)]:
            case=limits('ZERO_UPDATE_BRIDGE');case[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):c.validate_role('ZERO_UPDATE_BRIDGE',case)
    def test_original_limits_are_exact(self):
        case=limits('ZERO_UPDATE_BRIDGE');case['certificate_limits']=dict(c.LIMITS,elbo_relative=1e-7)
        with self.assertRaises(ValueError):c.validate_role('ZERO_UPDATE_BRIDGE',case)
    def test_exact_child_funding_not_boolean_or_one_second(self):
        spec=dict(role='TOY_PARITY',role_limits=limits('TOY_PARITY'),job_id='123',node='node-13',affinity=[31],scope_id='UNIT',expires_epoch=2000)
        grant=dict(schema='pricefm_hb_scientific_stage_grant_v1',status='ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY',role='TOY_PARITY',job_id='123',
            node='node-13',affinity=[31],scope_id='UNIT',memory_MiB=8192,max_new_numerical=1,attempt_index=1,old_claims_reused=False,
            old_costs_refunded=False,authorizes_production_acceptance=False,authorizes_production_fits=False,stage_deadline_epoch=2000,
            maximum_optimizer_invocations=8,maximum_total_optimizer_iterations=30,maximum_n=128,maximum_p=32,authorizes_toy_optimizer=True,
            expected_stock_body_sha256=c.STOCK_BODY_SHA,maximum_CPU_seconds=300,conditional_parse_and_current_kernel_ACK_required=True)
        self.assertTrue(c.validate_grant(spec,grant,now=100))
        for cap in [1,True,299,301]:
            with self.subTest(cap=cap),self.assertRaises(ValueError):c.validate_grant(spec,dict(grant,maximum_CPU_seconds=cap),now=100)


class DeliveryTests(unittest.TestCase):
    def rows(self):
        return [dict(relative=name,bytes=c.DELIVERY_BYTES[name],source=dict(path='/local/'+name,sha256=sha),remote=dict(path='/remote/'+name,sha256=sha)) for name,sha in c.DELIVERY_HASHES.items()]
    def test_fifteen_exact_opaque_sources(self):
        result=c.validate_delivery('ZERO_UPDATE_BRIDGE',self.rows());self.assertEqual(result['files'],15);self.assertFalse(result['scientific_arrays_opened'])
    def test_toy_has_no_real_delivery(self):
        with self.assertRaises(ValueError):c.validate_delivery('TOY_PARITY',self.rows())
    def test_metadata_member_length_is_frozen_too(self):
        rows=self.rows();rows[0]['bytes']+=1
        with self.assertRaises(ValueError):c.validate_delivery('ZERO_UPDATE_BRIDGE',rows)
    def test_opaque_transport_requires_separate_explicit_exact_authority(self):
        rows=[{key:value for key,value in dict(row,logical_path='/UNIT_ORIGINAL/'+row['relative']).items() if key!='remote'} for row in self.rows()]
        scope=dict(path='/UNIT_NOT_REAL/SCOPE.json',sha256='a'*64)
        original=dict(path='/UNIT_NOT_REAL/original.json',sha256=c.ORIGINAL_MANIFEST_SHA)
        authority=dict(status='ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY',scope=scope,target_name=c.TARGET,files=rows,
            original_manifest=original,no_optimizer_or_science_execution=True,allow_opaque_transport=True,
            maximum_files=15,maximum_file_bytes=c.MAX_TARGET_FILE,maximum_total_bytes=c.MAX_TARGET_TOTAL)
        self.assertTrue(c.validate_opaque_delivery_authority(authority,scope,rows,original))
        for field,value in [('allow_opaque_transport',False),('maximum_files',True),('maximum_file_bytes',float(c.MAX_TARGET_FILE)),
                            ('maximum_total_bytes',c.MAX_TARGET_TOTAL+1),('original_manifest',dict(original,sha256='b'*64))]:
            with self.subTest(field=field),self.assertRaises(ValueError):
                c.validate_opaque_delivery_authority(dict(authority,**{field:value}),scope,rows,original)
    def test_renamed_or_extra_target_rejected(self):
        for operation in ['drop','extra','replace']:
            rows=self.rows()
            if operation=='drop':rows.pop()
            elif operation=='extra':rows.append(dict(rows[-1],relative='AT/x.bin'))
            else:rows[0]['source']['sha256']='0'*64;rows[0]['remote']['sha256']='0'*64
            with self.subTest(operation=operation),self.assertRaises(ValueError):c.validate_delivery('ZERO_UPDATE_BRIDGE',rows)
    def test_shape_size_and_traversal(self):
        for field,value in [('bytes',162049535),('relative','../escape')]:
            rows=self.rows();row=next(r for r in rows if r['relative']=='design/X.bin');row[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):c.validate_delivery('ZERO_UPDATE_BRIDGE',rows)


class ReturnTests(unittest.TestCase):
    def manifest(self,role):
        rows=[dict(relative=path,bytes=1,sha256='a'*64) for path in sorted(c.output_inventory(role)[0])]
        return dict(schema='r182_frozen525_numerical_return_manifest_v1',scope_id='s',job_id='123',files=rows,complete_success=True)
    def test_exact_toy_and_bridge_manifest(self):
        for role in c.ROLES:self.assertTrue(batch.validate_manifest(self.manifest(role),dict(scope_id='s',role=role),'123'))
        self.assertEqual(sum(p.endswith('.rds') for p in c.output_inventory('TOY_PARITY')[1]),13)
        self.assertEqual(sum(p.endswith('.bin') for p in c.output_inventory('TOY_PARITY')[1]),8)
    def test_no_broad_rds_allowlist(self):
        manifest=self.manifest('TOY_PARITY');manifest['files'].append(dict(relative='numerical/toy/stolen.rds',bytes=1,sha256='b'*64))
        with self.assertRaises(ValueError):batch.validate_manifest(manifest,dict(scope_id='s',role='TOY_PARITY'),'123')
    def test_missing_checkpoint_is_not_complete(self):
        manifest=self.manifest('TOY_PARITY');manifest['files'].pop()
        with self.assertRaises(ValueError):batch.validate_manifest(manifest,dict(scope_id='s',role='TOY_PARITY'),'123')
    def test_bridge_cannot_return_optimizer_state(self):
        manifest=self.manifest('ZERO_UPDATE_BRIDGE');manifest['files'].append(dict(relative='numerical/bridge/final_state.rds',bytes=1,sha256='b'*64))
        with self.assertRaises(ValueError):batch.validate_manifest(manifest,dict(scope_id='s',role='ZERO_UPDATE_BRIDGE'),'123')
    def test_pass_worker_cannot_accept_partial_return(self):
        root=Path('/unit/NUMERIC_NOT_REAL');p=dict(scope_id='s',role='TOY_PARITY')
        account=dict(terminal=True,complete=True);manifest=dict(self.manifest('TOY_PARITY'),complete_success=False)
        values={str(root/'JOB.json'):dict(job_id='123'),'account':account,'manifest':manifest}
        history=[dict(state='OBSERVED',accounting=dict(path='account',sha256='a'*64)),dict(state='RETURNED',manifest=dict(path='manifest',sha256='b'*64))]
        with patch.object(batch,'packet',return_value=p),patch.object(batch,'records',return_value=history),patch.object(batch,'one_shot'),\
             patch.object(batch.h,'pin',side_effect=lambda path:dict(path=str(path),sha256='c'*64)),\
             patch.object(batch.h,'read',side_effect=lambda pin:values[pin['path']]),patch.object(batch,'run_native') as remote:
            with self.assertRaises(ValueError):batch.accept({}, {},root,'peer')
            remote.assert_not_called()


class PhysicalTests(unittest.TestCase):
    def test_reported_filesystem_floor_does_not_claim_quota(self):
        import types
        now=__import__('time').time()
        facts=types.SimpleNamespace(f_frsize=4096,f_bavail=80*1024**3//4096,f_bfree=81*1024**3//4096)
        with tempfile.TemporaryDirectory() as path,patch.object(physical.os,'statvfs',return_value=facts):
            value=physical.filesystem_facts(path);self.assertEqual(value['quota_status'],'UNKNOWN')
            self.assertTrue(physical.validate_filesystem(value,path,now=__import__('time').time()))
            for field,replacement in [('available_bytes',True),('quota_status','UNLIMITED'),('minimum_available_bytes',1),('observed_epoch',now-151)]:
                with self.subTest(field=field),self.assertRaises(ValueError):physical.validate_filesystem(dict(value,**{field:replacement}),path,now=now)
            facts.f_bavail-=1
            with self.assertRaises(ValueError):physical.filesystem_facts(path)
        with tempfile.TemporaryDirectory() as path,patch.object(physical.os,'statvfs',side_effect=OSError('synthetic failed stat')):
            with self.assertRaises(OSError):physical.filesystem_facts(path)
    def test_exact_kernel_cpu_lists(self):
        self.assertEqual(physical.cpu_list('0-2,8'),[0,1,2,8])
        with self.assertRaises(ValueError):physical.cpu_list('3-1')
    def test_one_cpu_is_not_physical_admission(self):
        snapshot=dict(status='OBSERVED_NUMERICAL_CORE_METADATA_NOT_ADMISSION',job_id='1',node='node-13',uid=__import__('os').getuid(),affinity=[0],observed_epoch=100,Slurm_core_policy={})
        with self.assertRaises(ValueError):physical.validate(snapshot,{}, {},job_id='1',node='node-13',affinity=[0],now=101)
    def test_job_ancestor_not_narrow_task_cpuset(self):
        membership='7:cpuset:/slurm/uid_26/job_123/step_batch/task_0\n'
        mounts='1 0 0:1 / /sys/fs/cgroup/cpuset rw - cgroup cgroup rw,cpuset\n'
        values={'/sys/fs/cgroup/cpuset/slurm/uid_26/job_123/cpuset.effective_cpus':'0,32\n',
                '/sys/fs/cgroup/cpuset/slurm/uid_26/job_123/step_batch/task_0/cpuset.effective_cpus':'0\n'}
        observed=physical.job_cpuset('123',membership,mounts,values.__getitem__)
        self.assertEqual(observed['effective_cpus'],[0,32]);self.assertEqual(observed['job_cgroup_path'],'/slurm/uid_26/job_123')
    def test_v2_mount_root_is_resolved(self):
        membership='0::/slurm/job_123/step_batch\n';mounts='1 0 0:1 /slurm /cgroup rw - cgroup2 cgroup rw\n'
        values={'/cgroup/job_123/cpuset.cpus.effective':'2-3\n'}
        self.assertEqual(physical.job_cpuset('123',membership,mounts,values.__getitem__)['effective_cpus'],[2,3])
    def test_missing_job_ancestor_does_not_use_task_affinity(self):
        with self.assertRaises(ValueError):physical.job_cpuset('123','0::/slurm/job_123/step_batch\n','1 0 0:1 / /cgroup rw - cgroup2 cgroup rw\n',{}.__getitem__)
    def test_producer_witnesses_roundtrip_and_cpuset_override_rejected(self):
        import os,time
        topo=dict(cpu=31,physical_package_id=0,core_id=31,thread_siblings=[31])
        cpuset=dict(version=1,job_cgroup_path='/slurm/job_123',job_filesystem_path='/unit/job_123',effective_file='/unit/job_123/cpuset.cpus',effective_cpus=[31])
        def native(argv):
            text=''
            if argv[1:3]==['show','config']:text='SelectType = select/cons_tres\nSelectTypeParameters = CR_Core_Memory\nTaskPlugin = task/cgroup\nProctrackType = proctrack/cgroup\n'
            elif argv[1:3]==['show','partition']:text='PartitionName=128x24 OverSubscribe=NO\n'
            return dict(argv=argv,returncode=0,stdout=text,stderr='',exact_child_reaped=True,identity=dict(pid=1234,start_ticks=1,uid=os.getuid()))
        with tempfile.TemporaryDirectory() as path,patch.object(physical.allocation,'live',return_value=dict(end_epoch=time.time()+1200)),\
             patch.object(physical.allocation,'exact_cgroup',return_value=['/slurm/job_123']),patch.object(physical,'observed_native',side_effect=native),\
             patch.object(physical,'topology',return_value=topo),patch.object(physical,'job_cpuset',return_value=cpuset),patch.object(physical,'own_children',return_value=[]):
            snapshot=physical.capture('123','node-13',[dict(job_id='122',job_name='r181-boundary-UNIT',terminal=True)],Path(path)/'physical')
            self.assertFalse(snapshot['physical_numerical_admission']);self.assertEqual(len(snapshot['witness_pins']),3)
            now=time.time();proof=dict(status='ROOT_ADMITTED_EXACT_SLURM_NUMERICAL_PHYSICAL_CORE',job_id='123',node='node-13',uid=os.getuid(),affinity=[31],
                topology=topo,Slurm_core_policy=snapshot['Slurm_core_policy'],all_SMT_siblings_reserved_to_this_job=True,unreviewed_numerical_peer_intersections=[],
                priority_drain_complete=True,old_processes_signalled_or_peer_allowlist_broadened=False,issued_epoch=now-1,expires_epoch=now+300,**snapshot['witness_pins'])
            review=dict(status='PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN',job_id='123',node='node-13',topology=topo,
                all_peer_and_drain_witnesses_bound=True,**snapshot['witness_pins'])
            self.assertTrue(physical.validate(snapshot,proof,review,job_id='123',node='node-13',affinity=[31],now=now))
            with patch.object(physical,'job_cpuset',return_value=dict(cpuset,effective_cpus=[31,63])),self.assertRaises(ValueError):
                physical.validate(snapshot,proof,review,job_id='123',node='node-13',affinity=[31],now=now)


class ParseTransitionTests(unittest.TestCase):
    def fixture(self):
        spec=dict(role='TOY_PARITY',job_id='123',node='node-13',nonce='0'*32,
                  scientific_sources={name:dict(path='/unit/'+name,sha256=sha) for name,sha in c.SCIENCE_HASHES.items()})
        frame=dict(status='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT',role='TOY_PARITY',job_id='123',node='node-13',nonce='0'*32,
                   source_files=c.ordered_science_pins(spec['scientific_sources']),optimizer_invocations=0,scientific_target_data_read=False)
        state=dict(state='LIVE',kernel_trace_owned=True,scientific_filter_accepted=True)
        return spec,frame,state
    def test_exact_parent_gate_at_pre_ACK_capture(self):
        spec,frame,state=self.fixture();self.assertEqual(owner.parse_gate(spec,json.dumps(frame).encode(),'SCIENTIFIC_FORK_DENIED',state),frame)
    def test_wrong_phase_or_unattested_filter_never_releases(self):
        spec,frame,state=self.fixture()
        with self.assertRaises(ValueError):owner.parse_gate(spec,json.dumps(frame).encode(),'TRACED_BOOTSTRAP',state)
        state['scientific_filter_accepted']=False
        with self.assertRaises(ValueError):owner.parse_gate(spec,json.dumps(frame).encode(),'SCIENTIFIC_FORK_DENIED',state)
    def test_missing_source_or_foreign_job_never_releases(self):
        for mutation in ['source','job','target']:
            spec,frame,state=self.fixture()
            if mutation=='source':frame['source_files'].pop()
            elif mutation=='job':frame['job_id']='999'
            else:frame['scientific_target_data_read']=True
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):owner.parse_gate(spec,json.dumps(frame).encode(),'SCIENTIFIC_FORK_DENIED',state)


class IndependentPhysicalFactsTests(unittest.TestCase):
    def fixture(self):
        import os,time,datetime
        now=time.time();end=int(now)+1200;job='123';node='node-13';uid=os.getuid();affinity=[31]
        identity=dict(pid=1000,start_ticks=100,boot_id='UNIT_NOT_A_REAL_BOOT',affinity=affinity,uid=uid)
        topo=dict(cpu=31,physical_package_id=0,core_id=31,thread_siblings=[31,63])
        cpuset=dict(version=1,job_cgroup_path='/slurm/uid_'+str(uid)+'/job_123',job_filesystem_path='/unit/job_123',
                    effective_file='/unit/job_123/cpuset.effective_cpus',effective_cpus=[31,63])
        policy=dict(SelectType='select/cons_tres',SelectTypeParameters='CR_Core_Memory',TaskPlugin='task/cgroup',ProctrackType='proctrack/cgroup',PartitionOverSubscribe='NO')
        scheduler=dict(job_id=job,node=node,uid=uid,cpus=1,tasks=1,nodes=1,requeue=False,memory_MiB=8192,
            wall_seconds=1200,end_epoch=float(end),cgroup_memory_limit_bytes=8192*1024**2,cgroups=['/slurm/uid_'+str(uid)+'/job_123/step_batch'])
        known=[dict(job_id='122',job_name='r181-boundary-UNIT',terminal=True)]
        config_raw='SelectType = select/cons_tres\nSelectTypeParameters = CR_Core_Memory\nTaskPlugin = task/cgroup\nProctrackType = proctrack/cgroup\n'
        end_text=datetime.datetime.fromtimestamp(end,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
        job_raw='JobId=123 JobState=RUNNING NumCPUs=1 NumTasks=1 NumNodes=1 NodeList=node-13 Requeue=0 Partition=128x24 Account=128x24 QOS=normal UserId=jaguir26('+str(uid)+') MinMemoryNode=8G TimeLimit=00:20:00 EndTime='+end_text
        commands=[(['/usr/bin/scontrol','show','job','-o','123'],job_raw),(['/usr/bin/scontrol','show','config'],config_raw),
                  (['/usr/bin/scontrol','show','partition','-o','128x24'],'PartitionName=128x24 OverSubscribe=NO'),
                  (['/usr/bin/squeue','--noheader','--user','jaguir26','--name','r181-boundary-UNIT','--format','%i|%128j|%T'],'')]
        records=[dict(argv=argv,stdout=stdout,stderr='',returncode=0,exact_child_reaped=True,
                      identity=dict(pid=1001+i,start_ticks=101+i,uid=uid)) for i,(argv,stdout) in enumerate(commands)]
        common=dict(job_id=job,node=node,uid=uid,observed_epoch=now)
        witnesses=dict(allocation_witness=dict(common,status='OBSERVED_CURRENT_JOB_SLURM_CORE_POLICY_NOT_ADMISSION',scheduler=scheduler,topology=topo,Slurm_core_policy=policy,job_cpuset=cpuset,online_thread_siblings=[31,63]),
            peer_ownership_witness=dict(common,status='OBSERVED_OWN_CGROUP_AND_STARTUP_TREE_NOT_ADMISSION',supervisor=identity,cgroups=scheduler['cgroups'],pending_owned_children=[],all_declared_native_helpers_reaped=True,unrelated_projects_censused=False),
            priority_drain_witness=dict(common,status='OBSERVED_KNOWN_PRICEFM_QUEUE_AND_OWN_STARTUP_DRAIN_NOT_ADMISSION',known_prior_jobs=known,observed_queue_rows=[],all_known_PriceFM_jobs_absent=True,pending_owned_children=[],no_production_processes_signalled=True))
        native=dict(common,status='ACTUAL_OWN_NATIVE_STARTUP_OBSERVATIONS_NOT_ADMISSION',records=records,own_startup_helpers_reaped=True)
        snap=dict(common,status='OBSERVED_NUMERICAL_CORE_METADATA_NOT_ADMISSION',affinity=affinity,topology=topo,job_cpuset=cpuset,online_thread_siblings=[31,63],
            online_cpu_list_raw='0-63\n',Slurm_core_policy=policy,raw_scheduler_configuration=config_raw,scheduler=scheduler,supervisor=identity,
            native_observations_value=native,witnesses=witnesses,physical_numerical_admission=False)
        snap['filesystem']=dict(status='OBSERVED_NUMERICAL_FILESYSTEM_STAT_NOT_USER_QUOTA',path='/UNIT_NOT_REAL',device=1,
            fragment_bytes=4096,available_blocks=80*1024**3//4096,available_bytes=80*1024**3,free_bytes=81*1024**3,
            minimum_available_bytes=80*1024**3,quota_status='UNKNOWN',observed_epoch=now)
        ready=dict(job_id=job,node=node,affinity=affinity,worker_identity=identity,physical_snapshot_value=snap)
        self.refresh(ready)
        return dict(known_prior_jobs=known,remote_namespace='/UNIT_NOT_REAL'),dict(remote_root='/UNIT_NOT_REAL'),ready
    def refresh(self,ready):
        snap=ready['physical_snapshot_value']
        pin=lambda name,value:dict(path='/UNIT_NOT_REAL/'+name,sha256=hashlib.sha256(independent_peer.encoded(value)).hexdigest())
        snap['native_observations']=pin('NATIVE_OBSERVATIONS.json',snap['native_observations_value'])
        snap['witness_pins']={name:pin(name+'.json',value) for name,value in snap['witnesses'].items()}
        ready['physical_snapshot']=pin('PHYSICAL_SNAPSHOT.json',snap)
    def test_raw_four_observations_and_whole_SMT_facts(self):
        config,spec,ready=self.fixture();self.assertEqual(independent_peer.physical_facts(config,spec,ready),ready['physical_snapshot_value'])
    def test_raw_or_kernel_ownership_gaps_reject(self):
        for mutation in ['missing_record','missing_job_ancestor','foreign_cpu','extra_sibling','omitted_online_sibling','active_known_job','unreaped_helper',
                         'disk_floor','disk_quota_claim','foreign_disk']:
            config,spec,ready=self.fixture();snap=ready['physical_snapshot_value'];raw=snap['native_observations_value']['records']
            if mutation=='missing_record':raw.pop()
            elif mutation=='missing_job_ancestor':snap['job_cpuset']['job_cgroup_path']+='/step_batch'
            elif mutation=='foreign_cpu':snap['job_cpuset']['effective_cpus']=[31,62]
            elif mutation=='extra_sibling':snap['online_thread_siblings']=[31,62,63]
            elif mutation=='omitted_online_sibling':snap['online_thread_siblings']=[31];snap['job_cpuset']['effective_cpus']=[31]
            elif mutation=='active_known_job':raw[-1]['stdout']='122|r181-boundary-UNIT|RUNNING\n'
            elif mutation=='unreaped_helper':raw[0]['exact_child_reaped']=False
            elif mutation=='disk_floor':snap['filesystem']['available_blocks']-=1;snap['filesystem']['available_bytes']-=4096
            elif mutation=='disk_quota_claim':snap['filesystem']['quota_status']='UNLIMITED'
            else:snap['filesystem']['path']='/UNIT_OTHER_VOLUME'
            self.refresh(ready)
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):independent_peer.physical_facts(config,spec,ready)


class PrerequisiteProducerTests(unittest.TestCase):
    def fixture(self,folder):
        remote='/UNIT_NOT_REAL/result';returned=folder/'returned';(returned/'owner').mkdir(parents=True)
        def save(path,value):path.write_text(json.dumps(value,sort_keys=True));return preparation.h.pin(path)
        native=dict(schema='r157_traced_bootstrap_guard_receipt_v1',status='EXITED',returncode=0,
            reaped=True,drained=True,CPU_accounting_complete=True,all_newborns_kernel_traced_before_execution=True,
            tracer_death_kernel_EXITKILL_enabled=True,postbootstrap_TSYNC_scientific_fork_denial=True,scientific_target_access_handshake=True,
            remaining_owned_lifetimes=[],unexpected_untraced_child_waits=[],scientific_filter_kernel_attestation=dict(operation='SECCOMP_SET_MODE_FILTER',flags='TSYNC',kernel_return=0))
        native_pin=save(returned/'owner/owned_guard.json',native)
        outcome=dict(status='PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER',original_guard_source_preserved=True,
            owned_guard=dict(path=remote+'/owner/owned_guard.json',sha256=native_pin['sha256']))
        save(returned/'owner/RESULT.json',outcome);save(returned/'INVENTORY.json',dict(job_id='221',node='node-13'))
        installation=dict(status='INSTALLED_CODE_BYTES_ONLY_NOT_NAMESPACE_OR_SCIENTIFIC_PROOF',files=2279,bytes=275498747,job_id='221',R_HOME='/UNIT_NOT_REAL/code/R_HOME')
        result_pin=save(returned/'RESULT.json',dict(status='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER',job_id='221',node='node-13',
            role='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER',outcome=outcome,installation=installation))
        (returned/'owner/child.stdout').write_bytes(b'');(returned/'owner/child.stderr').write_bytes(b'')
        rows=[dict(relative=str(path.relative_to(returned)),bytes=path.stat().st_size,sha256=preparation.h.pin(path)['sha256'])
              for path in sorted(returned.rglob('*')) if path.is_file()]
        manifest_pin=save(returned/'RETURN_MANIFEST.json',dict(job_id='221',scope_id='UNIT_NOT_REAL',files=rows))
        account_pin=save(folder/'account.json',dict(terminal=True,complete=True,job_id='221',primary_charge_counted_once=True,canonical_primary_CPU_seconds=1.23))
        peer_pin=save(folder/'peer.json',dict(status='PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE',job_id='221',role='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER',
            result=result_pin,accounting=account_pin,return_manifest=manifest_pin))
        candidate=dict(status='ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD',role='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER',job_id='221',scope_id='UNIT_NOT_REAL',
            namespace_proved=True,scientific_boundary_proved=True,result=result_pin,full_return_manifest=manifest_pin,accounting=account_pin,
            independent_review=peer_pin,canonical_primary_CPU_seconds=1.23)
        guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=5,aggregate_CPU_seconds=.25,complete_lifecycle_wall_seconds=1,
            guardian_forced_monitor_stop=False,stdout=json.dumps(candidate),**{key:True for key in ['all_owned_descendants_reaped','independent_guardian',
                'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
        guard_pin=save(folder/'accept.guard.json',guard)
        accepted=dict(candidate,status='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE',actual_accept_action_guard=guard_pin)
        accepted_pin=save(folder/'ACCEPTED.json',accepted)
        code=[dict(relative='R_HOME/bin/exec/R',sha256=c.NATIVE_SHA,bytes=100000),dict(relative='R_HOME/bin/Rscript',sha256='b'*64,bytes=100000)]
        code += [dict(relative='R_HOME/library/UNIT/code_%04d'%i,sha256='a'*64,bytes=100000) for i in range(2277)]
        code[-1]['bytes']+=275498747-sum(row['bytes'] for row in code)
        manifests={}
        for index,(name,part) in enumerate(zip(['base_manifest.json','addon01_manifest.json','addon02_manifest.json'],[code[:680],code[680:1480],code[1480:]])):
            manifests[name]=save(folder/name,dict(files=part))
        return accepted_pin,manifests
    def test_actual_metadata_producer_paths_and_duplicate_bytes(self):
        with tempfile.TemporaryDirectory() as path:
            folder=Path(path);accepted,manifests=self.fixture(folder)
            hashes={name:pin['sha256'] for name,pin in manifests.items()}
            with patch.dict(owner.namespace_contract.INPUT_HASHES,hashes):
                receipt=preparation.prerequisite_inputs(accepted,manifests,folder/'prepared')
                bundle=preparation.h.read(receipt['bundle']);reuse=preparation.h.read(receipt['runtime_reuse'])
                self.assertEqual(len(reuse['runtime_files']),2279);self.assertFalse(receipt['target_arrays_opened'])
                self.assertTrue(owner.validate_prerequisites(bundle))
                missing='/UNIT_NOT_REAL/result/owner/child.stderr'
                bundle['artifacts']=[row for row in bundle['artifacts'] if row['logical']['path']!=missing]
                with self.assertRaises(ValueError):owner.validate_prerequisites(bundle)


class SourceTests(unittest.TestCase):
    def test_scientific_files_match_all_frozen_hashes(self):
        root=Path(__file__).absolute().parents[4]
        for relative,sha in c.SCIENCE_HASHES.items():
            with self.subTest(relative=relative):self.assertEqual(hashlib.sha256((root/relative).read_bytes()).hexdigest(),sha)
    def test_bootstrap_ack_precedes_entrypoint(self):
        raw=Path(__file__).with_name('numerical_stage_bootstrap.R').read_text()
        self.assertLess(raw.index(".Call('r157_scientific_boundary'"),raw.index('source(spec$scientific_entrypoint$path)'))
        self.assertIn("c('TOY_PARITY','ZERO_UPDATE_BRIDGE')",raw)
        self.assertNotIn("'NO3_AL300_PILOT'",raw)
    def test_no_numpy_or_R_execution_in_prepare(self):
        raw=Path(__file__).with_name('numerical_stage_prepare.py').read_text();tree=ast.parse(raw)
        imports=[n.module for n in ast.walk(tree) if isinstance(n,ast.ImportFrom)]
        self.assertNotIn('numpy',imports)
        self.assertNotIn('subprocess',raw)
    def test_numerical_owner_always_demands_current_ack(self):
        guard=dict(schema='r157_traced_bootstrap_guard_receipt_v1',status='EXITED',returncode=0)
        with self.assertRaises(ValueError):owner.accepted_guard(guard)


class BuilderTests(unittest.TestCase):
    def fixture(self,folder):
        (folder/'UNIT_CONFIG.json').write_text('{"status":"UNIT_TEST_NOT_EXECUTION_AUTHORITY"}');root=folder/'registry';root.mkdir();(root/'READY.json').write_text('{}');(root/'PACKET.json').write_text('{}');(root/'packet').mkdir();(root/'packet/SPEC.json').write_text('{}')
        remote='/unit/pricefm_SYNTHETIC_NOT_A_REAL_JOB'
        source_root=Path(__file__).absolute().parent
        sources={name:dict(path=remote+'/package/pricefm_hb/'+name,sha256=hashlib.sha256((source_root/name).read_bytes()).hexdigest()) for name in batch.NAMES}
        science={name:dict(path=remote+'/science/'+name,sha256=sha) for name,sha in c.SCIENCE_HASHES.items()}
        reuse=dict(native_R=dict(path='/unit/qualified/code/R_HOME/bin/exec/R',sha256=c.NATIVE_SHA),
                   runtime_files=[dict(path='/unit/qualified/code/R_HOME/bin/Rscript',sha256='b'*64)],
                   boundary_qualification=dict(path='/unit/qualified/RESULT.json',sha256='c'*64),accepted_boundary={'unit_test_only':True})
        reuse_path=folder/'reuse.json';reuse_path.write_text(json.dumps(reuse));pub_path=folder/'pub.json';pub_path.write_text(json.dumps(dict(commit='a'*40)))
        config=dict(role='TOY_PARITY',role_limits=limits('TOY_PARITY'),runtime_reuse=preparation.h.pin(reuse_path),
                    publication=preparation.h.pin(pub_path),source_branch='work/UNIT_TEST_NOT_AUTHORITY',node='node-13')
        spec=dict(role='TOY_PARITY',science=science,sources=sources,scope_id='UNIT_NOT_A_REAL_SCOPE',nonce='0'*32,source_commit='a'*40,
                  controls=dict(traced_guard=dict(path=remote+'/tracer.py',sha256=c.TRACE_SHA),boundary_library=dict(path=remote+'/boundary.so',sha256=c.BOUNDARY_SHA),
                                prerequisite_bundle=dict(path=remote+'/prerequisite.json',sha256='f'*64)),target_delivery=[],
                  known_prior_jobs=[dict(job_id='122',job_name='r181-boundary-UNIT',terminal=True)])
        scope=dict(expires_epoch=__import__('time').time()+3600)
        ready=dict(job_id='123',affinity=[0],inventory=dict(helpers={}),physical_snapshot=dict(path=remote+'/PHYSICAL.json',sha256='d'*64),
            physical_snapshot_value=dict(uid=__import__('os').getuid(),topology={'cpu':0},Slurm_core_policy={},
                scheduler={'end_epoch':scope['expires_epoch']},witness_pins={}))
        packet=dict(remote_root=remote,spec_sha256='e'*64)
        return config,scope,root,packet,spec,ready
    def issue_unit_files(self,output):
        review=json.loads((output/'STAGE_SOURCE_REVIEW_REQUEST.json').read_text());review['status']=review.pop('required_status');(output/'STAGE_SOURCE_REVIEW.json').write_text(json.dumps(review))
        grant=json.loads((output/'STAGE_GRANT_TEMPLATE.json').read_text());grant['status']=grant.pop('required_status')
        grant['source_review']=dict(path='/unit/pricefm_SYNTHETIC_NOT_A_REAL_JOB/release/STAGE_SOURCE_REVIEW.json',sha256=batch.digest(output/'STAGE_SOURCE_REVIEW.json'))
        (output/'STAGE_GRANT.json').write_text(json.dumps(grant))
        for name in ['PHYSICAL_CORE_PROOF.json','PHYSICAL_CORE_REVIEW.json']:(output/name).write_text(json.dumps(dict(status='SYNTHETIC_TEST_NOT_PHYSICAL_ADMISSION')))
    def test_builder_does_not_issue_root_or_peer_authority(self):
        with tempfile.TemporaryDirectory() as path:
            folder=Path(path);context=self.fixture(folder);out=folder/'release'
            with patch.object(preparation,'context',return_value=context):preparation.prepare(str(folder/'UNIT_CONFIG.json'),out)
            for name in ['STAGE_GRANT_TEMPLATE.json','STAGE_SOURCE_REVIEW_REQUEST.json']:
                self.assertNotEqual(json.loads((out/name).read_text())['status'],json.loads((out/name).read_text())['required_status'])
            self.assertFalse((out/'RELEASE.json').exists());self.assertFalse((out/'OWNER_AUTHORITY.json').exists())
    def test_bound_owner_and_bootstrap_roundtrip_fields(self):
        with tempfile.TemporaryDirectory() as path:
            folder=Path(path);context=self.fixture(folder);out=folder/'release'
            with patch.object(preparation,'context',return_value=context):
                preparation.prepare(str(folder/'UNIT_CONFIG.json'),out);self.issue_unit_files(out);preparation.bind_owner(str(folder/'UNIT_CONFIG.json'),out)
            spec=json.loads((out/'OWNER_SPEC.json').read_text());boot=json.loads((out/'BOOTSTRAP_SPEC.json').read_text())
            self.assertEqual(spec['role'],'TOY_PARITY');self.assertEqual(boot['entrypoint_args'],[spec['science_root'],spec['stage_grant']['path'],spec['stage_grant']['sha256'],spec['output']+'/toy'])
            self.assertEqual(boot['source_parse_files'],list(spec['scientific_sources'].values()))
            extra={'R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED','R154_PROJECT_ROOT_ADMITTED','R154_PROJECT_MODE','R154_PROJECT_ADMISSION_PATH','R154_PROJECT_ADMISSION_SHA256','R154_PROJECT_RUNTIME_PATH','R154_PROJECT_RUNTIME_SHA256'}
            self.assertEqual(set(spec['environment']),set(owner.h.ENV_KEYS)|extra)
            self.assertEqual(json.loads((out/'OWNER_AUTHORITY_TEMPLATE.json').read_text())['status'],'PROPOSED_UNISSUED')
    def test_foreign_source_review_rejected_before_owner_creation(self):
        with tempfile.TemporaryDirectory() as path:
            folder=Path(path);context=self.fixture(folder);out=folder/'release'
            with patch.object(preparation,'context',return_value=context):
                preparation.prepare(str(folder/'UNIT_CONFIG.json'),out);self.issue_unit_files(out)
                review=json.loads((out/'STAGE_SOURCE_REVIEW.json').read_text());review['job_id']='999';(out/'STAGE_SOURCE_REVIEW.json').write_text(json.dumps(review))
                with self.assertRaises(ValueError):preparation.bind_owner(str(folder/'UNIT_CONFIG.json'),out)
            self.assertFalse((out/'OWNER_SPEC.json').exists())


class IndependentOpaqueMetadataTests(unittest.TestCase):
    def fixture(self,folder):
        remote='/UNIT_REMOTE/pricefm_fixture';rows=[dict(row,logical_path='/UNIT_ORIGINAL/'+row['relative']) for row in DeliveryTests().rows()]
        for row in rows:row.pop('remote')
        contract=dict(design_dir='/UNIT_ORIGINAL/design',output_dir='/UNIT_ORIGINAL/fit',parent_dir='/UNIT_ORIGINAL/parent',cran_library='/UNIT_ORIGINAL/library')
        original=dict(targets=[dict(name=c.TARGET,n=48576,p=417,tau=.75,contract=contract,
            bindings=[dict(path=row['logical_path'],sha256=row['source']['sha256']) for row in rows])])
        original_pin=self.save(folder/'UNIT_ORIGINAL_MANIFEST.json',original);scope=self.save(folder/'UNIT_SCOPE.json',{'unit_not_authority':True})
        authority=dict(status='ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY',scope=scope,target_name=c.TARGET,files=rows,original_manifest=original_pin,
            no_optimizer_or_science_execution=True,allow_opaque_transport=True,maximum_files=15,maximum_file_bytes=c.MAX_TARGET_FILE,maximum_total_bytes=c.MAX_TARGET_TOTAL)
        config=dict(role='ZERO_UPDATE_BRIDGE',node='node-13',registry=str(folder/'registry'),target_delivery=rows,scope=scope,
            original_manifest=original_pin,opaque_delivery_authority=self.save(folder/'UNIT_DELIVERY_AUTHORITY.json',authority))
        packet=dict(remote_root=remote);reuse=dict(native_R=dict(path='/UNIT_CODE/R_HOME/bin/exec/R',sha256=c.NATIVE_SHA))
        remote_rows=[dict(row,remote=dict(path=remote+'/target/'+row['relative'],sha256=row['source']['sha256'])) for row in rows]
        aliases={row['logical_path']:row['remote']['path'] for row in remote_rows}
        aliases.update({contract[key]:remote+'/target/'+name for key,name in [('design_dir','design'),('output_dir','fit'),('parent_dir','parent')]})
        aliases[contract['cran_library']]='/UNIT_CODE/R_HOME/library'
        out=folder/'registry/ZERO_UPDATE_BRIDGE/packet';out.mkdir(parents=True)
        execution=dict(schema='r182_exact_NO3_HB_alias_execution_manifest_v1',status='PREPARED_REMOTE_ALIASES_NOT_EXECUTION_AUTHORITY',
            original_manifest=dict(path=remote+'/original_target_manifest.json',sha256=original_pin['sha256']),
            execution={c.TARGET:dict(aliases=aliases,execution_host='node-13',source_host='jerez.be.ucsc.edu')},
            original_mathematical_manifest_bytes_unchanged=True,optimizer_updates=0)
        execution_pin=self.save(out/'execution_manifest.json',execution)
        spec=dict(target_delivery=remote_rows,execution_manifest=dict(path=remote+'/execution_manifest.json',sha256=execution_pin['sha256']))
        return config,spec,packet,reuse,original_pin['sha256']
    def save(self,path,value):
        preparation.h.write_new(path,value);return preparation.h.pin(path)
    def test_exact_bridge_metadata_aliases_do_not_open_target_members(self):
        with tempfile.TemporaryDirectory() as path:
            context=self.fixture(Path(path))
            with patch.object(independent_peer,'ORIGINAL_MANIFEST',context[-1]):result=independent_peer.opaque_delivery(*context[:-1])
            self.assertEqual(len(result),16);self.assertEqual(result['target/design/X.bin'][1],162049536)
            self.assertFalse(any(name.startswith('/local/') for name in independent_peer.READS))
    def test_missing_transport_or_changed_remote_alias_rejects(self):
        for mutation in ['no_transport','foreign_remote','wrong_metadata_length']:
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as path:
                context=self.fixture(Path(path));config,spec,packet,reuse,sha=context
                if mutation=='no_transport':
                    target=Path(config['opaque_delivery_authority']['path']);value=json.loads(target.read_text());value['allow_opaque_transport']=False
                    target.write_text(json.dumps(value));config['opaque_delivery_authority']=preparation.h.pin(target)
                elif mutation=='foreign_remote':spec['target_delivery'][0]['remote']['path']+='_foreign'
                else:spec['target_delivery'][0]['bytes']+=1
                with patch.object(independent_peer,'ORIGINAL_MANIFEST',sha),self.assertRaises(ValueError):independent_peer.opaque_delivery(config,spec,packet,reuse)


class NativeJournalTests(unittest.TestCase):
    """Exercise real packet/journal producers with entirely mocked transport."""
    def fixture(self,folder):
        import time
        source=Path(__file__).absolute().parent;worktree=source.parents[3];registry=folder/'registry';registry.mkdir()
        save=lambda name,value:self.save(folder/name,value)
        trace=folder/'UNIT_NEVER_EXECUTED.py';trace.write_text('# synthetic guard fixture, never executed\n')
        boundary=folder/'UNIT_NEVER_LOADED.so';boundary.write_bytes(b'synthetic boundary fixture, never loaded\n')
        item=save('UNIT_PROOF.json',dict(status='UNIT_SYNTHETIC_NOT_ACTUAL_PROOF'))
        prerequisite=save('prerequisite.json',dict(artifacts=[dict(logical=item,local=item,bytes=(folder/'UNIT_PROOF.json').stat().st_size)]))
        manifests={name:save(name,dict(files=[])) for name in ['base_manifest.json','addon01_manifest.json','addon02_manifest.json']}
        reuse_value=dict(manifest_inputs=manifests,native_R=dict(path='/UNIT_NOT_REAL/code/R_HOME/bin/exec/R',sha256=c.NATIVE_SHA))
        reuse=save('reuse.json',reuse_value);scope=dict(expires_epoch=time.time()+3600,fixed_latest_submit_epoch=time.time()+600)
        config=dict(role='TOY_PARITY',role_limits=limits('TOY_PARITY'),source_dir=str(source),registry=str(registry),
            source_branch='work/UNIT_NOT_AUTHORITY',remote_namespace='/UNIT_NOT_REAL/pricefm_r182_fixture',node='node-13',
            cached_python='/UNIT_NOT_REAL/python3.11',cached_python_sha256='c'*64,
            scientific_sources={name:preparation.h.pin(worktree/name) for name in c.SCIENCE_HASHES},
            traced_guard=preparation.h.pin(trace),boundary_library=preparation.h.pin(boundary),prerequisite_bundle=prerequisite,
            runtime_reuse=reuse,scope=save('scope.json',dict(scope,status='UNIT_SYNTHETIC_NOT_FUNDED')),
            publication=save('publication.json',dict(commit='a'*40)),source_review=item,target_delivery=[],known_prior_jobs=[])
        hashes={name:batch.digest(source/name) for name in batch.NAMES};site=dict(user='jaguir26',account='128x24',partition='128x24',qos='normal')
        root=registry/config['role'];ready_value={};calls=[]
        def native(_site,argv):
            calls.append(argv);stdout=''
            if argv[0]=='sha256sum':
                p=batch.packet(root);values={p['remote_root']+'/'+row['relative']:row['sha256'] for row in p['uploads']}
                values[config['cached_python']]=config['cached_python_sha256'];stdout=''.join(values[path]+'  '+path+'\n' for path in argv[1:])
            elif argv[0]=='sbatch':stdout='123\n'
            return dict(argv=argv,returncode=0,stdout=stdout,stderr='')
        def transport(_site,commands,path):
            if commands[0].startswith('get '):preparation.h.write_new(root/'READY.json',ready_value)
            return dict(returncode=0,stdout='',stderr='')
        def action(name,call,validate=True):
            start=batch.started_action(registry,config['role'],name);value=call();batch.pending_action(start,value)
            identity=preparation.h.read(preparation.h.pin(start));cap=batch.action_limits(name)
            guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=cap['local_CPU'],aggregate_CPU_seconds=.001,
                complete_lifecycle_wall_seconds=.001,guardian_forced_monitor_stop=False,session_id=identity['command_pid'],
                leader_start_ticks=identity['command_birth_ticks'],stdout=json.dumps(value),**{key:True for key in ['all_owned_descendants_reaped',
                    'independent_guardian','kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
            path=folder/(name+'.guard.json');preparation.h.write_new(path,guard)
            if validate:batch.finish_previous(registry,str(path))
            return value,path
        with patch.object(batch,'run_native',side_effect=native),patch.object(batch,'run_sftp',side_effect=transport):
            packet,_=action('prepare',lambda:batch.prepare(config,scope,config['role'],hashes,registry))
            stage_result,_=action('stage',lambda:batch.stage(config,site,registry,root))
            action('submit',lambda:batch.submit(config,scope,site,root))
            spec=preparation.h.read(preparation.h.pin(root/'packet/SPEC.json'))
            ready_value.update(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=config['role'],scope_id=spec['scope_id'],job_id='123',
                node='node-13',affinity=[31],cpus_per_task=1,models=0,sources=spec['sources'],spec_sha256=packet['spec_sha256'])
            _,ready_guard=action('ready',lambda:batch.ready(site,root),validate=False)
        self.assertEqual(stage_result['checksum'],preparation.h.pin(root/'STAGE_CHECKSUM.json'))
        for name in batch.NAMES:independent_peer.read_bytes(source/name,code=True)
        for pin in config['scientific_sources'].values():independent_peer.read_bytes(pin['path'],code=True)
        for pin in [*manifests.values(),config['scope']]:independent_peer.read(pin)
        return config,root,packet,spec,ready_value,str(ready_guard),reuse_value
    def save(self,path,value):
        preparation.h.write_new(path,value);return preparation.h.pin(path)
    def review(self,context):
        config=context[0]
        with patch.object(independent_peer,'TRACER',config['traced_guard']['sha256']),\
             patch.object(independent_peer,'BOUNDARY',config['boundary_library']['sha256']):
            independent_peer.packet_and_native_journals(*context)
    def test_packet_native_journals_and_durable_remote_checksums_roundtrip(self):
        with tempfile.TemporaryDirectory() as path:
            context=self.fixture(Path(path));self.review(context)
    def test_missing_checksum_or_foreign_READY_guard_reject(self):
        for mutation in ['checksum_missing','foreign_ready_birth']:
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as path:
                context=self.fixture(Path(path))
                if mutation=='checksum_missing':(context[1]/'STAGE_CHECKSUM.json').unlink()
                else:
                    guard=Path(context[5]);value=json.loads(guard.read_text());value['leader_start_ticks']+=1;guard.write_text(json.dumps(value))
                with self.assertRaises((ValueError,FileNotFoundError)):self.review(context)


class CriticalDriverTests(unittest.TestCase):
    """Synthetic transaction fixtures; subprocesses/native jobs are never run."""
    def exercise(self,folder,reject_phase=None):
        context=BuilderTests().fixture(folder);config,scope,root,packet,spec,ready=context
        config.update(source_dir=str(Path(__file__).absolute().parent),scope={'path':'/unit/scope.json','sha256':'8'*64})
        scope['allowed_metadata_output_root']=str(folder)
        ready['physical_snapshot_value']['observed_epoch']=__import__('time').time()
        (root/'READY.json').write_text(json.dumps(ready))
        authority_file=folder/'UNIT_DRIVER_AUTHORITY.json';authority_file.write_text('{"unit_fixture_only":true}')
        dummy=folder/'UNIT_NEVER_EXECUTED.py';dummy.write_text('# source fixture only\n')
        stage=folder/'UNIT_STAGE_GUARD.json';stage.write_text('{}')
        authority=dict(original_supervisor=preparation.h.pin(dummy),peer_program=preparation.h.pin(dummy),actual_stage_guard=preparation.h.pin(stage))
        actions=[];peer_phases=[]
        def popen(argv,stdout,stderr,**kwargs):
            if '--phase' in argv:
                phase=argv[argv.index('--phase')+1];peer_phases.append(phase)
                bundle=Path(argv[argv.index('--bundle')+1]);self.assertFalse((bundle/'RELEASE.json').exists())
                if phase==reject_phase:return type('NeverSpawned',(),{'wait':lambda _self:1})()
                if phase=='source_physical':
                    value=json.loads((bundle/'STAGE_SOURCE_REVIEW_REQUEST.json').read_text());value['status']=value.pop('required_status')
                    preparation.h.write_new(bundle/'STAGE_SOURCE_REVIEW.json',value)
                    preparation.h.write_new(bundle/'PHYSICAL_CORE_REVIEW.json',{'status':'UNIT_SYNTHETIC_NOT_ACTUAL_PEER_PROOF'})
                    preparation.h.write_new(bundle/'ROOT_FIELDS_RECOMMENDATION.json',dict(
                        status='PASS_REVIEWED_CONDITIONAL_ROOT_NUMERICAL_FIELDS',job_id=ready['job_id'],role=config['role'],
                        recommended_root_fields=dict(all_SMT_siblings_reserved_to_this_job=True,unreviewed_numerical_peer_intersections=[],priority_drain_complete=True)))
                else:
                    preparation.h.write_new(bundle/'OWNER_REVIEW.json',{'status':'UNIT_SYNTHETIC_NOT_ACTUAL_PEER_PROOF'})
                    labels=dict(owner_spec='OWNER_SPEC.json',owner_authority='OWNER_AUTHORITY.json',owner_review='OWNER_REVIEW.json',
                        stage_grant='STAGE_GRANT.json',stage_source_review='STAGE_SOURCE_REVIEW.json',global_contract='GLOBAL_CONTRACT.json',
                        bootstrap_spec='BOOTSTRAP_SPEC.json',physical_core_proof='PHYSICAL_CORE_PROOF.json',physical_core_review='PHYSICAL_CORE_REVIEW.json')
                    preparation.h.write_new(bundle/'PEER_RELEASE.json',dict(status='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE',
                        stage_pins={key:dict(path=packet['remote_root']+'/release/'+name,sha256=batch.digest(bundle/name)) for key,name in labels.items()}))
            else:
                action=argv[argv.index('-c')+2];actions.append(action)
                if action=='submit':preparation.h.write_new(root/'JOB.json',{'job_id':ready['job_id'],'unit_fixture_only':True})
                if action=='release':self.assertEqual(peer_phases,['source_physical','owner_release'])
                guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=int(argv[argv.index('--cpu')+1]),
                    aggregate_CPU_seconds=.001,complete_lifecycle_wall_seconds=.001,guardian_forced_monitor_stop=False,
                    **{key:True for key in ['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter',
                        'orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
                stdout.write(json.dumps(guard).encode());stdout.flush()
            return type('NeverSpawned',(),{'wait':lambda _self:0})()
        with patch.object(driver,'require_authority',return_value=(config,scope,authority,root)),\
             patch.object(preparation,'context',return_value=context),patch.object(batch,'packet',return_value=packet),\
             patch.object(driver.subprocess,'Popen',side_effect=popen),patch.object(driver.time,'sleep') as sleep:
            try:result=driver.run(str(folder/'UNIT_CONFIG.json'),preparation.h.pin(authority_file))
            except ValueError:
                self.assertIsNotNone(reject_phase);result=None
            sleep.assert_called_once_with(15)
        return result,actions,peer_phases,folder/'critical_driver'
    def test_mocked_lifecycle_is_acyclic_and_two_peers_precede_release(self):
        with tempfile.TemporaryDirectory() as path:
            result,actions,peers,out=self.exercise(Path(path))
            self.assertEqual(actions,['submit','ready','release']);self.assertEqual(peers,['source_physical','owner_release'])
            self.assertEqual(result['status'],'NATIVE_NUMERICAL_ROOT_RELEASE_ISSUED_AWAIT_COMPUTE_NOT_ACCEPTED')
            self.assertTrue((out/'RESULT.json').is_file());self.assertFalse((out/'FAILED.json').exists())
    def test_mocked_peer_rejection_never_releases_or_retries(self):
        with tempfile.TemporaryDirectory() as path:
            result,actions,peers,out=self.exercise(Path(path),reject_phase='owner_release')
            self.assertIsNone(result);self.assertEqual(actions,['submit','ready']);self.assertEqual(peers,['source_physical','owner_release'])
            self.assertTrue((out/'FAILED.json').is_file());self.assertFalse((out/'release/RELEASE.json').exists())


if __name__=='__main__':unittest.main()
