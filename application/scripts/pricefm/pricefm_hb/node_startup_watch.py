"""Paid bounded exact-READY probes; import the wait into its priced parent.
Only the probe CLI runs in a new process, beneath the unchanged original H3.
No root release, R, model, job submission, cancellation or retry is performed.
"""
import argparse
import importlib
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

if __package__ in (None,''):
    sys.path.insert(0,str(Path(__file__).absolute().parents[1]))
from pricefm_hb import startup_helper as h

PROFILE=dict(maximum_probes=10,interval_seconds=20,deadline_seconds=300,
    probe_local_CPU=3,probe_remote_unknown_fee=3,probe_wall_seconds=45,combined_startup_watch_CPU_ceiling=60)
H_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
MODULES=dict(startup='startup_batch_stop',scientific='scientific_batch',numerical='numerical_batch')


def context(config_path,role,family,authority_pin):
    h.require(family in MODULES,'exact supported producer family')
    b=importlib.import_module('pricefm_hb.'+MODULES[family]);c,s,site,_=b.load_config(config_path)
    h.require(role in b.ROLES and (family=='startup' or role==c['role']),'one exact funded role')
    authority=h.read(authority_pin);now=time.time();source=h.pin(Path(__file__).absolute())
    pub=h.read(c['publication']);review=h.read(c['source_review'])
    h.require(pub.get('extra_administrative_source_files',{}).get('node_startup_watch.py')==source['sha256'],
              'actual published extra administrative watch source')
    h.require(review.get('extra_administrative_source_files')==pub.get('extra_administrative_source_files')
              and Path(b.__file__).absolute()==Path(c['source_dir'])/(MODULES[family]+'.py'),
              'current reviewed watcher dependency closure and exact family import')
    h.require(authority.get('status')=='ROOT_AUTHORIZED_NODE_STARTUP_WATCH'
              and authority.get('config')==h.pin(config_path) and authority.get('parent_scope')==c['scope']
              and authority.get('role')==role and authority.get('family')==family and authority.get('source')==source
              and authority.get('budget')==c['startup_watch_budget'] and authority.get('profile')==PROFILE
              and all(type(authority['profile'][key]) is int for key in PROFILE)
              and type(authority.get('maximum_calls')) is int and authority['maximum_calls']==1
              and authority.get('automatic_retry') is False
              and s['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=s['expires_epoch'],
              'new complete source/config/role-bound watch authority')
    out=h.physical(c['startup_watch_roots'][role])
    h.require(str(out)==authority.get('output_root') and out.is_relative_to(h.physical(s['allowed_metadata_output_root']))
              and out!=Path(s['allowed_metadata_output_root']),'canonical private per-role watch root')
    root=Path(c['registry'])/role;p=b.packet(root);job=h.read(h.pin(root/'JOB.json'))
    h.require(b.records(root)[-1]['state']=='SUBMITTED' and not (root/'ROLE_FAILED_SPENT.json').exists()
              and job['scope_id']==p['scope_id'],'exact fresh submitted unfailed role')
    return b,c,s,site,authority,out,root,p,job


def probe(config_path,role,family,authority_pin,index):
    b,c,s,site,a,out,root,p,job=context(config_path,role,family,authority_pin)
    b.require_outer_context()
    h.require(resource.getrlimit(resource.RLIMIT_CPU)[1]==3 and type(index) is int and 0<=index<10,
              'one original H3 exact indexed probe')
    folder=out/'startup';h.require(folder.is_dir(),'paid parent creates startup folder first')
    b.one_shot(folder,'probe_%02d'%index)
    raw=b.run_native(site,['test','-f',p['remote_root']+'/READY.json'])
    h.write_new(folder/('probe_%02d.native.json'%index),raw)
    h.require(raw['returncode'] in (0,1),'transport failure is not a waiting state')
    value=dict(status='STARTUP_WAITING_READY_ABSENT_NO_RELEASE',probe_index=index,
        family=family,role=role,job_id=job['job_id'],scope_id=p['scope_id'],execution_node=c['node'],
        qualification_route_id=s['qualification_route_id'],config=h.pin(config_path),driver_authority=authority_pin,
        watch_source=h.pin(Path(__file__).absolute()),batch_source_sha256=b.digest(b.__file__),
        command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),observed_epoch=time.time(),
        raw_observation=h.pin(folder/('probe_%02d.native.json'%index)),production_admission=False)
    if raw['returncode']==0:
        resource.setrlimit(resource.RLIMIT_FSIZE,(4*1024**2,4*1024**2))
        target=folder/('probe_%02d.READY.json'%index)
        transfer=b.run_sftp(site,['get '+p['remote_root']+'/READY.json '+b.safe_path(str(target))],folder/('probe_%02d.sftp'%index))
        h.write_new(folder/('probe_%02d.transfer.json'%index),transfer)
        h.require(transfer['returncode']==0,'exact READY metadata copy failed')
        ready=h.read(h.pin(target));b.validate_ready(ready,p,job['job_id'])
        h.require(type(ready['observed_epoch']) in (int,float) and math.isfinite(ready['observed_epoch'])
                  and 0<=time.time()-ready['observed_epoch']<(180 if family=='startup' else 80 if family=='scientific' else 90)
                  and ready.get('qualification_route_id')==s['qualification_route_id'],
                  'fresh current route READY, never an old node/job snapshot')
        value.update(status='STARTUP_READY_PRESENT_MATCHED_NO_RELEASE',ready=h.pin(target))
    h.write_new(folder/('probe_%02d.RESULT.json'%index),value)
    return value


