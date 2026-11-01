"""Advancing-clock driver→real peer/release fixtures, entirely in TEMP.

No child process, scheduler, target, R, transport or actual grant is executed.
Only the prerequisite/native lifecycle context is synthetic. The actual driver
constructs its metadata and both real independent peer phases validate it;
the actual local/compute release validators consume the produced proposal.
"""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import numerical_critical_driver as driver
from . import numerical_batch as batch
from . import numerical_stage_prepare as prepare
from . import numerical_stage_worker as worker
from . import startup_batch_worker as common
from . import numerical_independent_peer as peer
from . import numerical_stage_tests as retained


class AdvancingClock:
    def __init__(self):self.current=1800000000.0;self.calls=0
    def __call__(self):
        value=self.current;self.current+=.125;self.calls+=1;return value


class OwnerTimestampTests(unittest.TestCase):
    def exercise(self,folder,scope_seconds=20000,mutation=None):
        clock=AdvancingClock();actions=[];phases=[];seen={}
        with patch.object(driver.time,'time',side_effect=clock):
            context=retained.BuilderTests().fixture(folder);config,scope,root,packet,spec,ready=context
            physical_config,_,physical_ready=retained.IndependentPhysicalFactsTests().fixture()
            ready.update(physical_ready);snap=ready['physical_snapshot_value'];remote=packet['remote_root']
            snap['filesystem']['path']=remote
            native=snap['native_observations_value'];snap['native_observations']=dict(path=remote+'/result/physical/NATIVE_OBSERVATIONS.json',sha256=hashlib.sha256(peer.encoded(native)).hexdigest())
            snap['witness_pins']={name:dict(path=remote+'/result/physical/'+name.upper()+'.json',sha256=hashlib.sha256(peer.encoded(value)).hexdigest()) for name,value in snap['witnesses'].items()}
            ready['physical_snapshot']=dict(path=remote+'/result/PHYSICAL_SNAPSHOT.json',sha256=hashlib.sha256(peer.encoded(snap)).hexdigest())
            spec['science']=dict(sorted(spec['science'].items()));spec.update(remote_root=remote,node=ready['node'])
            packet.update(scope_id=spec['scope_id'],role=config['role'],sources=spec['sources'])
            config.update(source_dir=str(Path(__file__).absolute().parent),scope=dict(path='/UNIT_NOT_AUTHORITY/scope.json',sha256='8'*64),
                          known_prior_jobs=physical_config['known_prior_jobs'])
            scope.update(allowed_metadata_output_root=str(folder),expires_epoch=clock.current+scope_seconds)
            spec.update(expires_epoch=scope['expires_epoch'],scope=dict(path=remote+'/Q_SCOPE.json',sha256=config['scope']['sha256']))
            ready.update(role=config['role'],scope_id=spec['scope_id'],status='READY_SOURCE_BOUND_COMPUTE_METADATA',
                         models=0,optimizer_invocations=0,cpus_per_task=1,sources=spec['sources'],spec_sha256=packet['spec_sha256'])
            ready['inventory']['helpers']={name:dict(resolved_file=dict(path='/UNIT_HELPERS/'+name,sha256=('%064x'%(i+1))))
                                            for i,name in enumerate(['which','uname','bash','sh','rm'])}
            prepare.h.write_new(root/'READY_ACTUAL_UNIT.json',ready)
            (root/'READY.json').write_bytes((root/'READY_ACTUAL_UNIT.json').read_bytes())
            authority_file=folder/'UNIT_NOT_AUTHORITY.json';prepare.h.write_new(authority_file,dict(synthetic_no_execution_authority=True))
            dummy=folder/'UNIT_NEVER_EXECUTED.py';dummy.write_text('# synthetic source, never executed\n')
            stage=folder/'UNIT_STAGE.json';prepare.h.write_new(stage,dict(synthetic_not_guard_proof=True))
            authority=dict(original_supervisor=prepare.h.pin(dummy),peer_program=prepare.h.pin(dummy),actual_stage_guard=prepare.h.pin(stage))
            reuse=prepare.h.read(config['runtime_reuse'])
            def peer_context(bundle):return config,scope,root,bundle,packet,spec,ready,authority,reuse
            def native_child(argv,stdout,stderr,**kwargs):
                if '--phase' in argv:
                    phase=argv[argv.index('--phase')+1];phases.append(phase);bundle=Path(argv[argv.index('--bundle')+1])
                    self.assertFalse((bundle/'RELEASE.json').exists())
                    if phase=='source_physical':peer.source_phase(peer_context(bundle))
                    else:
                        auth_path=bundle/'OWNER_AUTHORITY.json';auth=json.loads(auth_path.read_text())
                        seen['produced_authority']=dict(auth)
                        if mutation=='overlong':auth['expires_epoch']=auth['issued_epoch']+7200.125
                        elif mutation=='expired':auth.update(issued_epoch=clock.current-600,expires_epoch=clock.current-1)
                        elif mutation=='late_issuance':auth.update(issued_epoch=clock.current+30,expires_epoch=clock.current+7230)
                        if mutation:auth_path.write_text(json.dumps(auth,sort_keys=True,indent=2)+'\n')
                        peer.owner_phase(peer_context(bundle),str(authority_file));seen['real_owner_phase_passed']=True
                else:
                    action=argv[argv.index('-c')+2];actions.append(action)
                    if action=='submit':prepare.h.write_new(root/'JOB.json',dict(job_id=ready['job_id'],unit_not_real_job=True))
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
                    stdout.write(json.dumps(guard).encode());stdout.flush()
                return type('NeverSpawned',(),{'wait':lambda _self:0})()
            with patch.object(driver,'require_authority',return_value=(config,scope,authority,root)),\
                 patch.object(prepare,'context',return_value=context),patch.object(batch,'packet',return_value=packet),\
                 patch.object(driver.subprocess,'Popen',side_effect=native_child),patch.object(driver.time,'sleep'):
                try:seen['result']=driver.run(str(folder/'UNIT_CONFIG.json'),prepare.h.pin(authority_file))
                except ValueError as error:
                    if mutation is None:raise
                    seen['rejected']=str(error)
            seen.update(actions=actions,phases=phases,clock_calls=clock.calls,scope_expiry=scope['expires_epoch'],
                        released=(folder/'critical_driver/release/RELEASE.json').exists())
        return seen

    def test_advancing_clock_actual_driver_real_peers_and_both_release_validators(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_unit_r187_') as path:seen=self.exercise(Path(path))
        auth=seen['produced_authority'];self.assertEqual(auth['expires_epoch']-auth['issued_epoch'],7200)
        self.assertGreater(seen['clock_calls'],2);self.assertTrue(seen['real_owner_phase_passed'])
        self.assertTrue(seen['real_local_release_passed']);self.assertTrue(seen['real_worker_release_passed'])
        self.assertEqual(seen['actions'],['submit','ready','release']);self.assertTrue(seen['released'])

    def test_scope_expiry_clips_same_captured_epoch(self):
        with tempfile.TemporaryDirectory(prefix='pricefm_unit_r187_') as path:seen=self.exercise(Path(path),scope_seconds=900)
        auth=seen['produced_authority'];self.assertEqual(auth['expires_epoch'],seen['scope_expiry'])
        self.assertLess(auth['expires_epoch']-auth['issued_epoch'],7200);self.assertTrue(seen['real_worker_release_passed'])

    def assert_peer_rejection(self,mutation):
        with tempfile.TemporaryDirectory(prefix='pricefm_unit_r187_') as path:seen=self.exercise(Path(path),mutation=mutation)
        self.assertIn('fresh bounded owner450/child300/whole600 authority',seen['rejected'])
        self.assertEqual(seen['actions'],['submit','ready']);self.assertFalse(seen['released'])

    def test_real_peer_still_rejects_overlong_authority(self):self.assert_peer_rejection('overlong')
    def test_real_peer_still_rejects_expired_authority(self):self.assert_peer_rejection('expired')
    def test_real_peer_still_rejects_future_issuance(self):self.assert_peer_rejection('late_issuance')


if __name__=='__main__':unittest.main()
