"""Direct batch worker for one newly funded numerical toy or zero-update bridge.

The same PID owns bootstrap, current physical-core admission, native ptrace,
R child, drain and sealing. Metadata authority never admits numerical work.
"""
import argparse
import os
from pathlib import Path
import resource
import signal
import sys
import time


def bootstrap(spec_pin):
    sys.path.insert(0,str(Path(__file__).absolute().parents[1]))
    from pricefm_hb import startup_batch_worker as common
    from pricefm_hb import numerical_batch as controller
    from pricefm_hb import numerical_stage_owner as owner
    from pricefm_hb import numerical_stage_contract as contract
    from pricefm_hb import scientific_allocation as allocation
    spec=common.read_json(common.read_exact(spec_pin))
    common.require(spec.get('schema')=='r182_numerical_batch_spec_v1' and spec.get('role') in contract.ROLES,
                   'separate supported numerical purpose')
    common.require(spec['sources']['numerical_stage_worker.py']==common.pin(Path(__file__).absolute())
                   and set(spec['sources'])==set(controller.NAMES),'complete exact numerical compute source closure')
    for pin in spec['sources'].values():common.read_exact(pin)
    for pin in spec['science'].values():common.read_exact(pin)
    scope=common.read_json(common.read_exact(spec['scope']))
    common.require(scope.get('status')=='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE'
                   and scope.get('roles')==[spec['role']] and scope.get('compute_CPU_reservation')==600
                   and scope.get('wall_seconds')==1200 and scope.get('memory_MiB')==8192
                   and scope.get('max_concurrent_jobs')==scope.get('maximum_jobs')==1
                   and scope.get('automatic_retry') is False and scope.get('requeue') is False
                   and scope['issued_epoch']<=time.time() and time.time()+1200<scope['expires_epoch']==spec['expires_epoch'],
                   'new complete numerical-stage grant, not metadata authority')
    contract.validate_role(spec['role'],spec['role_limits']);contract.validate_delivery(spec['role'],spec['target_delivery'])
    common.require(spec['aggregate_CPU_reservation']==600 and spec['wall_seconds']==1200
                   and spec['memory_MiB']==8192 and spec['threads']==1 and spec['production_fits']==0,
                   'exact complete bounded numerical resource profile')
    job=os.environ.get('SLURM_JOB_ID','');node=os.uname().nodename.split('.')[0]
    common.require(job.isdigit() and os.environ.get('SLURMD_NODENAME')==node==spec['node']=='node-13'
                   and os.environ.get('SLURM_CPUS_PER_TASK')=='1' and len(os.sched_getaffinity(0))==1
                   and os.environ.get('TZ')=='UTC','actual assigned single CPU compute allocation')
    for key in owner.h.THREAD_KEYS:common.require(os.environ.get(key)=='1','single numerical thread environment')
    common.require(common.sha(Path(sys.executable).resolve(strict=True))==spec['cached_python_sha256'],
                   'exact actual compute Python')
    from pricefm_hb import numerical_physical_admission as physical
    physical.begin_ownership()
    scheduler=allocation.live(job,node,sorted(os.sched_getaffinity(0)),minimum_remaining=1000)
    return spec,scope,common,owner,contract,job,scheduler