def wait(config_path,role,family,authority_pin):
    """Run in the already priced driver process; no additional SELF helper."""
    b,c,s,site,a,out,root,p,job=context(config_path,role,family,authority_pin)
    h.require(os.sched_getaffinity(0)=={31},'metadata administrative31 only')
    h.require(a['original_supervisor']['sha256']==H_SHA,'unchanged H3 guardian')
    h.read_pin(a['original_supervisor'],1024**2)
    out.mkdir(mode=0o700,exist_ok=True);(out/'startup').mkdir(mode=0o700)
    h.write_new(out/'STARTUP.INTENT.json',dict(status='PAID_NODE_STARTUP_WATCH_STARTED_NOT_READY',
        authority=authority_pin,source=h.pin(Path(__file__).absolute()),config=h.pin(config_path),role=role,family=family))
    python=str(Path(sys.executable).resolve(strict=True));start=time.monotonic();attempts=[]
    for index in range(10):
        h.require(300-(time.monotonic()-start)>=45,'remaining startup calendar cannot fit another whole H3 envelope')
        stdout=out/'startup'/('probe_%02d.guard.json'%index);stderr=out/'startup'/('probe_%02d.guard.stderr'%index)
        argv=[python,'-I','-B',a['original_supervisor']['path'],'--cpu','3','--wall','45','--output-cap','8388608','--',
              python,'-I','-B',str(Path(__file__).absolute()),'--config',config_path,'--role',role,'--family',family,
              '--authority',authority_pin['path'],'--authority-sha256',authority_pin['sha256'],'--index',str(index)]
        with stdout.open('xb') as so,stderr.open('xb') as se:
            child=subprocess.Popen(argv,stdout=so,stderr=se,preexec_fn=lambda:None);code=child.wait()
            so.flush();os.fsync(so.fileno());se.flush();os.fsync(se.fileno())
        h.require(code==0,'original probe guardian failed; exact cancellation and paid failure tail required')
        guard=h.read(h.pin(stdout))
        # No success is inferred from a process exit without actual guardian data.
        flags=['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter','orphan_subreaper',
               'guardian_included_in_CPU','inherited_waited_history_included_once']
        h.require(type(guard.get('returncode')) is int and type(guard.get('command_returncode')) is int
                  and guard['returncode']==guard['command_returncode']==0 and guard.get('cap_reason') is None
                  and type(guard.get('CPU_limit')) is int and guard['CPU_limit']==3
                  and type(guard.get('aggregate_CPU_seconds')) in (int,float)
                  and math.isfinite(guard['aggregate_CPU_seconds']) and 0<=guard['aggregate_CPU_seconds']<3
                  and type(guard.get('complete_lifecycle_wall_seconds')) in (int,float)
                  and math.isfinite(guard['complete_lifecycle_wall_seconds']) and 0<=guard['complete_lifecycle_wall_seconds']<=45
                  and guard.get('guardian_forced_monitor_stop') is False and all(guard.get(k) is True for k in flags),
                  'complete actual original H3 guardian')
        value=h.strict_json(guard['stdout'])
        h.require(value.get('probe_index')==index and value.get('config')==h.pin(config_path)
                  and value.get('driver_authority')==authority_pin and value.get('family')==family and value.get('role')==role
                  and value.get('command_pid')==guard.get('session_id')
                  and value.get('command_birth_ticks')==guard.get('leader_start_ticks'),'exact probe guard/process/source context')
        attempts.append(dict(guard=h.pin(stdout),result=value))
        h.require(time.monotonic()-start<=300,'complete startup deadline exceeded')
        if value['status']=='STARTUP_READY_PRESENT_MATCHED_NO_RELEASE':
            result=dict(status='STARTUP_READY_OBSERVED_AWAIT_ONE_SHOT_READY',attempts=attempts,profile=PROFILE,
                elapsed_seconds=time.monotonic()-start,ready=value['ready'],authority=authority_pin,family=family,role=role)
            h.write_new(out/'STARTUP_WATCH.json',result);return result
        h.require(value['status']=='STARTUP_WAITING_READY_ABSENT_NO_RELEASE','unrecognized probe outcome cannot wait')
        if index<9:
            delay=min(20,max(0,300-(time.monotonic()-start)-45))
            if delay:time.sleep(delay)  # Outside all original per-probe guardians.
    raise ValueError('ten finite startup observations exhausted; no resubmission or source/clock reset')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for key in ['config','role','family','authority','authority-sha256']:p.add_argument('--'+key,required=True)
    p.add_argument('--index',required=True,type=int);a=p.parse_args()
    print(json.dumps(probe(a.config,a.role,a.family,dict(path=a.authority,sha256=a.authority_sha256),a.index),sort_keys=True))


if __name__=='__main__':main()

