"""Independent raw-protocol fixtures; no scheduler, R or scientific values."""
import contextlib
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from . import numerical_batch as batch
from . import numerical_critical_driver as driver
from . import numerical_independent_peer as peer


class Clock:
    def __init__(self): self.now = 1800000000.
    def time(self): self.now += .01; return self.now
    def monotonic(self): return self.now
    def sleep(self, seconds): self.now += seconds


class StartupFixture:
    """Use the actual producer and watcher; native replies/H receipts are fixtures."""
    def __init__(self, folder, absent=2):
        self.folder=folder;self.clock=Clock()
        self.root=folder/'registry/ZERO_UPDATE_BRIDGE';self.root.mkdir(parents=True)
        self.startup=folder/'critical_driver/startup';self.startup.mkdir(parents=True,mode=0o700)
        self.out=folder/'critical_driver/release';self.out.mkdir(mode=0o700)
        self.cp=folder/'CONFIG.json';self.ap=folder/'AUTHORITY.json'
        source=Path(__file__).resolve().parent
        self.scope=dict(issued_epoch=self.clock.now-10,expires_epoch=self.clock.now+1000,
            allowed_metadata_output_root=str(folder),new_separate_administrative_CPU_reservation=234,
            administrative_allocations=dict(native_complete_envelope136=136,critical_driver_SELF10=10,
                independent_source_physical8=8,independent_owner_release8=8,
                independent_complete_return6=6,exact_useful_mirror4=4,closeout2=2,startup_watch60=60))
        self.sp=folder/'SCOPE.json';self.write(self.sp,self.scope)
        self.packet=dict(role='ZERO_UPDATE_BRIDGE',scope_id='SYNTHETIC_STARTUP_NONCANDIDATE',
            remote_root='/UNIT_REMOTE/SYNTHETIC_NONCANDIDATE',spec_sha256='a'*64,
            sources={'numerical_batch.py':batch.h.pin(batch.__file__)})
        self.write(self.root/'PACKET.json',self.packet)
        self.write(self.root/'JOB.json',dict(job_id='123',scope_id=self.packet['scope_id']))
        batch.append(self.root,'PREPARED',packet=batch.h.pin(self.root/'PACKET.json'))
        batch.append(self.root,'SUBMITTED')
        wp=folder/'WATCH_BUDGET.json';np=folder/'NATIVE_BUDGET.json'
        self.write(wp,dict(status='PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET',
            scope=batch.h.pin(self.sp),profile=batch.STARTUP_WATCH_PROFILE,
            issued_epoch=self.clock.now,expires_epoch=self.scope['expires_epoch']))
        self.write(np,dict(status='PROSPECTIVE_FRESH_NUMERICAL_NATIVE_CONTROL_BUDGET',
            scope=batch.h.pin(self.sp),combined_native_control_CPU_ceiling=136,
            issued_epoch=self.clock.now,expires_epoch=self.scope['expires_epoch']))
        self.config=dict(role=self.packet['role'],registry=str(self.root.parent),scope=batch.h.pin(self.sp),
            source_dir=str(source),critical_driver=batch.h.pin(driver.__file__),
            startup_watch_budget=batch.h.pin(wp),native_control_budget=batch.h.pin(np))
        self.write(self.cp,self.config)
        self.authority=dict(status='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE',
            config=batch.h.pin(self.cp),scope=self.config['scope'],driver_source=self.config['critical_driver'],
            original_supervisor=batch.h.pin(source/'profile_supervisor.py'),
            startup_watch_profile=batch.STARTUP_WATCH_PROFILE,
            startup_watch_budget=self.config['startup_watch_budget'],
            issued_epoch=self.clock.now,expires_epoch=self.scope['expires_epoch'],
            driver_maximum_wall_seconds=1200)
        self.write(self.ap,self.authority)
        self.ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',scope_id=self.packet['scope_id'],job_id='123',
            role=self.config['role'],spec_sha256=self.packet['spec_sha256'],sources=self.packet['sources'],
            node='node-13',affinity=[0],cpus_per_task=1,models=0,optimizer_invocations=0,
            physical_numerical_admission=False,physical_snapshot_value=dict(observed_epoch=self.clock.now))
        def native(site, argv):
            return dict(argv=argv,returncode=1 if self.index<absent else 0,stdout='',stderr='')
        def transfer(site, commands, path):
            path.write_text('\n'.join(commands)+'\n')
            self.write(self.startup/('probe_%02d.READY.json'%self.index),self.ready)
            return dict(returncode=0,stdout='',stderr='')
        def probe(index):
            self.index=index
            value=batch.startup_probe(str(self.cp),batch.h.pin(self.ap),index)
            observed=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=3,
                aggregate_CPU_seconds=.01,complete_lifecycle_wall_seconds=.1,
                guardian_forced_monitor_stop=False,session_id=value['command_pid'],
                leader_start_ticks=value['command_birth_ticks'],stdout=json.dumps(value))
            observed.update({k:True for k in ('all_owned_descendants_reaped','independent_guardian',
                'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU',
                'inherited_waited_history_included_once')})
            gp=self.startup/('probe_%02d.guard.json'%index);self.write(gp,observed)
            (self.startup/('probe_%02d.guard.stderr'%index)).write_text('')
            return dict(guard=batch.h.pin(gp),result=value)
        with patch.object(batch,'load_config',return_value=(self.config,self.scope,{},{})),\
             patch.object(batch,'require_outer_context'),patch.object(batch.resource,'getrlimit',return_value=(3,3)),\
             patch.object(batch.resource,'setrlimit'),patch.object(batch,'run_native',side_effect=native),\
             patch.object(batch,'run_sftp',side_effect=transfer),\
             patch.object(batch.time,'time',side_effect=self.clock.time),\
             patch.object(driver.time,'monotonic',side_effect=self.clock.monotonic),\
             patch.object(driver.time,'sleep',side_effect=self.clock.sleep):
            self.watch=driver.wait_for_startup_ready(probe,batch.STARTUP_WATCH_PROFILE)
        self.wp=folder/'critical_driver/STARTUP_WATCH.json';self.write(self.wp,self.watch)
        (self.root/'READY.json').write_bytes((self.startup/('probe_%02d.READY.json'%absent)).read_bytes())
    def write(self,path,value):path.write_text(json.dumps(value,sort_keys=True,indent=2)+'\n')
    def review(self):
        with patch.object(peer.time,'time',return_value=self.clock.now):
            return peer.startup_watch_review(str(self.cp),self.scope,self.root,self.ready,self.authority,str(self.ap))
    def change_result(self,index,mutate):
        result_path=self.startup/('probe_%02d.RESULT.json'%index)
        value=json.loads(result_path.read_text());mutate(value);self.write(result_path,value)
        gp=self.startup/('probe_%02d.guard.json'%index);g=json.loads(gp.read_text())
        g['stdout']=json.dumps(value);self.write(gp,g)
        self.watch['attempts'][index]=dict(guard=batch.h.pin(gp),result=value);self.write(self.wp,self.watch)
    def change_guard(self,index,mutate):
        gp=self.startup/('probe_%02d.guard.json'%index);g=json.loads(gp.read_text());mutate(g);self.write(gp,g)
        self.watch['attempts'][index]['guard']=batch.h.pin(gp);self.write(self.wp,self.watch)


