"""One fresh Slurm allocation; data-free install and directly owned R metadata.

The unchanged ptrace owner runs in this PID, never below H. Installation is
single-process code I/O. No target, numerical entrypoint or optimizer role is
supported. A fresh READY, external peer/root release and full return are needed.
"""
import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import resource
import signal
import sys
import time


def require(ok,message):
    if not ok:raise ValueError(message)


def CPU():
    a=resource.getrusage(resource.RUSAGE_SELF);b=resource.getrusage(resource.RUSAGE_CHILDREN)
    return a.ru_utime+a.ru_stime,b.ru_utime+b.ru_stime


def bootstrap(spec_pin):
    sys.path.insert(0,str(Path(__file__).absolute().parents[1]))
    from pricefm_hb import startup_batch_worker as common
    from pricefm_hb import scientific_allocation as allocation
    from pricefm_hb import scientific_metadata_owner as owner
    from pricefm_hb import scientific_batch as controller
    spec=common.read_json(common.read_exact(spec_pin));root=Path(spec['remote_root'])
    require(spec.get('schema')=='pricefm_scientific_batch_spec_v1' and spec.get('role') in owner.ROLES,
            'zero-target/optimizer scientific metadata role required')
    require(spec['sources']['scientific_batch_worker.py']==common.pin(Path(__file__).absolute()),'actual source-bound worker required')
    require(set(spec['sources'])==set(controller.NAMES),'complete scientific compute source closure required')
    for pin in spec['sources'].values():common.read_exact(pin)
    for pin in spec['science'].values():common.read_exact(pin,64*1024**2)
    scope=common.read_json(common.read_exact(spec['scope']))
    require(scope.get('status')=='PROSPECTIVE_FRESH_SCIENTIFIC_METADATA_JOB_SCOPE'
            and scope.get('roles')==[spec['role']] and scope.get('maximum_jobs')==scope.get('max_concurrent_jobs')==1
            and scope.get('compute_CPU_reservation')==600 and scope.get('expires_epoch')==spec['expires_epoch']
            and scope.get('automatic_retry') is False and scope.get('requeue') is False,'fresh single-role whole scope required')
    require(time.time()+1200<spec['expires_epoch'] and spec['aggregate_CPU_reservation']==600
            and spec['wall_seconds']==1200 and spec['memory_MiB']==8192 and spec['threads']==1
            and spec['component_CPU_caps']==dict(install=60,owner=450,worker=30,batch_shell=30,launch_reserve=30)
            and spec['component_wall_caps']==dict(install=600,owner=300,release_wait=120,exit=180)
            and spec['new_models']==spec['optimizer_invocations']==0 and spec['scientific_data_read'] is False,
            'whole additive component CPU/wall/data-free bounds required')
    raw_cgroup=Path('/proc/self/cgroup').read_text()
    facts=dict(schema='pricefm_scientific_precheck_facts_v1',status='OBSERVED_OWN_JOB_FACTS_NOT_ADMISSION',
        job_id=os.environ.get('SLURM_JOB_ID'),node=os.uname().nodename,uid=os.getuid(),pid=os.getpid(),
        start_ticks=owner.h.process_birth_ticks(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        affinity=sorted(os.sched_getaffinity(0)),cgroup_raw=raw_cgroup[:16384],cgroup_truncated=len(raw_cgroup)>16384,
        CPU_rlimit=list(resource.getrlimit(resource.RLIMIT_CPU)),sources=spec['sources'],optimizer_invocations=0,scientific_data_read=False)
    common.write_new(root/'result/PRECHECK_FACTS.json',facts)
    require(len(raw_cgroup)<=16384,'own cgroup metadata exceeds bounded exact observation')
    require(os.environ.get('SLURM_JOB_ID','').isdigit() and os.environ.get('SLURMD_NODENAME')==spec['node']==scope['execution_node']==scope['qualification_node']
            and spec['node'] in ['node-%02d'%n for n in range(15,22)]
            and spec.get('qualification_route_id')==scope.get('qualification_route_id')
            and type(spec.get('qualification_route_id')) is str and len(spec['qualification_route_id'])==32
            and os.uname().nodename.split('.')[0]==spec['node'] and len(os.sched_getaffinity(0))==1
            and os.environ.get('SLURM_CPUS_PER_TASK')=='1' and os.environ.get('TZ')=='UTC',
            'actual one-CPU compute allocation only; never login')
    for key in owner.h.THREAD_KEYS:require(os.environ.get(key)=='1','single numerical thread environment required')
    require(common.sha(Path(sys.executable).resolve(strict=True))==spec['cached_python_sha256'],'actual cached compute Python required')
    prior=spec['accepted_R'];require(prior.get('role')=='EXACT_R46_STARTUP_METADATA'
        and prior.get('status')=='ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE'
        and prior.get('qualification_route_id')==spec['qualification_route_id'],'actual accepted baseR required')
    if spec['role']=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER':
        require(spec['accepted_namespace'].get('status')=='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
                and spec['accepted_namespace'].get('namespace_proved') is True
                and spec['accepted_namespace'].get('qualification_route_id')==spec['qualification_route_id'],'accepted namespace prerequisite required')
    job=os.environ['SLURM_JOB_ID'];scheduler=allocation.live(job,spec['node'],sorted(os.sched_getaffinity(0)),minimum_remaining=1000)
    return spec,scope,common,owner,job,scheduler


def validate_release(spec,spec_pin,ready_pin,release_pin,common,*,job_id=None):
    job_id=os.environ.get('SLURM_JOB_ID') if job_id is None else job_id
    release=common.read_json(common.read_exact(release_pin));ready=common.read_json(common.read_exact(ready_pin))
    require(release.get('status')=='ROOT_RELEASED_STARTUP_BATCH_ROLE' and release.get('role')==spec['role']
            and release.get('scope_id')==spec['scope_id'] and release.get('job_id')==ready['job_id']==job_id
            and release.get('node')==ready['node']==spec['node'] and release.get('ready_sha256')==ready_pin['sha256']
            and release.get('qualification_route_id')==ready.get('qualification_route_id')==spec.get('qualification_route_id')
            and release.get('spec_sha256')==spec_pin['sha256'] and release.get('sources')==spec['sources']
            and release.get('scope_sha256')==spec['scope']['sha256'],'exact root READY/source/job release required')
    require(release['issued_epoch']<=time.time() and time.time()+900<release['expires_epoch']<=spec['expires_epoch'],
            'complete install+owner+return window required')
    folder=Path(spec['remote_root'])/'release';names=set()
    require(type(release['files']) is list and 1<=len(release['files'])<=16,'bounded release metadata required')
    for row in release['files']:
        name=common.safe_member(row['relative']);require('/' not in name and name not in names and name!='RELEASE.json','flat unique release metadata required')
        names.add(name);common.read_exact(dict(path=str(folder/name),sha256=row['sha256']))
    required={'install_spec','install_authority','install_review','namespace_spec','owner_spec','owner_authority','owner_review','independent_review'}
    for key in required:
        pin=release[key];require(Path(pin['path']).parent==folder and Path(pin['path']).name in names,'all exact stage/review pins must be in release')
        common.read_exact(pin)
    peer=common.read_json(common.read_exact(release['independent_review']))
    require(peer.get('status')=='PASS_REVIEWED_STARTUP_BATCH_RELEASE' and peer.get('purpose')=='SCIENTIFIC_METADATA_ONLY'
            and all(peer.get(k)==release.get(k) for k in ['role','job_id','node','qualification_route_id','ready_sha256','spec_sha256','sources'])
            and peer.get('stage_pins')=={k:release[k] for k in required-{'independent_review'}},'independent exact stage/source release review required')
    return release


def run(spec_pin):
    started=time.monotonic()
    sys.path.insert(0,str(Path(__file__).absolute().parents[1]))
    from pricefm_hb import startup_batch_worker as common
    spec=common.read_json(common.read_exact(spec_pin));root=Path(spec['remote_root'])
    require(root==Path(__file__).absolute().parents[2] and root.stat().st_uid==os.getuid()
            and root.stat().st_mode&0o022==0,'exact staged owned worker namespace required before failure return')
    try:spec,scope,common,owner,job,scheduler=bootstrap(spec_pin)
    except BaseException as exc:
        common.seal_return(spec,os.environ.get('SLURM_JOB_ID',''),dict(status='FAILED_SCIENTIFIC_METADATA_WORKER',
            role=spec['role'],scope_id=spec['scope_id'],job_id=os.environ.get('SLURM_JOB_ID',''),node=os.uname().nodename.split('.')[0],
            spec_sha256=spec_pin['sha256'],sources=spec['sources'],ready=None,release=None,outcome=None,
            error=type(exc).__name__+': '+str(exc),allocation_admitted=False,optimizer_invocations=0,new_models=0,
            scientific_data_read=False,production_admission=False,numerical_parity_proved=False,canonical_sacct_required=True))
        return 1
    from pricefm_hb import scientific_code_install as install
    root=Path(spec['remote_root']);result_root=root/'result'
    ready_pin=None;release_pin=None;outcome=None;error=None;installation=None
    initial_self,_=CPU()
    try:
        inventory=common.runtime_inventory(spec,job);inventory['qualification_route_id']=spec['qualification_route_id']
        old=spec['accepted_R_context']['inventory']
        require(old.get('job_id')==spec['accepted_R']['job_id'] and old.get('node')==spec['node'] and old.get('qualification_route_id')==spec['qualification_route_id']
                and all(inventory[k]==old[k] for k in ['libc','python','python_version'])
                and all(inventory['uname'][i]==old['uname'][i] for i in [0,2,4])
                and all(inventory['helpers'][k]==old['helpers'][k] for k in ['which','uname']),
                'fresh actual kernel/libc/Python/native-helper compatibility with accepted exactR required')
        for name in ['bash','sh','rm']:
            path=(Path('/usr/bin')/name).resolve(strict=True)
            inventory['helpers'][name]=dict(logical_path='/usr/bin/'+name,resolved_file=common.pin(path),bytes=path.stat().st_size)
        inventory['scheduler']=scheduler;common.write_new(result_root/'INVENTORY.json',inventory)
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=spec['role'],scope_id=spec['scope_id'],job_id=job,node=spec['node'],qualification_route_id=spec['qualification_route_id'],
            spec_sha256=spec_pin['sha256'],sources=spec['sources'],affinity=inventory['affinity'],cpus_per_task=1,models=0,
            inventory=inventory,observed_epoch=time.time(),expires_epoch=spec['expires_epoch'])
        ready['worker_identity']=dict(pid=os.getpid(),start_ticks=owner.h.process_birth_ticks(),
            boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),affinity=inventory['affinity'],uid=os.getuid())
        common.publish_atomic_new(root/'READY.json',ready);ready_pin=common.pin(root/'READY.json')
        path=root/'release/RELEASE.json';until=time.monotonic()+120
        while not path.is_file() and time.monotonic()<until:time.sleep(.1)
        require(path.is_file(),'fresh finite root release window expired; no automatic payload')
        release_pin=common.pin(path);release=validate_release(spec,spec_pin,ready_pin,release_pin,common)
        common.write_new(result_root/'EXECUTION_CONTEXT.json',dict(spec=spec_pin,ready=ready_pin,release=release_pin))
        ispec=install.validate(release['install_spec'],release['install_authority'],release['install_review'])
        require(ispec['job_id']==job and ispec['node']==spec['node'] and ispec['affinity']==ready['affinity']
                and ispec['remote_namespace']==str(root) and ispec['output']==str(root/'code'),'exact current staged install context required')
        before,_=CPU();phase_start=time.monotonic()
        # Installation never forks. SIGXCPU/alarm stops this single process if
        #its60CPU/600wall component cannot finish; no R is released afterward.
        resource.setrlimit(resource.RLIMIT_CPU,(int(before)+60,600));signal.alarm(600)
        installation=install.install(ispec)
        after,_=CPU();require(after-before<60 and time.monotonic()-phase_start<600,'install component exceeded exact retained cap')
        common.write_new(result_root/'INSTALL_RESULT.json',installation)
        resource.setrlimit(resource.RLIMIT_CPU,(90,600));signal.alarm(max(1,int(1200-(time.monotonic()-started))))
        ospec,auth=owner.validate(release['owner_spec'],release['owner_authority'],release['owner_review'])
        require(ospec['role']==spec['role'] and ospec['job_id']==job and ospec['node']==spec['node'] and ospec['affinity']==ready['affinity']
                and ospec['namespace_spec']==release['namespace_spec'] and ospec['remote_namespace']==str(root)
                and ospec['output']==str(result_root/'owner'),'exact current directly owned metadata payload required')
        expected_allowlist={row['resolved_file']['path']:row['resolved_file']['sha256'] for row in ready['inventory']['helpers'].values()}
        expected_allowlist[ospec['R_native']['path']]=owner.ELF_SHA
        require(ospec['bootstrap_exec_allowlist']==expected_allowlist,'closed actual READY native helper and exactR exec allowlist required')
        outcome=owner.run(release['owner_spec'],release['owner_authority'],release['owner_review'])
        owner.validate_current_owner(common.read_json(common.read_exact(outcome['owned_guard'])),
            common.read_json(common.read_exact(outcome['owned_tree'])),ospec,release['owner_authority'],ready['worker_identity'])
        own,waited=CPU()
        require(own+waited<600 and own-(after-before)<30 and time.monotonic()-started<1200,
                'complete worker and waited CPU/wall exceed additive funding')
        status='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER'
    except BaseException as exc:
        status='FAILED_SCIENTIFIC_METADATA_WORKER';error=type(exc).__name__+': '+str(exc)
    own,waited=CPU()
    result=dict(status=status,role=spec['role'],scope_id=spec['scope_id'],job_id=job,node=spec['node'],qualification_route_id=spec['qualification_route_id'],spec_sha256=spec_pin['sha256'],
        sources=spec['sources'],ready=ready_pin,release=release_pin,outcome=outcome,error=error,installation=installation,
        optimizer_invocations=0,new_models=0,scientific_data_read=False,production_admission=False,numerical_parity_proved=False,
        worker_SELF_CPU_seconds=own,worker_waited_CPU_seconds=waited,whole_self_plus_waited_CPU=own+waited,
        wall_seconds=time.monotonic()-started,canonical_sacct_required=True,primary_charge_not_replaced_by_component_sum=True)
    common.seal_return(spec,job,result)
    return 0 if error is None else 1


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--spec',required=True);p.add_argument('--sha256',required=True);args=p.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU,(90,600));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(1200)
    raise SystemExit(run(dict(path=args.spec,sha256=args.sha256)))


if __name__=='__main__':main()