def validate_release(spec,spec_pin,ready_pin,release_pin,common):
    release=common.read_json(common.read_exact(release_pin));ready=common.read_json(common.read_exact(ready_pin))
    common.require(release.get('status')=='ROOT_RELEASED_STARTUP_BATCH_ROLE'
                   and release.get('purpose')=='FROZEN525_NUMERICAL_STAGE_ONLY'
                   and release.get('role')==spec['role'] and release.get('scope_id')==spec['scope_id']
                   and release.get('job_id')==ready['job_id']==os.environ['SLURM_JOB_ID']
                   and release.get('node')==ready['node']==spec['node']
                   and release.get('ready_sha256')==ready_pin['sha256'] and release.get('spec_sha256')==spec_pin['sha256']
                   and release.get('sources')==spec['sources'] and release.get('scope_sha256')==spec['scope']['sha256'],
                   'actual current numerical-purpose root release')
    common.require(release['issued_epoch']<=time.time() and time.time()+300<release['expires_epoch']<=spec['expires_epoch'],
                   'complete numerical owner/return deadline')
    folder=Path(spec['remote_root'])/'release';names=set()
    common.require(type(release.get('files')) is list and 1<=len(release['files'])<=16,'bounded exact release metadata')
    for row in release['files']:
        name=common.safe_member(row['relative']);common.require('/' not in name and name not in names and name!='RELEASE.json','unique flat release metadata')
        names.add(name);common.read_exact(dict(path=str(folder/name),sha256=row['sha256']))
    required={'owner_spec','owner_authority','owner_review','stage_grant','stage_source_review',
              'global_contract','bootstrap_spec','physical_core_proof','physical_core_review','independent_review'}
    for key in required:
        pin=release[key];common.require(Path(pin['path']).parent==folder and Path(pin['path']).name in names,'complete released stage contracts')
        common.read_exact(pin)
    peer=common.read_json(common.read_exact(release['independent_review']))
    common.require(peer.get('status')=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE'
                   and all(peer.get(k)==release[k] for k in ['role','job_id','node','ready_sha256','spec_sha256','sources'])
                   and peer.get('stage_pins')=={key:release[key] for key in required-{'independent_review'}},
                   'applicable independent numerical-purpose outer release review')
    return release


def seal(spec,job,result,common,contract):
    root=Path(spec['remote_root'])/'result';common.write_new(root/'RESULT.json',result)
    allowed,binary=contract.output_inventory(spec['role']);allowed.add('numerical/FAILED.json');rows=[]
    for path in sorted(root.rglob('*')):
        if path.is_dir():continue
        common.require(path.is_file() and not path.is_symlink() and path.stat().st_nlink==1,'regular private result bytes')
        relative=str(path.relative_to(root));common.require(relative in allowed,'result outside exact frozen producer inventory')
        size=path.stat().st_size;common.require(size<=contract.MAX_RETURN_FILE,'bounded exact numerical result file')
        if path.suffix.lower() in {'.rds','.bin'}:common.require(relative in binary,'unexpected numerical binary return')
        rows.append(dict(relative=relative,bytes=size,sha256=common.sha(path)))
    complete=result['status']=='PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER'
    common.require(len(rows)<=contract.MAX_RETURN_FILES and sum(r['bytes'] for r in rows)<=contract.MAX_RETURN_TOTAL,'finite numerical return envelope')
    if complete:common.require({r['relative'] for r in rows}==contract.output_inventory(spec['role'])[0],'exact complete frozen output inventory')
    common.write_new(root/'RETURN_MANIFEST.json',dict(schema='r182_frozen525_numerical_return_manifest_v1',
        scope_id=spec['scope_id'],job_id=job,files=rows,complete_success=complete,production_fits=0,pilot_fits=0))