class IndependentStartupPeerTests(unittest.TestCase):
    def fixture(self, test, absent=2):
        with tempfile.TemporaryDirectory(prefix='pricefm_independent_startup_UNIT_') as name:
            test(StartupFixture(Path(name),absent))
    def test_real_producer_delayed_watcher_independent_peer(self):
        self.fixture(lambda f:self.assertEqual(f.review(),f.watch))
    def test_one_probe_success(self):
        self.fixture(lambda f:self.assertEqual(len(f.review()['attempts']),1),absent=0)
    def test_pid_birth_and_owned_drain_flags(self):
        for key,value in [('session_id',1),('leader_start_ticks',1),
                          ('all_owned_descendants_reaped',False),
                          ('kernel_escape_filter',False),('guardian_forced_monitor_stop',True)]:
            def check(f):
                f.change_guard(0,lambda g:g.update({key:value}))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(key=key):self.fixture(check)
    def test_raw_native_command_and_transport_are_independent(self):
        for field,value in [('argv',['test','-f','/FOREIGN/READY.json']),('returncode',255),('stderr','permission denied')]:
            def check(f):
                native=f.startup/'probe_00.native.json';raw=json.loads(native.read_text());raw[field]=value;f.write(native,raw)
                f.change_result(0,lambda r:r.update(raw_observation=batch.h.pin(native)))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(field=field):self.fixture(check)
    def test_successful_final_transfer_proof_required(self):
        def check(f):
            p=f.startup/'probe_02.transfer.json';v=json.loads(p.read_text());v['returncode']=1;f.write(p,v)
            with self.assertRaises(ValueError):f.review()
        self.fixture(check)
    def test_exact_final_sftp_source_destination_and_single_command(self):
        for text in ['get /FOREIGN/READY.json /wrong.json\n','get /a /b\nget /secret /other\n']:
            def check(f):
                (f.startup/'probe_02.sftp').write_text(text)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(text=text):self.fixture(check)
    def test_contiguous_guard_result_index_source_and_authority(self):
        for key,value in [('probe_index',True),('probe_index',2),('batch_source_sha256','0'*64),
                          ('driver_authority',dict(path='/wrong.json',sha256='1'*64)),
                          ('job_id','456'),('role','TOY_PARITY'),('scope_id','FOREIGN')]:
            def check(f):
                f.change_result(0,lambda r:r.update({key:value}))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(key=key,value=value):self.fixture(check)
    def test_unknown_result_and_watch_fields_rejected(self):
        def one(f):
            f.change_result(0,lambda r:r.update(extra=True))
            with self.assertRaises(ValueError):f.review()
        def two(f):
            f.watch['extra']=True;f.write(f.wp,f.watch)
            with self.assertRaises(ValueError):f.review()
        self.fixture(one);self.fixture(two)
    def test_missing_redundant_and_foreign_probe_artifacts(self):
        def extra(f):
            (f.startup/'probe_09.intent.json').write_text('{}')
            with self.assertRaises(ValueError):f.review()
        def missing(f):
            (f.startup/'probe_02.transfer.json').unlink()
            with self.assertRaises((ValueError,FileNotFoundError)):f.review()
        self.fixture(extra);self.fixture(missing)
    def test_false_early_presence_or_missing_final_ready(self):
        def check(f):
            f.change_result(0,lambda r:r.update(status='STARTUP_READY_PRESENT_MATCHED_NO_RELEASE'))
            with self.assertRaises(ValueError):f.review()
        self.fixture(check)
    def test_snapshot_stale_future_and_observation_timestamps(self):
        for value in [-1000,float('inf'),True]:
            def check(f):
                f.change_result(0,lambda r:r.update(observed_epoch=value))
                with self.assertRaises(ValueError):f.review()
            with self.subTest(value=value):self.fixture(check)
        def stale(f):
            with patch.object(peer.time,'time',return_value=f.clock.now+100):
                with self.assertRaises(ValueError):
                    peer.startup_watch_review(str(f.cp),f.scope,f.root,f.ready,f.authority,str(f.ap))
        self.fixture(stale)
    def test_finite_elapsed_and_actual_observation_span(self):
        for value in [True,float('inf'),-1,301,0]:
            def check(f):
                f.watch['elapsed_seconds']=value;f.write(f.wp,f.watch)
                with self.assertRaises(ValueError):f.review()
            with self.subTest(value=value):self.fixture(check)
    def test_main_blocks_both_phases_before_any_pass(self):
        for phase in ['source_physical','owner_release']:
            def check(f):
                ctx=(f.config,f.scope,f.root,f.out,f.packet,{},f.ready,f.authority,{})
                f.change_guard(0,lambda g:g.update(session_id=1))
                argv=['peer.py','--phase',phase,'--config',str(f.cp),'--bundle',str(f.out),
                      '--ready-guard',str(f.startup/'probe_02.guard.json'),'--driver-authority',str(f.ap)]
                with patch('sys.argv',argv),patch.object(peer,'context',return_value=ctx),\
                     patch.object(peer.resource,'setrlimit'),patch.object(peer.signal,'alarm'),\
                     patch.object(peer,'source_phase') as source,patch.object(peer,'owner_phase') as owner:
                    with self.assertRaises(ValueError):peer.main()
                    source.assert_not_called();owner.assert_not_called()
            with self.subTest(phase=phase):self.fixture(check)




