"""One bounded submit→READY→independent peers→root release invocation.

No model turn occurs inside the unchanged 120-second READY window. This
administrative program executes no R, target parsing, optimizer or login-node
payload. It never writes a peer PASS: an independently authored, hash-pinned
program must produce both actual review phases before the release is published.
There is no retry, clock extension, scope renewal or failed-role continuation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

if __package__ in (None,''):
    sys.path.insert(0,str(Path(__file__).absolute().parents[1]))
from pricefm_hb import startup_helper as h
from pricefm_hb import numerical_batch as batch
from pricefm_hb import numerical_stage_prepare as preparation
from pricefm_hb import numerical_stage_contract as contract

ORIGINAL_H_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'


def require_authority(config_path,authority_pin):
    config,scope,site,hashes=batch.load_config(config_path);authority=h.read(authority_pin);now=time.time()
    h.require(os.sched_getaffinity(0)=={31}
              and authority.get('status')=='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE'
              and authority.get('config')==h.pin(config_path) and authority.get('scope')==config['scope']
              and authority.get('driver_source')==h.pin(Path(__file__).absolute())
              and config.get('critical_driver')==authority['driver_source']
              and authority.get('role')==config['role'] and authority.get('role_limits')==config['role_limits']
              and authority.get('max_calls')==1 and authority.get('automatic_retry') is False
              and authority.get('driver_SELF_CPU_reservation')==10 and authority.get('driver_SELF_soft_CPU')==8
              and authority.get('peer_CPU_each')==8
              and authority.get('peer_phases')==['source_physical','owner_release']
              and authority.get('outside_guard_settle_seconds')==15
              and scope['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=scope['expires_epoch'],
              'new exact bounded numerical critical-driver root authority')
    h.require(authority['original_supervisor']['sha256']==ORIGINAL_H_SHA,
              'unchanged original native administrative supervisor required')
    h.read_pin(authority['original_supervisor'],limit=1024**2)
    h.read_pin(authority['peer_program'],limit=1024**2)
    publication=h.read(config['publication'])
    h.require(publication['administrative_source_files']['numerical_critical_driver.py']==authority['driver_source']['sha256']
              and publication['administrative_source_files']['numerical_independent_peer.py']==authority['peer_program']['sha256'],
              'published and independently reviewed administrative driver/peer bytes required')
    h.require(authority.get('peer_program_independently_authored_and_reviewed') is True,
              'peer program must have independent authorship and review, never a driver-generated PASS')
    root=Path(config['registry'])/config['role']
    h.require(batch.records(root)[-1]['state']=='STAGED' and not (root/'JOB.json').exists()
              and not (root/'ROLE_FAILED_SPENT.json').exists(),'fresh staged unsubmitted numerical role only')
    stage=h.read(authority['actual_stage_guard']);batch.passing_guard(stage,18,300)
    return config,scope,authority,root


def run(config_path,authority_pin):
    config,scope,authority,root=require_authority(config_path,authority_pin);base=Path(scope['allowed_metadata_output_root'])
    out=base/'critical_driver';out.mkdir(mode=0o700)
    h.write_new(out/'INTENT.json',dict(status='STARTED_BOUNDED_NUMERICAL_CRITICAL_LIFECYCLE_NOT_SUCCESS',
        authority=authority_pin,config=h.pin(config_path),driver=h.pin(Path(__file__).absolute()),
        peer_program=authority['peer_program'],old_fees_retained=True,no_retry=True))
    python=str(Path(sys.executable).resolve(strict=True));source_parent=str(Path(config['source_dir']).parent)
    command_code='import sys;sys.path.insert(0,'+repr(source_parent)+');from pricefm_hb import numerical_batch;numerical_batch.main()'
    def durable(paths):
        for path in paths:
            descriptor=os.open(path,os.O_RDONLY)
            try:os.fsync(descriptor)
            finally:os.close(descriptor)
        descriptor=os.open(out,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(descriptor)
        finally:os.close(descriptor)
    def native(action,previous):
        h.read_pin(authority['original_supervisor'],limit=1024**2)
        limits=batch.action_limits(action);stdout=out/(action+'.guard.json');stderr=out/(action+'.guard.stderr')
        argv=[python,'-I','-B',authority['original_supervisor']['path'],'--cpu',str(limits['local_CPU']),
            '--wall',str(limits['wall']),'--output-cap','8388608','--',python,'-I','-B','-c',command_code,
            action,'--config',config_path,'--role',config['role'],'--previous-guard',previous['path']]
        if action=='release':argv+=['--bundle',str(out/'release')]
        with stdout.open('xb') as stream,stderr.open('xb') as error:
            child=subprocess.Popen(argv,stdout=stream,stderr=error,preexec_fn=lambda:None)
            code=child.wait()
        durable([stdout,stderr])
        pin=h.pin(stdout);guard=h.read(pin)
        h.require(code==0,'native action failed; role/fees retained and no automatic retry')
        batch.passing_guard(guard,limits['local_CPU'],limits['wall']);return pin
    def peer(phase,bundle,ready_guard):
        h.read_pin(authority['peer_program'],limit=1024**2)
        argv=[python,'-I','-B',authority['peer_program']['path'],'--phase',phase,'--config',config_path,
              '--bundle',str(bundle),'--ready-guard',ready_guard['path'],'--driver-authority',authority_pin['path']]
        def cap():
            signal.signal(signal.SIGXCPU,signal.SIG_DFL)
            resource.setrlimit(resource.RLIMIT_CPU,(6,8));signal.alarm(30)
            resource.setrlimit(resource.RLIMIT_FSIZE,(2*1024**2,2*1024**2))
        with (out/(phase+'.peer.stdout')).open('xb') as stream,(out/(phase+'.peer.stderr')).open('xb') as error:
            child=subprocess.Popen(argv,stdout=stream,stderr=error,preexec_fn=cap);code=child.wait()
        h.require(code==0,'independent numerical peer rejected; no root release or retry')
    try:
        submit_guard=native('submit',authority['actual_stage_guard'])
        time.sleep(15)  # Outside every original per-action guardian.
        ready_guard=native('ready',submit_guard)
        ready=h.read(h.pin(root/'READY.json'));snapshot=ready['physical_snapshot_value']
        h.require(time.time()-snapshot['observed_epoch']<90,'insufficient unchanged READY window; no payload released')
        bundle=out/'release';preparation.prepare(config_path,bundle)
        peer('source_physical',bundle,ready_guard)
        remote=batch.packet(root)['remote_root']+'/release/'
        remote_pin=lambda name:dict(path=remote+name,sha256=batch.digest(bundle/name))
        recommendation=h.read(h.pin(bundle/'ROOT_FIELDS_RECOMMENDATION.json'))
        h.require(recommendation.get('status')=='PASS_REVIEWED_CONDITIONAL_ROOT_NUMERICAL_FIELDS'
                  and recommendation.get('job_id')==ready['job_id'] and recommendation.get('role')==config['role']
                  and recommendation.get('recommended_root_fields')==dict(all_SMT_siblings_reserved_to_this_job=True,
                      unreviewed_numerical_peer_intersections=[],priority_drain_complete=True),
                  'independent actual facts must establish each conditional root physical field')
        proof=h.read(h.pin(bundle/'PHYSICAL_CORE_PROOF_TEMPLATE.json'));proof['status']=proof.pop('required_status')
        proof.update(recommendation['recommended_root_fields']);proof['issued_epoch']=time.time()
        h.write_new(bundle/'PHYSICAL_CORE_PROOF.json',proof)
        grant=h.read(h.pin(bundle/'STAGE_GRANT_TEMPLATE.json'));grant['status']=grant.pop('required_status')
        grant['source_review']=remote_pin('STAGE_SOURCE_REVIEW.json');grant['issued_epoch']=time.time()
        grant['conditional_parse_and_current_kernel_ACK_required']=True;grant['driver_root_authority']=authority_pin
        h.write_new(bundle/'STAGE_GRANT.json',grant)
        preparation.bind_owner(config_path,bundle)
        owner_authority=h.read(h.pin(bundle/'OWNER_AUTHORITY_TEMPLATE.json'));owner_authority['status']=owner_authority.pop('required_status')
        owner_issued_epoch=time.time();owner_authority['issued_epoch']=owner_issued_epoch
        owner_authority['expires_epoch']=min(scope['expires_epoch'],owner_issued_epoch+7200)
        owner_authority['driver_root_authority']=authority_pin;h.write_new(bundle/'OWNER_AUTHORITY.json',owner_authority)
        peer('owner_release',bundle,ready_guard)
        proposal=preparation.release_proposal(config_path,bundle);proposal.pop('required_status');proposal['status']='ROOT_RELEASED_STARTUP_BATCH_ROLE'
        proposal['issued_epoch']=time.time();proposal['conditional_parse_and_current_kernel_ACK_required']=True
        h.require(time.time()-snapshot['observed_epoch']<90,'bounded peer/root preparation exceeded unchanged release window')
        h.write_new(bundle/'RELEASE.json',proposal)
        release_guard=native('release',ready_guard)
        result=dict(status='NATIVE_NUMERICAL_ROOT_RELEASE_ISSUED_AWAIT_COMPUTE_NOT_ACCEPTED',job=h.pin(root/'JOB.json'),
            submit_guard=submit_guard,ready_guard=ready_guard,release_guard=release_guard,root_release=h.pin(bundle/'RELEASE.json'),
            actual_independent_source_review=h.pin(bundle/'STAGE_SOURCE_REVIEW.json'),actual_independent_physical_review=h.pin(bundle/'PHYSICAL_CORE_REVIEW.json'),
            actual_independent_owner_review=h.pin(bundle/'OWNER_REVIEW.json'),actual_independent_outer_review=h.pin(bundle/'PEER_RELEASE.json'),
            old_fees_retained=True,no_R_or_optimizer_in_driver=True,no_actual_numerical_acceptance_preclaimed=True)
        h.write_new(out/'RESULT.json',result);return result
    except BaseException as error:
        h.write_new(out/'FAILED.json',dict(status='FAILED_CRITICAL_LIFECYCLE_ROLE_AND_FEES_RETAINED_NO_RETRY',
            error=type(error).__name__+': '+str(error),authority=authority_pin,no_successor_release_authority=True))
        raise


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--authority',required=True);parser.add_argument('--authority-sha256',required=True)
    args=parser.parse_args();signal.signal(signal.SIGXCPU,signal.SIG_DFL);signal.alarm(900)
    resource.setrlimit(resource.RLIMIT_CORE,(0,0));resource.setrlimit(resource.RLIMIT_CPU,(8,136))
    result=run(args.config,dict(path=args.authority,sha256=args.authority_sha256));print(json.dumps(result,sort_keys=True))


if __name__=='__main__':main()