def run(spec_pin):
    started=time.monotonic();spec,scope,common,owner,contract,job,scheduler=bootstrap(spec_pin)
    from pricefm_hb import numerical_physical_admission as physical
    root=Path(spec['remote_root']);result_root=root/'result';ready_pin=None;release_pin=None;outcome=None;error=None
    try:
        prerequisite=common.read_json(common.read_exact(spec['controls']['prerequisite_bundle']))
        owner.validate_prerequisites(prerequisite)
        reuse=common.read_json(common.read_exact(spec['controls']['runtime_reuse']))
        owner.validate_runtime_reuse(reuse,prerequisite)
        seen=set();total=0
        for row in reuse['runtime_files']:
            common.require(row['path'] not in seen,'unique exact reused code files');seen.add(row['path'])
            raw=common.read_exact(row,64*1024**2);total+=len(raw)
        common.require(len(seen)==2279 and total==275498747,'complete qualified code-only runtime closure')
        inventory=common.runtime_inventory(spec,job);old=reuse['inventory']
        common.require(all(inventory[k]==old[k] for k in ['libc','python','python_version'])
                       and all(inventory['uname'][i]==old['uname'][i] for i in [0,2,4]),'current numerical kernel/runtime context changed')
        for name in ['bash','sh','rm']:
            helper=(Path('/usr/bin')/name).resolve(strict=True)
            inventory['helpers'][name]=dict(logical_path='/usr/bin/'+name,resolved_file=common.pin(helper),bytes=helper.stat().st_size)
        common.require(all(inventory['helpers'][name]==old['helpers'][name] for name in ['which','uname','bash','sh','rm']),
                       'current native bootstrap helper context changed from accepted boundary')
        inventory['scheduler']=scheduler;common.write_new(result_root/'INVENTORY.json',inventory)
        snapshot=physical.capture(job,spec['node'],spec['known_prior_jobs'],result_root/'physical',disk_root=root);common.write_new(result_root/'PHYSICAL_SNAPSHOT.json',snapshot)
        identity=dict(pid=os.getpid(),start_ticks=owner.h.process_birth_ticks(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                      affinity=sorted(os.sched_getaffinity(0)),uid=os.getuid())
        ready=dict(status='READY_SOURCE_BOUND_COMPUTE_METADATA',role=spec['role'],scope_id=spec['scope_id'],job_id=job,node=spec['node'],
            spec_sha256=spec_pin['sha256'],sources=spec['sources'],affinity=identity['affinity'],cpus_per_task=1,models=0,
            optimizer_invocations=0,inventory=inventory,worker_identity=identity,physical_snapshot=common.pin(result_root/'PHYSICAL_SNAPSHOT.json'),
            physical_snapshot_value=snapshot,physical_numerical_admission=False,expires_epoch=spec['expires_epoch'])
        common.publish_atomic_new(root/'READY.json',ready);ready_pin=common.pin(root/'READY.json')
        release_path=root/'release/RELEASE.json';until=time.monotonic()+120
        while not release_path.is_file() and time.monotonic()<until:time.sleep(.1)
        common.require(release_path.is_file(),'finite numerical release wait expired; no automatic retry')
        release_pin=common.pin(release_path);release=validate_release(spec,spec_pin,ready_pin,release_pin,common)
        common.write_new(result_root/'EXECUTION_CONTEXT.json',dict(spec=spec_pin,ready=ready_pin,release=release_pin))
        ospec,auth=owner.validate(release['owner_spec'],release['owner_authority'],release['owner_review'])
        expected_allowlist={row['resolved_file']['path']:row['resolved_file']['sha256'] for row in inventory['helpers'].values()}
        expected_allowlist[ospec['R_native']['path']]=contract.NATIVE_SHA
        common.require(ospec['role']==spec['role'] and ospec['job_id']==job and ospec['node']==spec['node']
                       and ospec['scope_id']==spec['scope_id'] and ospec['physical_snapshot']==ready['physical_snapshot']
                       and ospec['bootstrap_exec_allowlist']==expected_allowlist
                       and ospec['stage_grant']==release['stage_grant'] and ospec['bootstrap_spec']==release['bootstrap_spec']
                       and ospec['source_commit']==spec['source_commit']
                       and ospec['scientific_sources']==spec['science'] and ospec['target_delivery']==spec['target_delivery'],
                       'current READY/spec/grant/physical/source/delivery owner binding')
        common.require(ospec['known_prior_jobs']==spec['known_prior_jobs'],'same exact known PriceFM drain graph')
        outcome=owner.run(release['owner_spec'],release['owner_authority'],release['owner_review'],identity)
        status='PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER'
    except BaseException as exc:
        status='FAILED_FROZEN525_NUMERICAL_WORKER';error=type(exc).__name__+': '+str(exc)
    own=resource.getrusage(resource.RUSAGE_SELF);waited=resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu=own.ru_utime+own.ru_stime+waited.ru_utime+waited.ru_stime
    common.require(cpu<600 and time.monotonic()-started<1200,'whole numerical reservation exceeded')
    result=dict(status=status,role=spec['role'],scope_id=spec['scope_id'],job_id=job,node=spec['node'],spec_sha256=spec_pin['sha256'],
        sources=spec['sources'],ready=ready_pin,release=release_pin,outcome=outcome,error=error,production_fits=0,pilot_fits=0,
        whole_self_plus_waited_CPU=cpu,wall_seconds=time.monotonic()-started,canonical_primary_accounting_still_required=True)
    seal(spec,job,result,common,contract);return 0 if error is None else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--spec',required=True);parser.add_argument('--sha256',required=True)
    args=parser.parse_args();resource.setrlimit(resource.RLIMIT_CPU,(90,600));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(1200)
    raise SystemExit(run(dict(path=args.spec,sha256=args.sha256)))


if __name__=='__main__':main()