from . import numerical_owner_timestamp_tests as retained_timestamp
from . import numerical_stage_tests as retained
from . import numerical_stage_prepare as prepare
from . import numerical_stage_worker as worker
from . import startup_batch_worker as common


class IndependentDriverIntegrationTests(unittest.TestCase):
    def exercise_real_peer_main(self,folder,scope_seconds=20000,mutation=None,startup_failure=False):
        clock=retained_timestamp.AdvancingClock();actions=[];phases=[];seen={}
        with patch.object(driver.time,'time',side_effect=clock):
            context=retained.BuilderTests().fixture(folder);config,scope,root,packet,spec,ready=context
            old_root=root;root=old_root/config['role'];root.mkdir()
            for name in ['READY.json','PACKET.json','packet']:
                (old_root/name).rename(root/name)
            context=(config,scope,root,packet,spec,ready)
            physical_config,_,physical_ready=retained.IndependentPhysicalFactsTests().fixture()
            ready.update(physical_ready);snap=ready['physical_snapshot_value'];remote=packet['remote_root']
            snap['filesystem']['path']=remote
            native=snap['native_observations_value'];snap['native_observations']=dict(path=remote+'/result/physical/NATIVE_OBSERVATIONS.json',sha256=hashlib.sha256(peer.encoded(native)).hexdigest())
            snap['witness_pins']={name:dict(path=remote+'/result/physical/'+name.upper()+'.json',sha256=hashlib.sha256(peer.encoded(value)).hexdigest()) for name,value in snap['witnesses'].items()}
            ready['physical_snapshot']=dict(path=remote+'/result/PHYSICAL_SNAPSHOT.json',sha256=hashlib.sha256(peer.encoded(snap)).hexdigest())
            spec['science']=dict(sorted(spec['science'].items()));spec.update(remote_root=remote,node=ready['node'])
            packet.update(scope_id=spec['scope_id'],role=config['role'],sources=spec['sources'])
            config.update(source_dir=str(Path(__file__).absolute().parent),registry=str(root.parent),scope=dict(path='/UNIT_NOT_AUTHORITY/scope.json',sha256='8'*64),
                          known_prior_jobs=physical_config['known_prior_jobs'])
            scope.update(allowed_metadata_output_root=str(folder),issued_epoch=clock.current-10,expires_epoch=clock.current+scope_seconds,
                new_separate_administrative_CPU_reservation=234,
                administrative_allocations=dict(native_complete_envelope136=136,critical_driver_SELF10=10,
                    independent_source_physical8=8,independent_owner_release8=8,independent_complete_return6=6,
                    exact_useful_mirror4=4,closeout2=2,startup_watch60=60))
            scope_file=folder/'UNIT_REAL_SCOPE.json';prepare.h.write_new(scope_file,scope)
            config['scope']=prepare.h.pin(scope_file)
            spec['sources']['numerical_batch.py']['sha256']=batch.digest(batch.__file__)
            spec.update(expires_epoch=scope['expires_epoch'],scope=dict(path=remote+'/Q_SCOPE.json',sha256=config['scope']['sha256']))
            ready.update(role=config['role'],scope_id=spec['scope_id'],status='READY_SOURCE_BOUND_COMPUTE_METADATA',
                         models=0,optimizer_invocations=0,physical_numerical_admission=False,
                         cpus_per_task=1,sources=spec['sources'],spec_sha256=packet['spec_sha256'])
            ready['inventory']['helpers']={name:dict(resolved_file=dict(path='/UNIT_HELPERS/'+name,sha256=('%064x'%(i+1))))
                                            for i,name in enumerate(['which','uname','bash','sh','rm'])}
            prepare.h.write_new(root/'READY_ACTUAL_UNIT.json',ready)
            (root/'READY.json').write_bytes((root/'READY_ACTUAL_UNIT.json').read_bytes())
            authority_file=folder/'UNIT_NOT_AUTHORITY.json';prepare.h.write_new(authority_file,dict(synthetic_no_execution_authority=True))
            dummy=folder/'UNIT_NEVER_EXECUTED.py';dummy.write_text('# synthetic source, never executed\n')
            stage=folder/'UNIT_STAGE.json';prepare.h.write_new(stage,dict(synthetic_not_guard_proof=True))
            authority=dict(original_supervisor=prepare.h.pin(dummy),peer_program=prepare.h.pin(dummy),actual_stage_guard=prepare.h.pin(stage))
            watch_budget=folder/'UNIT_WATCH_BUDGET.json';native_budget=folder/'UNIT_NATIVE_BUDGET.json'
            prepare.h.write_new(watch_budget,dict(status='PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET',
                scope=config['scope'],profile=batch.STARTUP_WATCH_PROFILE,expires_epoch=scope['expires_epoch']))
            prepare.h.write_new(native_budget,dict(status='PROSPECTIVE_FRESH_NUMERICAL_NATIVE_CONTROL_BUDGET',
                scope=config['scope'],combined_native_control_CPU_ceiling=136,expires_epoch=scope['expires_epoch']))
            config.update(startup_watch_budget=prepare.h.pin(watch_budget),native_control_budget=prepare.h.pin(native_budget),
                          critical_driver=prepare.h.pin(driver.__file__))
            authority.update(startup_watch_profile=batch.STARTUP_WATCH_PROFILE,
                startup_watch_budget=config['startup_watch_budget'],config=None,scope=config['scope'],
                driver_source=config['critical_driver'],driver_maximum_wall_seconds=1200,
                original_supervisor=prepare.h.pin(Path(peer.__file__).parent/'profile_supervisor.py'),
                peer_program=prepare.h.pin(peer.__file__),status='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE',
                issued_epoch=scope['issued_epoch'],expires_epoch=scope['expires_epoch'])
            (folder/'UNIT_CONFIG.json').write_text(json.dumps(config,sort_keys=True)+'\n')
            authority['config']=prepare.h.pin(folder/'UNIT_CONFIG.json')
            authority_file.write_text(json.dumps(authority,sort_keys=True)+'\n')
            (root/'PACKET.json').write_text(json.dumps(packet,sort_keys=True)+'\n')
            reuse=prepare.h.read(config['runtime_reuse'])
            def peer_context(bundle):return config,scope,root,bundle,packet,spec,ready,authority,reuse
            def actual_peer_main(phase,bundle):
                if mutation=='sftp' and phase=='source_physical':
                    p=folder/'critical_driver/startup/probe_00.transfer.json'
                    value=json.loads(p.read_text());value['returncode']=1;p.write_text(json.dumps(value))
                argv=[str(peer.__file__),'--phase',phase,'--config',str(folder/'UNIT_CONFIG.json'),
                      '--bundle',str(bundle),'--ready-guard',str(folder/'critical_driver/ready.guard.json'),
                      '--driver-authority',str(authority_file)]
                with patch('sys.argv',argv),patch.object(peer,'context',return_value=peer_context(bundle)),\
                     patch.object(peer.resource,'setrlimit'),patch.object(peer.signal,'alarm'):
                    peer.main()
                seen['independent_startup_checks']=seen.get('independent_startup_checks',0)+1
            def native_child(argv,stdout,stderr,**kwargs):
                if '--phase' in argv:
                    phase=argv[argv.index('--phase')+1];phases.append(phase);bundle=Path(argv[argv.index('--bundle')+1])
                    self.assertFalse((bundle/'RELEASE.json').exists())
                    if phase=='source_physical':actual_peer_main(phase,bundle)
                    else:
                        auth_path=bundle/'OWNER_AUTHORITY.json';auth=json.loads(auth_path.read_text())
                        seen['produced_authority']=dict(auth)
                        if mutation=='overlong':auth['expires_epoch']=auth['issued_epoch']+7200.125
                        elif mutation=='expired':auth.update(issued_epoch=clock.current-600,expires_epoch=clock.current-1)
                        elif mutation=='late_issuance':auth.update(issued_epoch=clock.current+30,expires_epoch=clock.current+7230)
                        if mutation:auth_path.write_text(json.dumps(auth,sort_keys=True,indent=2)+'\n')
                        actual_peer_main(phase,bundle);seen['real_owner_phase_passed']=True
                else:
                    action=argv[argv.index('-c')+2];actions.append(action)
                    probe_value=None
                    if action=='startup_probe':
                        def transfer(site,commands,path):
                            path.write_text('\n'.join(commands)+'\n')
                            prepare.h.write_new(folder/'critical_driver/startup/probe_00.READY.json',ready)
                            return dict(returncode=0,stdout='',stderr='')
                        native=dict(argv=['test','-f',remote+'/READY.json'],returncode=0,stdout='',stderr='')
                        with patch.object(batch,'load_config',return_value=(config,scope,{},{})),\
                             patch.object(batch,'require_outer_context'),patch.object(batch.resource,'getrlimit',return_value=(3,3)),\
                             patch.object(batch.resource,'setrlimit'),patch.object(batch,'run_native',return_value=native),\
                             patch.object(batch,'run_sftp',side_effect=transfer):
                            probe_value=batch.startup_probe(str(folder/'UNIT_CONFIG.json'),prepare.h.pin(authority_file),0)
                    if action=='submit':
                        prepare.h.write_new(root/'JOB.json',dict(job_id=ready['job_id'],scope_id=spec['scope_id'],unit_not_real_job=True))
                        batch.append(root,'SUBMITTED')
                    if action=='cancel':
                        def cancelled(site,argv):seen['exact_cancel_argv']=argv;return dict(returncode=0,stdout='',stderr='')
                        seen['expected_cancel_argv']=['scancel','--user','UNIT_USER','--name',packet['scope_id'],ready['job_id']]
                        with patch.object(batch,'run_native',side_effect=cancelled):batch.cancel(dict(user='UNIT_USER'),root)
                    if action=='release':
                        self.assertEqual(phases,['source_physical','owner_release']);bundle=folder/'critical_driver/release'
                        with patch.object(batch,'run_sftp',return_value=dict(returncode=0,stdout='',stderr='')):
                            batch.release({},root,bundle)
                        value=prepare.h.read(prepare.h.pin(bundle/'RELEASE.json'));seen['real_local_release_passed']=True
                        def resolve(pin):
                            path=Path(pin['path']);self.assertEqual(path.parent,Path(remote)/'release')
                            return prepare.h.read_pin(dict(path=str(bundle/path.name),sha256=pin['sha256']))
                        ready_raw=prepare.h.read_pin(prepare.h.pin(root/'READY.json'))
                        ready_pin=dict(path=remote+'/READY.json',sha256=hashlib.sha256(ready_raw).hexdigest())
                        def read_exact(pin):return ready_raw if pin==ready_pin else resolve(pin)
                        with patch.object(common,'read_exact',side_effect=read_exact),patch.dict(worker.os.environ,SLURM_JOB_ID=ready['job_id']):
                            worker.validate_release(spec,dict(path=remote+'/SPEC.json',sha256=packet['spec_sha256']),ready_pin,
                                                    dict(path=remote+'/release/RELEASE.json',sha256=batch.digest(bundle/'RELEASE.json')),common)
                        seen['real_worker_release_passed']=True
                    guard=dict(returncode=0,command_returncode=0,cap_reason=None,CPU_limit=int(argv[argv.index('--cpu')+1]),
                        aggregate_CPU_seconds=.001,complete_lifecycle_wall_seconds=.001,guardian_forced_monitor_stop=False,
                        **{key:True for key in ['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter',
                            'orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']})
                    if probe_value is not None:
                        guard['stdout']=json.dumps(probe_value)
                        guard['session_id']=probe_value['command_pid'];guard['leader_start_ticks']=probe_value['command_birth_ticks']
                    stdout.write(json.dumps(guard).encode());stdout.flush()
                return type('NeverSpawned',(),{'wait':lambda _self:0})()
            with patch.object(driver,'require_authority',return_value=(config,scope,authority,root)),\
                 patch.object(prepare,'context',return_value=context),patch.object(batch,'packet',return_value=packet),\
                 patch.object(driver.subprocess,'Popen',side_effect=native_child),patch.object(driver.time,'sleep'),\
                 (patch.object(driver,'wait_for_startup_ready',side_effect=ValueError('unit startup deadline')) if startup_failure else contextlib.nullcontext()):
                try:seen['result']=driver.run(str(folder/'UNIT_CONFIG.json'),prepare.h.pin(authority_file))
                except ValueError as error:
                    if mutation is None and not startup_failure:raise
                    seen['rejected']=str(error)
            seen.update(actions=actions,phases=phases,clock_calls=clock.calls,scope_expiry=scope['expires_epoch'],
                        released=(folder/'critical_driver/release/RELEASE.json').exists())
            seen['role_failed_spent']=(root/'ROLE_FAILED_SPENT.json').exists()
        return seen


    def test_actual_driver_peer_main_and_both_real_release_validators(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_independent_driver_UNIT_') as p:
            seen=self.exercise_real_peer_main(Path(p))
        self.assertTrue(seen['real_owner_phase_passed'])
        self.assertTrue(seen['real_local_release_passed'])
        self.assertTrue(seen['real_worker_release_passed'])
        self.assertEqual(seen['independent_startup_checks'],2)
        self.assertEqual(seen['phases'],['source_physical','owner_release'])
        self.assertTrue(seen['released'])

    def test_failed_transfer_blocks_actual_driver_before_any_root_release(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_independent_driver_UNIT_') as p:
            seen=self.exercise_real_peer_main(Path(p),mutation='sftp')
        self.assertIn('successful final SFTP',seen['rejected'])
        self.assertFalse(seen['released'])
        self.assertEqual(seen['phases'],['source_physical'])


if __name__=='__main__':unittest.main()

