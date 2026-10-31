"""Native control for one fresh data-free scientific namespace/boundary role.

No Python, R, supervisor or payload interpreter is executed on the login node.
Every network mutation has an exclusive durable intent. Ambiguous submission
retains its claim and never retries. Scientific output is not a supported role.
"""
import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import shlex
import signal
import subprocess
import sys
import time

from . import startup_helper as h

from . import scientific_metadata_owner as owner
from . import scientific_namespace_contract as contract
from . import scientific_code_install as installer

ROLES = tuple(owner.ROLES)
NAMES = ("__init__.py","startup_helper.py","startup_batch_worker.py","profile_admission.py","environment.py","runtime_archive.py","scientific_namespace_plan.py","scientific_namespace_contract.py","scientific_allocation.py","scientific_code_install.py","scientific_metadata_owner.py","scientific_namespace_fixture.R","scientific_boundary_fixture.R","scientific_batch.py","scientific_batch_worker.py")

NATIVE = {"mkdir", "chmod", "test", "sha256sum", "sbatch", "squeue", "sacct", "scancel", "rm", "rmdir"}
TERMINAL = {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED", "BOOT_FAIL"}
ACTION_ENVELOPE = {
    "stage": dict(local_CPU=18, remote_unknown_fee=18, wall=300, maximum_calls=1),
    "submit": dict(local_CPU=4, remote_unknown_fee=4, wall=45, maximum_calls=1),
    "ready": dict(local_CPU=6, remote_unknown_fee=6, wall=330, maximum_calls=1),
    "release": dict(local_CPU=4, remote_unknown_fee=4, wall=180, maximum_calls=1),
    "observe": dict(local_CPU=3, remote_unknown_fee=3, wall=45, maximum_calls=3),
    "collect": dict(local_CPU=6, remote_unknown_fee=6, wall=300, maximum_calls=1),
    "accept": dict(local_CPU=5, remote_unknown_fee=5, wall=180, maximum_calls=1),
    "cancel": dict(local_CPU=4, remote_unknown_fee=4, wall=45, maximum_calls=1),
}
NATIVE_CONTROL_TOTAL = 136

def safe_path(value):
    h.require(type(value) is str and re.fullmatch(r"/[A-Za-z0-9_./-]+", value)
              and ".." not in Path(value).parts, "safe absolute path required")
    return value


def canonical_identity(config):
    return {k:v for k,v in config.items() if k!='canonical_authority'}


def passing_guard(guard,CPU,wall):
    h.require(guard.get('returncode')==guard.get('command_returncode')==0 and guard.get('cap_reason') is None
              and guard.get('CPU_limit')==CPU and 0<=guard['aggregate_CPU_seconds']<CPU
              and 0<=guard['complete_lifecycle_wall_seconds']<=wall
              and all(guard.get(k) is True for k in ['all_owned_descendants_reaped','independent_guardian',
                    'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once'])
              and guard.get('guardian_forced_monitor_stop') is False,'complete original outer guard required')


def prepare_release(config_path,output):
    """Bind actual READY to UNISSUED stage specs; create no authority or PASS."""
    c,s,site,hashes=load_config(config_path);root=Path(c['registry'])/c['role'];p=packet(root)
    spec=h.read(h.pin(root/'packet/SPEC.json'));ready=h.read(h.pin(root/'READY.json'));job=h.read(h.pin(root/'JOB.json'))
    validate_ready(ready,p,job['job_id']);out=h.physical(output)
    h.require(out.is_relative_to(h.physical(s['allowed_metadata_output_root'])) and str(out)!=s['allowed_metadata_output_root'],
              'new actual release preparation stays in the proved persistent-home scope')
    out.mkdir(mode=0o700)
    remote=p['remote_root'];folder=remote+'/release';inputs=spec['inputs']
    required={'base_archive.tar.gz','base_manifest.json','addon_closure.json','addon01.tar.gz','addon01_manifest.json','addon02.tar.gz','addon02_manifest.json'}
    h.require(set(inputs)==required,'exact reviewed base and two additive code parts required')
    pins={}
    def put(name,value):
        h.write_new(out/name,value);pin=dict(path=folder+'/'+name,sha256=digest(out/name));pins[name]=pin;return pin
    ispec=dict(schema='r179_scientific_code_install_spec_v1',purpose=installer.n.PURPOSE,
        bounds=dict(files=4096,bytes=384*1024**2,one_file_bytes=64*1024**2),R_executions=0,scientific_target_data=False,optimizer_invocations=0,
        job_id=job['job_id'],node=c['node'],affinity=ready['affinity'],remote_namespace=remote,output=remote+'/code',expires_epoch=s['expires_epoch'],
        base_manifest=inputs['base_manifest.json'],base_archive=inputs['base_archive.tar.gz'],addon_manifest=inputs['addon_closure.json'],
        addons=[dict(archive=inputs['addon0'+str(i)+'.tar.gz'],manifest=inputs['addon0'+str(i)+'_manifest.json']) for i in (1,2)])
    ip=put('install_spec.json',ispec)
    fixture=spec['sources']['scientific_namespace_fixture.R'];ns=dict(schema='r179_scientific_namespace_fixture_spec_v1',job_id=job['job_id'],node=c['node'],
        affinity=ready['affinity'],optimizer_invocations=0,scientific_data_read=False,library=remote+'/code/R_HOME/library',R_HOME=remote+'/code/R_HOME',
        package_versions=contract.PACKAGE_VERSIONS,expected_stock_body_sha256=contract.STOCK_BODY_SHA,
        fixedpoint_helper=spec['science']['fixedpoint_helper.R'],namespace_fixture=fixture,scientific_boundary_library=spec['science']['boundary.so'],
        allowed_package_DLLs={remote+'/code/'+name:sha for name,sha in contract.REQUIRED_PACKAGE_DLLS.items()},
        required_package_DLLs={remote+'/code/'+name:sha for name,sha in contract.REQUIRED_PACKAGE_DLLS.items()
                               if Path(name).name in {'exdqlm.so','digest.so','jsonlite.so','Matrix.so','Rcpp.so','nimble.so'}})
    contract.validate(ns,remote);np=put('namespace_spec.json',ns)
    rh=remote+'/code/R_HOME';env={key:'1' for key in h.THREAD_KEYS}
    env.update(PATH='/usr/bin:/bin',LANG='C',LC_ALL='C',TZ='UTC',HOME=remote,TMPDIR=remote+'/tmp',R_HOME=rh,R_ARCH='',R_DOC_DIR=rh+'/doc',
               R_INCLUDE_DIR=rh+'/include',R_SHARE_DIR=rh+'/share',R_LIBS_USER=rh+'/library',R_LIBS_SITE=rh+'/library',
               LD_LIBRARY_PATH=rh+'/lib:'+remote+'/code/lib',SLURM_JOB_ID=job['job_id'],SLURMD_NODENAME=c['node'],SLURM_CPUS_PER_TASK='1')
    native=dict(path=rh+'/bin/exec/R',sha256=owner.ELF_SHA)
    allowed={row['resolved_file']['path']:row['resolved_file']['sha256'] for row in ready['inventory']['helpers'].values()}
    allowed[native['path']]=native['sha256']
    ospec=dict(schema='r179_scientific_metadata_owner_spec_v1',role=c['role'],scope_id=p['scope_id'],nonce=spec['nonce'],
        job_id=job['job_id'],node=c['node'],affinity=ready['affinity'],optimizer_invocations=0,models=0,scientific_data_read=False,
        remote_namespace=remote,output=remote+'/result/owner',traced_guard=spec['science']['traced_guard.py'],boundary_library=spec['science']['boundary.so'],
        R_native=native,fixture=spec['sources'][owner.ROLES[c['role']]],namespace_spec=np,environment=env,bootstrap_exec_allowlist=allowed)
    op=put('owner_spec.json',ospec)
    owner_sources={spec['sources'][Path(path).name]['path']:spec['sources'][Path(path).name] for path in owner.sources(c['role'])}
    install_sources={name:spec['sources'][name] for name in installer.sources()}
    proposed_expiry=min(s['expires_epoch'],time.time()+3600)
    put('install_authority_TEMPLATE.json',dict(status='PROPOSED_UNISSUED',required_status='ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY',
        spec=ip,sources=install_sources,memory_MiB=8192,max_calls=1,install_CPU_seconds=60,install_wall_seconds=600,
        whole_CPU_seconds=600,whole_wall_seconds=1200,issued_epoch=None,expires_epoch=proposed_expiry))
    put('owner_authority_TEMPLATE.json',dict(status='PROPOSED_UNISSUED',required_status='ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY',
        spec=op,sources=owner_sources,memory_MiB=8192,max_calls=1,owner_CPU_seconds=450,owner_wall_seconds=300,
        whole_CPU_seconds=600,whole_wall_seconds=1200,issued_epoch=None,expires_epoch=proposed_expiry))
    value=dict(status='PREPARED_ACTUAL_READY_BOUND_SPECS_NOT_RELEASE_OR_AUTHORITY',job_id=job['job_id'],role=c['role'],node=c['node'],
        scope=c['scope'],actual_ready=h.pin(root/'READY.json'),config=h.pin(config_path),packet=h.pin(root/'PACKET.json'),
        remote_pins=pins,sources=spec['sources'],spec_sha256=p['spec_sha256'],ready_sha256=digest(root/'READY.json'),
        remote_root=remote,scope_sha256=spec['scope']['sha256'],expires_epoch=s['expires_epoch'],no_jobs_R_or_science_executed=True,
        independent_statuses=['PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC','PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC','PASS_REVIEWED_STARTUP_BATCH_RELEASE'])
    h.write_new(out/'PREPARATION.json',value);return value


def accepted_R(value):
    record=h.read(value)
    h.require(record.get('status')=='ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE'
              and record.get('role')=='EXACT_R46_STARTUP_METADATA','actual accepted exactR metadata role required')
    guard=h.read(record['actual_accept_action_guard']);passing_guard(guard,5,180)
    candidate=h.strict_json(guard['stdout'])
    h.require(dict(candidate,status=record['status'],actual_accept_action_guard=record['actual_accept_action_guard'])==record,
              'acceptedR must equal the actual guarded acceptance candidate')
    result=h.read(record['result'])
    h.require(result.get('status')=='R46_STARTUP_METADATA_PASS_NOT_NUMERICAL_PARITY'
              and result.get('outcome',{}).get('R_startup_proved') is True
              and result['job_id']==record['job_id'],'actual compute R startup outcome required')
    return record


def accepted_R_context(value):
    record=accepted_R(value);manifest=h.read(record['full_return_manifest'])
    rows=[row for row in manifest['files'] if row['relative']=='INVENTORY.json']
    h.require(len(rows)==1,'actual acceptedR compute inventory must be in complete return')
    path=Path(record['full_return_manifest']['path']).parent/'INVENTORY.json'
    pin=dict(path=str(path),sha256=rows[0]['sha256']);inventory=h.read(pin)
    h.require(path.stat().st_size==rows[0]['bytes'] and inventory.get('job_id')==record['job_id']
              and inventory.get('node')=='node-13','exact acceptedR runtime inventory identity required')
    return dict(inventory_pin=pin,inventory=inventory)


def accepted_namespace(value,hashes):
    record=h.read(value);h.require(record.get('status')=='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
        and record.get('role')==ROLES[0] and record.get('namespace_proved') is True,'actual accepted namespace required')
    guard=h.read(record['actual_accept_action_guard']);passing_guard(guard,5,180)
    h.require(dict(h.strict_json(guard['stdout']),status=record['status'],actual_accept_action_guard=record['actual_accept_action_guard'])==record,
              'actual guarded namespace acceptance record required')
    result=h.read(record['result']);account=h.read(record['accounting'])
    h.require(result.get('status')=='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER' and result.get('role')==ROLES[0]
              and result.get('job_id')==record['job_id'] and result.get('node')=='node-13'
              and {k:v['sha256'] for k,v in result['sources'].items()}==hashes
              and account.get('complete') is True and account.get('terminal') is True
              and account.get('job_id')==record['job_id'],'complete same-source namespace result/accounting required')
    manifest=h.read(record['full_return_manifest']);base=Path(record['full_return_manifest']['path']).parent
    validate_manifest(manifest,result,record['job_id'])
    for row in manifest['files']:
        path=base/row['relative'];h.require(path.stat().st_size==row['bytes'] and digest(path)==row['sha256'],'complete namespace return drift')
    return record


def known_job(root):
    direct=root/'JOB.json';forensic=root/'RECONCILED_JOB.json'
    h.require(direct.exists() or forensic.exists(),'no exact known job; forensic reconciliation required before drain')
    return h.read(h.pin(direct if direct.exists() else forensic))


def reconcile(config,site,root):
    """One exact-nonce forensic observation; never grants release or retries."""
    p=packet(root);one_shot(root,'reconcile')
    h.require((root/'ROLE_FAILED_SPENT.json').is_file() and (root/'submit.intent.json').is_file(),
              'only an acknowledged failed submitted role can be reconciled')
    intents=[r for r in records(root) if r['state']=='SUBMISSION_INTENT']
    h.require(len(intents)==1 and '--job-name='+p['scope_id'] in intents[0]['argv']
              and intents[0]['argv'][-1]==p['remote_root']+'/job.sbatch','exact canonical submission intent/argv required')
    begin=datetime.datetime.fromtimestamp(intents[0]['epoch']-60,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
    raw=run_native(site,['sacct','--user',site['user'],'--name',p['scope_id'],'--starttime',begin,'--noheader','--parsable2',
                         '--format','JobIDRaw,JobName%128,User,UID,Account,Partition,State'])
    h.require(raw['returncode']==0,'forensic accounting transport failed; claim remains quarantined')
    rows=[line.split('|') for line in raw['stdout'].splitlines() if line.strip()]
    h.require(all(len(row)==7 for row in rows),'forensic accounting shape differs')
    primary=[r for r in rows if r[0].isdigit()]
    h.require(len(primary)==1,'missing/multiple exact submitted jobs; claim remains quarantined')
    row=primary[0];h.require(row[1]==p['scope_id'] and row[2]==site['user'] and row[3]==str(os.getuid())
        and row[4:6]==['128x24','128x24'],'foreign job name/owner/account cannot be reconciled')
    if (root/'JOB.json').exists():h.require(known_job(root)['job_id']==row[0],'durable job and scheduler disagree')
    value=dict(job_id=row[0],scope_id=p['scope_id'],status='FORENSIC_EXACT_JOB_DRAIN_ONLY_NOT_SUBMITTED_OR_RELEASE_AUTHORITY',
               observation=raw,submission_intent_epoch=intents[0]['epoch'],all_fees_retained=True)
    h.write_new(root/'RECONCILED_JOB.json',value);append(root,'FORENSIC_JOB_RECONCILED_DRAIN_ONLY',job=h.pin(root/'RECONCILED_JOB.json'))
    return value


def validate_local_release(root,bundle):
    from . import scientific_batch_worker as worker
    from . import startup_batch_worker as common
    p=packet(root);job=known_job(root);spec_pin=dict(path=p['remote_root']+'/SPEC.json',sha256=p['spec_sha256'])
    ready_pin=dict(path=p['remote_root']+'/READY.json',sha256=digest(root/'READY.json'))
    out=h.physical(bundle);release_pin=dict(path=p['remote_root']+'/release/RELEASE.json',sha256=digest(out/'RELEASE.json'))
    release=h.read(h.pin(out/'RELEASE.json'));aliases={spec_pin['path']:root/'packet/SPEC.json',ready_pin['path']:root/'READY.json',release_pin['path']:out/'RELEASE.json'}
    for row in release['files']:
        name=str(safe_relative(row['relative']));h.require('/' not in name,'flat release metadata required')
        aliases[p['remote_root']+'/release/'+name]=out/name
    class Aliases:
        read_json=staticmethod(h.strict_json)
        safe_member=staticmethod(common.safe_member)
        @staticmethod
        def read_exact(pin):
            h.require(pin['path'] in aliases,'unknown logical release alias')
            return h.read_pin(dict(path=str(aliases[pin['path']]),sha256=pin['sha256']))
    return worker.validate_release(h.read(h.pin(root/'packet/SPEC.json')),spec_pin,ready_pin,release_pin,Aliases,job_id=job['job_id'])


def load_config(path):
    h.require(os.sched_getaffinity(0)=={31},'administrative31 required')
    c=h.read(h.pin(path));s=h.read(c['scope']);now=time.time()
    h.require(c.get('schema')=='pricefm_scientific_batch_config_v1' and c.get('role') in ROLES,
              'single metadata-only scientific purpose required')
    h.require(s.get('status')=='PROSPECTIVE_FRESH_SCIENTIFIC_METADATA_JOB_SCOPE'
              and s.get('roles')==[c['role']] and s.get('maximum_jobs')==s.get('max_concurrent_jobs')==1
              and s.get('compute_CPU_reservation')==600 and s.get('wall_seconds')==1200
              and s.get('memory_MiB')==8192 and s.get('threads')==s.get('cpus_per_task')==1
              and s.get('automatic_retry') is False and s.get('requeue') is False
              and s['issued_epoch']<=now<s['expires_epoch'],'fresh finite full-purpose funding required')
    root=h.physical(s['allowed_metadata_output_root']);canonical=h.physical(c['registry'])
    h.require(str(root).startswith('/home/jaguir26/.local/state/pricefm/') and canonical.parent==root
              and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,
              'private persistent-home canonical state required')
    placement=h.read(c['placement_proof'])
    h.require(placement.get('same_original_H4_caps_and_stopped_rules') is True and placement.get('both_probe_fees_retained') is True,
              'actual originalH4 unchanged-rule placement proof required')
    rows=[r for r in placement.get('rows',[]) if r.get('label')=='home']
    h.require(len(rows)==1 and rows[0]['root']==str(root.parent) and rows[0]['device']==root.stat().st_dev
              and rows[0]['returncode']==0 and rows[0]['files']==8,'exact actual passing persistent-home root/device probe required')
    pg=h.read(rows[0]['guard']);passing_guard(pg,4,90);pv=h.strict_json(pg['stdout'])
    h.require(pv.get('status')=='OBSERVED_OWNED_METADATA_FSYNC_READBACK_NOT_LATENCY_GUARANTEE'
              and pv.get('root')==str(root.parent) and len(pv.get('rows',[]))==8,'actual passing fsync/readback payload required')
    auth=h.read(c['canonical_authority'])
    h.require(auth.get('status')=='ROOT_AUTHORIZED_CANONICAL_SCIENTIFIC_METADATA_CONFIG'
              and auth.get('binding')==canonical_identity(c) and auth.get('maximum_jobs')==1
              and s['issued_epoch']<=auth['issued_epoch']<=now<auth['expires_epoch']<=s['expires_epoch'],
              'exact fresh whole config authority required')
    budget=h.read(c['native_control_budget'])
    h.require(budget.get('status')=='PROSPECTIVE_FRESH_SCIENTIFIC_METADATA_NATIVE_CONTROL_BUDGET'
              and budget.get('combined_native_control_CPU_ceiling')==136 and budget.get('scope')==c['scope']
              and budget.get('expires_epoch')==s['expires_epoch'],'new whole native136 including forensic drain reservation required')
    safe_path(c['remote_namespace']);h.require(c['remote_namespace'].startswith('/mnt/beegfs/home/jaguir26/pricefm_r181_')
              and c['node']=='node-13','new isolated reviewed compute namespace required')
    hashes={name:digest(Path(c['source_dir'])/name) for name in NAMES}
    h.require(set(c['inputs'])==set(contract.INPUT_HASHES)
              and {name:row['sha256'] for name,row in c['inputs'].items()}==contract.INPUT_HASHES,
              'closed previously reviewed code-only archive/manifest input hashes required')
    pub=h.read(c['publication']);review=h.read(c['source_review'])
    h.require(pub.get('status')=='PASS_SCIENTIFIC_BATCH_SOURCE_PUBLICATION' and re.fullmatch('[0-9a-f]{40}',pub['commit'])
              and pub.get('source_files')==hashes and review.get('status')=='PASS_REVIEWED_SCIENTIFIC_BATCH_SOURCE'
              and review.get('source_files')==hashes,'complete published and independently reviewed source map required')
    accepted_R(c['accepted_R'])
    if c['role']==ROLES[1]:
        accepted_namespace(c['accepted_namespace'],hashes)
    return c,s,site_config(c['site']),hashes


def prepare(config,scope,role,hashes,registry):
    h.require(role==config['role'] and role in ROLES,'one funded metadata role required')
    root=registry/role;root.mkdir(mode=0o700);out=root/'packet';out.mkdir(mode=0o700)
    (out/'package/pricefm_hb').mkdir(parents=True);(out/'science').mkdir()
    token=hashlib.sha256((str(root)+str(time.time_ns())).encode()).hexdigest()[:32]
    scope_id='r181-'+('namespace-' if role==ROLES[0] else 'boundary-')+token[:20]
    remote=config['remote_namespace']+'/'+scope_id;uploads=[];sources={}
    def add(local,relative,expected=None,copy=False):
        source=h.physical(local);sha=digest(source)
        h.require(expected is None or expected==sha,'prepared bytes differ from pinned input')
        target=out/relative
        if copy:
            target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as f:f.write(source.read_bytes())
            source=target
        uploads.append(dict(local=str(source),relative=relative,sha256=sha,bytes=source.stat().st_size))
        return dict(path=remote+'/'+relative,sha256=sha)
    for name in NAMES:sources[name]=add(Path(config['source_dir'])/name,'package/pricefm_hb/'+name,hashes[name],True)
    scope_pin=add(config['scope']['path'],'Q_SCOPE.json',config['scope']['sha256'],True)
    inputs={}
    for name,row in config['inputs'].items():
        h.require(re.fullmatch('[A-Za-z0-9_.-]+',name),'flat known code archive/manifest label required')
        inputs[name]=add(row['path'],name,row['sha256'])
    science={}
    expected={'fixedpoint_helper.R':contract.FIXEDPOINT_SHA,'traced_guard.py':owner.TRACE_SHA,'boundary.so':owner.BOUNDARY_SHA}
    h.require(set(config['science'])==set(expected),'exact zero-data science control files required')
    for name,row in config['science'].items():
        h.require(row['sha256']==expected[name],'original science control source differs')
        science[name]=add(row['path'],'science/'+name,row['sha256'],True)
    spec=dict(schema='pricefm_scientific_batch_spec_v1',role=role,scope_id=scope_id,remote_root=remote,
        scope=scope_pin,source_commit=h.read(config['publication'])['commit'],sources=sources,inputs=inputs,science=science,
        cached_python=config['cached_python'],cached_python_sha256=config['cached_python_sha256'],node=config['node'],nonce=token,
        expires_epoch=scope['expires_epoch'],release_wait_seconds=120,aggregate_CPU_reservation=600,wall_seconds=1200,
        memory_MiB=8192,threads=1,component_CPU_caps=dict(install=60,owner=450,worker=30,batch_shell=30,launch_reserve=30),
        component_wall_caps=dict(install=600,owner=300,release_wait=120,exit=180),
        maximum_return_bytes=32*1024**2,maximum_return_files=4096,new_models=0,optimizer_invocations=0,scientific_data_read=False,
        accepted_R_reference=config['accepted_R'],accepted_R=accepted_R(config['accepted_R']),
        accepted_R_context=accepted_R_context(config['accepted_R']))
    if role==ROLES[1]:spec['accepted_namespace']=h.read(config['accepted_namespace'])
    h.write_new(out/'SPEC.json',spec);spec_sha=digest(out/'SPEC.json')
    #600 is the inherited ceiling, never30: a worker soft cap separately bounds
    #its own cumulative CPU while its direct unchanged tracer owns R at450.
    body='#!/bin/bash\nset -euo pipefail\numask 077\nulimit -c 0\nulimit -t 600\nexport PATH=/usr/bin:/bin\nexport TZ=UTC\n'
    body+='\n'.join('export '+k+'=1' for k in sorted(h.THREAD_KEYS))+'\n'
    body+='exec '+shlex.join([
        config['cached_python'],'-I','-B',remote+'/package/pricefm_hb/scientific_batch_worker.py','--spec',remote+'/SPEC.json','--sha256',spec_sha])+'\n'
    with (out/'job.sbatch').open('x') as f:f.write(body)
    for name in ['SPEC.json','job.sbatch']:add(out/name,name)
    value=dict(scope_id=scope_id,role=role,remote_root=remote,spec_sha256=spec_sha,uploads=uploads,sources=sources,
               source_publication=config['publication'],source_review=config['source_review'])
    h.write_new(root/'PACKET.json',value);append(root,'PREPARED',packet=h.pin(root/'PACKET.json'));return value


def submit(config,scope,site,root):
    p=packet(root);h.require(records(root)[-1]['state']=='STAGED','exact completed stage required')
    one_shot(root,'submit');h.require(time.time()<scope['fixed_latest_submit_epoch'] and time.time()+1200<scope['expires_epoch'],
                                    'full job and return must fit fixed calendar')
    queue=run_native(site,['squeue','--noheader','--user',site['user'],'--format','%i'])
    h.require(queue['returncode']==0 and not queue['stdout'].strip(),'single-job queue must be empty')
    argv=['sbatch','--parsable','--export=NONE','--propagate=NONE','--mail-type=NONE','--account='+site['account'],
        '--partition='+site['partition'],'--qos='+site['qos'],'--nodelist='+config['node'],'--nodes=1','--ntasks=1',
        '--cpus-per-task=1','--hint=nomultithread','--mem=8192M','--time=00:20:00','--no-requeue','--job-name='+p['scope_id'],
        '--output='+p['remote_root']+'/slurm-%j.out','--error='+p['remote_root']+'/slurm-%j.err',p['remote_root']+'/job.sbatch']
    append(root,'SUBMISSION_INTENT',argv=argv,whole_compute_CPU_reservation=600,automatic_retry=False)
    result=run_native(site,argv)
    h.write_new(root/'SUBMISSION_REPLY.json',result)
    append(root,'SUBMISSION_REPLY_OBSERVED_NOT_ACCEPTED',reply=h.pin(root/'SUBMISSION_REPLY.json'))
    h.require(result['returncode']==0,'submission ambiguous/spent; retain exact diagnostic and never retry')
    job_id=parse_job_id(result['stdout'])
    h.write_new(root/'JOB.json',dict(job_id=job_id,scope_id=p['scope_id'],submission=result))
    append(root,'SUBMITTED',job_id=job_id,job=h.pin(root/'JOB.json'));return dict(job_id=job_id,scope_id=p['scope_id'])


def acknowledge_failed_previous(registry,role,guard_path):
    paths=[p for p in registry.glob('control_*.started.json') if not p.with_name(p.name.replace('.started.','.validated.')).exists()
           and not p.with_name(p.name.replace('.started.','.failed_ack.')).exists()]
    h.require(len(paths)==1,'one exact failed action required');p=paths[0];v=h.read(h.pin(p));g=h.read(h.pin(guard_path))
    h.require(v['role']==role and v['source_sha256']==digest(__file__) and g['returncode']!=0
              and g.get('all_owned_descendants_reaped') is True and g.get('independent_guardian') is True
              and g.get('session_id')==v['command_pid'] and g.get('leader_start_ticks')==v['command_birth_ticks'],
              'exact failed and drained action guard required')
    record=dict(status='FAILED_ROLE_SPENT_DRAIN_OR_DIAGNOSIS_ONLY',started=h.pin(p),failed_guard=h.pin(guard_path),old_fees_retained=True)
    root=registry/role
    if not (root/'ROLE_FAILED_SPENT.json').exists():h.write_new(root/'ROLE_FAILED_SPENT.json',record)
    h.write_new(p.with_name(p.name.replace('.started.','.failed_ack.')),record)
    return record


def accept(config,site,root,actual_review):
    p=packet(root);job=h.read(h.pin(root/'JOB.json'));past=records(root);one_shot(root,'accept')
    account_pin=next(x['accounting'] for x in reversed(past) if x['state']=='OBSERVED');account=h.read(account_pin)
    returned=next(x['manifest'] for x in reversed(past) if x['state']=='RETURNED');manifest=h.read(returned)
    h.require(account['terminal'] and account['complete'],'actual successful terminal accounting required')
    validate_manifest(manifest,p,job['job_id'])
    for row in manifest['files']:
        f=root/'returned'/row['relative'];h.require(f.stat().st_size==row['bytes'] and digest(f)==row['sha256'],'complete return drift')
    result_pin=h.pin(root/'returned/RESULT.json');result=h.read(result_pin)
    h.require(result.get('status')=='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER' and result.get('role')==p['role']
              and result['scope_id']==p['scope_id'] and result['sources']==p['sources'] and result['spec_sha256']==p['spec_sha256']
              and result['job_id']==job['job_id'] and result['node']==config['node']
              and result.get('optimizer_invocations')==0 and result.get('scientific_data_read') is False,
              'actual exact data-free scientific worker result required')
    outcome=result['outcome'];expected='PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY' if p['role']==ROLES[0] else 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
    h.require(outcome.get('status')==expected and outcome.get('job_id')==job['job_id'] and outcome.get('node')==config['node']
              and outcome.get('production_admission') is False and outcome.get('numerical_parity_proved') is False,
              'actual scientific namespace/boundary result required; never numerical acceptance')
    releases=[x for x in past if x['state']=='RELEASED'];h.require(len(releases)==1,'one actual source-bound root release required')
    release_pin=releases[0]['release'];release=h.read(release_pin);bundle=Path(release_pin['path']).parent
    ready_pin=dict(path=p['remote_root']+'/READY.json',sha256=digest(root/'READY.json'))
    h.require(result.get('ready')==ready_pin and result.get('release')==dict(path=p['remote_root']+'/release/RELEASE.json',sha256=release_pin['sha256'])
              and outcome.get('spec')==release['owner_spec'] and outcome.get('authority')==release['owner_authority']
              and outcome.get('review')==release['owner_review'],'current exact READY/release/stage contracts required')
    def staged(pin):
        h.require(Path(pin['path']).parent==Path(p['remote_root'])/'release','exact release-local stage pin required')
        return h.read(dict(path=str(bundle/Path(pin['path']).name),sha256=pin['sha256']))
    ospec=staged(release['owner_spec']);ns=staged(release['namespace_spec'])
    files={p['remote_root']+'/result/'+x['relative']:x['sha256'] for x in manifest['files']}
    proof={}
    for name in ['owned_guard','owned_tree']:
        pin=outcome[name];h.require(files.get(pin['path'])==pin['sha256'],'actual original owner evidence missing from return')
        path=root/'returned'/Path(pin['path']).relative_to(p['remote_root']+'/result')
        proof[name]=h.read(dict(path=str(path),sha256=pin['sha256']))
    ready_value=h.read(h.pin(root/'READY.json'))
    h.require(outcome.get('scheduler',{}).get('uid')==ready_value['worker_identity']['uid']==os.getuid(),'actual scheduler/worker owner UID required')
    contract.validate(ns,p['remote_root']);owner.validate_frames(outcome['namespace_frames'],ospec,ns)
    owner.validate_current_owner(proof['owned_guard'],proof['owned_tree'],ospec,release['owner_authority'],ready_value['worker_identity'])
    review_pin=h.pin(actual_review);review=h.read(review_pin)
    h.require(review.get('status')=='PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE' and review.get('role')==p['role']
              and review.get('job_id')==job['job_id'] and review.get('result')==result_pin
              and review.get('return_manifest')==returned and review.get('accounting')==account_pin,
              'actual independent whole role return review required')
    queue=run_native(site,['squeue','--noheader','--user',site['user'],'--format','%i'])
    h.require(queue['returncode']==0 and job['job_id'] not in queue['stdout'].split(),'job remains queued/unknown')
    value=dict(status='ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD',role=p['role'],job_id=job['job_id'],scope_id=p['scope_id'],
        result=result_pin,full_return_manifest=returned,accounting=account_pin,canonical_primary_CPU_seconds=account['canonical_primary_CPU_seconds'],
        primary_charge_counted_once=True,independent_review=review_pin,namespace_proved=True,
        scientific_boundary_proved=p['role']==ROLES[1],numerical_parity_proved=False,production_admission=False)
    h.write_new(root/'ACCEPTANCE_CANDIDATE.json',value);append(root,'ACCEPTANCE_VALIDATED',candidate=h.pin(root/'ACCEPTANCE_CANDIDATE.json'))
    lock=config['remote_namespace']+'/qualification.lock'
    for argv in [['test','-f',lock+'/OWNED_'+p['scope_id']],['rm','--',lock+'/OWNED_'+p['scope_id']],['rmdir',lock]]:
        h.require(run_native(site,argv)['returncode']==0,'accepted output claim release incomplete; retain state')
    append(root,'ACCEPTANCE_PENDING_GUARD',candidate=h.pin(root/'ACCEPTANCE_CANDIDATE.json'),claim_released=True);return value


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','stage','submit','ready','release','observe','collect','accept','cancel','reconcile','retire_failed','finalize'])
    parser.add_argument('--config',required=True);parser.add_argument('--role',choices=ROLES,required=True)
    for name in ['bundle','actual-review','previous-guard','failed-guard']:parser.add_argument('--'+name)
    args=parser.parse_args();c,s,site,hashes=load_config(args.config);h.require(args.role==c['role'],'only the singly funded role is admitted')
    if args.action!='finalize':
        require_outer_context();h.require(resource.getrlimit(resource.RLIMIT_CPU)[1]==action_limits(args.action)['local_CPU'],'same original native action hard cap required')
    else:resource.setrlimit(resource.RLIMIT_CPU,(2,2));signal.alarm(15)
    with canonical(c) as registry:
        if args.failed_guard:
            h.require(args.action in ['cancel','reconcile','observe','collect','retire_failed','finalize'],'failed role permits drain/diagnosis only')
            acknowledge_failed_previous(registry,args.role,args.failed_guard)
        prior=finish_previous(registry,args.previous_guard)
        if args.action=='finalize':print(json.dumps(prior,sort_keys=True));return
        root=registry/args.role
        h.require(args.action not in ['prepare','stage','submit','release','accept'] or not (root/'ROLE_FAILED_SPENT.json').exists(),'failed role remains spent')
        started=started_action(registry,args.role,args.action)
        try:
            if args.action=='prepare':value=prepare(c,s,args.role,hashes,registry)
            elif args.action=='stage':value=stage(c,site,registry,root)
            elif args.action=='submit':value=submit(c,s,site,root)
            elif args.action=='ready':value=ready(site,root)
            elif args.action=='release':value=release(site,root,args.bundle)
            elif args.action=='observe':value=observe(site,root)
            elif args.action=='collect':value=collect(site,root)
            elif args.action=='accept':value=accept(c,site,root,args.actual_review)
            elif args.action=='cancel':value=cancel(site,root)
            elif args.action=='reconcile':value=reconcile(c,site,root)
            else:value=retire_failed(c,site,root,args.actual_review)
        except BaseException as error:
            if root.is_dir():append(root,'ACTION_FAILED_RETAINED',action=args.action,error=type(error).__name__+': '+str(error))
            raise
        pending_action(started,value)
    print(json.dumps(value,sort_keys=True))



def safe_relative(value):
    path = PurePosixPath(value)
    h.require(type(value) is str and re.fullmatch(r"[A-Za-z0-9_./-]+", value) and not path.is_absolute()
              and ".." not in path.parts and path.parts and not ({".ssh", ".git", ".codex"} & set(path.parts)),
              "safe metadata-relative path required")
    return path

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def native_command(argv):
    h.require(argv and argv[0] in NATIVE and all(type(x) is str and "\x00" not in x for x in argv),
              "only native administrative commands may run on login")
    return shlex.join(argv)

def site_config(value):
    site = h.read(value)
    h.require((site["host"], site["user"], site["account"], site["partition"], site["qos"])
              == ("hb.ucsc.edu", "jaguir26", "128x24", "128x24", "normal"), "verified HB association required")
    for name in ("known_hosts_file", "ssh_identity_file"):
        h.require(h.physical(site[name]).is_file(), "configured trust/identity path required")
    return site

def ssh_options(site):
    options = {"BatchMode": "yes", "StrictHostKeyChecking": "yes", "UpdateHostKeys": "no",
        "CheckHostIP": "no", "ControlMaster": "no", "ControlPath": "none", "IdentitiesOnly": "yes",
        "IdentityAgent": "none", "ForwardAgent": "no", "ClearAllForwardings": "yes",
        "PreferredAuthentications": "publickey", "PasswordAuthentication": "no", "KbdInteractiveAuthentication": "no",
        "ConnectTimeout": "10", "ConnectionAttempts": "1", "UserKnownHostsFile": site["known_hosts_file"]}
    return [item for key, value in options.items() for item in ("-o", key + "=" + value)] + ["-i", site["ssh_identity_file"]]

def run_native(site, argv, *, runner=subprocess.run):
    command = ["/usr/bin/ssh", *ssh_options(site), site["user"] + "@" + site["host"], native_command(argv)]
    # Public preexec_fn forces the reviewed fork path. There is no inner kill
    # or timeout: the actual whole-action original guardian owns both.
    result = runner(command, capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded native command output required")
    return dict(argv=argv, returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)

def run_sftp(site, commands, batch_path, *, runner=subprocess.run):
    h.require(all("\n" not in x and "\x00" not in x for x in commands), "single-line SFTP requests required")
    with Path(batch_path).open("x") as handle:
        handle.write("\n".join(commands) + "\n"); handle.flush(); os.fsync(handle.fileno())
    result = runner(["/usr/bin/sftp", "-q", "-b", str(batch_path), *ssh_options(site),
                     site["user"] + "@" + site["host"]], capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded SFTP output required")
    return dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)

def append(root, state, **fields):
    records = sorted(root.glob("record_*.json"))
    value = dict(state=state, epoch=time.time(), previous=h.pin(records[-1]) if records else None, **fields)
    path = root / ("record_%04d.json" % len(records)); h.write_new(path, value)
    return value

def records(root):
    paths = sorted(root.glob("record_*.json")); result = []; previous = None
    for path in paths:
        value = h.read(h.pin(path)); h.require(value["previous"] == previous, "canonical journal chain differs")
        result.append(value); previous = h.pin(path)
    return result

def one_shot(root, name):
    path = root / (name + ".intent.json")
    h.write_new(path, dict(status="INTENT_NOT_SUCCESS", operation=name, epoch=time.time()))
    return path

def action_limits(action):
    if action == 'reconcile': return dict(local_CPU=3,wall=120)
    if action == "prepare": return dict(local_CPU=4, wall=120)
    if action == "retire_failed": return dict(local_CPU=3, wall=120)
    return ACTION_ENVELOPE[action]

def require_outer_context():
    values = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines() if ":" in line)
    h.require(os.getpid() == os.getsid(0) == os.getpgrp()
              and values["NoNewPrivs"].strip() == "1" and values["Seccomp"].strip() == "2",
              "each native action requires the actual original outer guardian")

def started_action(registry, role, action):
    index = len(list(registry.glob("control_*.started.json")))
    path = registry / ("control_%04d.started.json" % index)
    h.write_new(path, dict(status="ACTION_STARTED_NOT_SUCCESS", role=role, action=action,
        created_epoch=time.time(), command_pid=os.getpid(), command_birth_ticks=h.process_birth_ticks(),
        source_sha256=digest(Path(__file__).absolute()), limits=action_limits(action)))
    return path

def pending_action(started, value):
    value_start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.write_new(path, dict(status="INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS",
        **{key: item for key, item in value_start.items() if key != "status"}, result=value))

def finish_previous(registry, guard_path):
    pending = sorted(x for x in registry.glob("control_*.started.json")
                     if not x.with_name(x.name.replace(".started.json", ".validated.json")).exists()
                     and not x.with_name(x.name.replace(".started.json", ".failed_ack.json")).exists())
    if not pending:
        h.require(guard_path is None, "no pending action matches supplied guard")
        return None
    h.require(len(pending) == 1 and guard_path is not None, "actual prior outer guardian required before another action")
    started = pending[0]; start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.require(path.is_file(), "prior action did not complete internal publication; retain failed guard/claim and stop")
    value = h.read(h.pin(path)); guard_pin = h.pin(guard_path); guard = h.read(guard_pin)
    h.require(all(value[key] == item for key, item in start.items() if key != "status")
              and value["source_sha256"] == digest(Path(__file__).absolute()), "pending action source/identity changed")
    limit = value["limits"]
    h.require(type(guard["returncode"]) is type(guard["command_returncode"]) is int
              and guard["returncode"] == guard["command_returncode"] == 0
              and guard.get("cap_reason") is None and type(guard["CPU_limit"]) is int and guard["CPU_limit"] == limit["local_CPU"]
              and type(guard["aggregate_CPU_seconds"]) in (int, float) and math.isfinite(guard["aggregate_CPU_seconds"])
              and 0 <= guard["aggregate_CPU_seconds"] < limit["local_CPU"]
              and type(guard["complete_lifecycle_wall_seconds"]) in (int, float)
              and math.isfinite(guard["complete_lifecycle_wall_seconds"])
              and 0 <= guard["complete_lifecycle_wall_seconds"] <= limit["wall"]
              and guard.get("guardian_forced_monitor_stop") is False
              and all(guard.get(x) is True for x in ("all_owned_descendants_reaped", "independent_guardian", "kernel_escape_filter",
                  "orphan_subreaper", "guardian_included_in_CPU", "inherited_waited_history_included_once"))
              and guard["session_id"] == value["command_pid"] and guard["leader_start_ticks"] == value["command_birth_ticks"]
              and h.strict_json(guard["stdout"]) == value["result"], "actual prior whole-action guard failed or differs")
    h.write_new(started.with_name(started.name.replace(".started.json", ".validated.json")),
                dict(status="ACTUAL_ACTION_GUARD_PASSED", started=h.pin(started), pending=h.pin(path), guard=guard_pin))
    if value["action"] == "accept":
        root = registry / value["role"]; accepted = dict(value["result"], status="ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE",
                                          actual_accept_action_guard=guard_pin)
        h.write_new(root / "ACCEPTED.json", accepted); append(root, "ACCEPTED", accepted=h.pin(root / "ACCEPTED.json"), claim_released=True)
    return dict(status="PRIOR_ACTION_GUARD_VALIDATED", action=value["action"], guard=guard_pin)

@contextlib.contextmanager
def canonical(config):
    parent = h.physical(config["registry"]); parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(parent / ".controller.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield parent
    finally:
        os.close(descriptor)

def packet(root):
    first = records(root)[0]
    h.require(first["state"] == "PREPARED" and first["packet"]["path"] == str(root / "PACKET.json"),
              "original immutable packet pin required")
    return h.read(first["packet"])

def stage(config, site, registry, root):
    p = packet(root); one_shot(root, "stage")
    h.require(not any(x["state"] in {"SUBMITTED", "AMBIGUOUS_SPENT", "RELEASED"}
                      for other in registry.iterdir() if other.is_dir() and other != root for x in records(other)[-1:]),
              "another canonical role may still own a job")
    lock = config["remote_namespace"] + "/qualification.lock"
    append(root, "STAGING_INTENT", remote_claim=lock)
    for argv in (["mkdir", "-p", "-m", "700", config["remote_namespace"]], ["mkdir", "-m", "700", lock]):
        result = run_native(site, argv); h.require(result["returncode"] == 0, "native exclusive staging/claim failed; claim retained")
    spent = run_native(site, ["mkdir", "-m", "700", config["remote_namespace"] + "/ROLE_" + p["role"] + "_SPENT"])
    if spent["returncode"] != 0:
        run_native(site, ["rmdir", lock])  # Our just-created, still-empty private claim only.
        raise ValueError("canonical remote role already spent; no cross-server replay")
    h.require(run_native(site, ["mkdir", "-m", "700", p["remote_root"]])["returncode"] == 0, "new remote role namespace required")
    commands = []
    for directory in ("package", "package/pricefm_hb", "release", "result", "tmp", "science"):
        commands.append("mkdir " + safe_path(p["remote_root"] + "/" + directory))
    marker = root / "CLAIM_MARKER"; marker.write_bytes(b"")
    commands.append("put " + safe_path(str(marker)) + " " + lock + "/OWNED_" + p["scope_id"])
    for row in p["uploads"]:
        h.require(digest(row["local"]) == row["sha256"], "local upload bytes changed")
        commands.append("put " + safe_path(row["local"]) + " " + safe_path(p["remote_root"] + "/" + row["relative"]))
    transfer = run_sftp(site, commands, root / "stage.sftp")
    h.require(transfer["returncode"] == 0, "partial or failed SFTP stage; no retry/submission allowed")
    expected = {p["remote_root"] + "/" + x["relative"]: x["sha256"] for x in p["uploads"]}
    expected[config["cached_python"]] = config["cached_python_sha256"]
    hashes = run_native(site, ["sha256sum", *sorted(expected)])
    h.require(hashes["returncode"] == 0, "native complete stage hash observation failed")
    actual = {}
    for line in hashes["stdout"].splitlines():
        parts = line.split(None, 1)
        h.require(len(parts) == 2 and re.fullmatch("[0-9a-f]{64}", parts[0]) and parts[1] not in actual,
                  "complete unique native staged hash rows required")
        actual[parts[1]] = parts[0]
    h.require(actual == expected, "partial/changed stage or cached Python identity; no submission")
    append(root, "STAGED", transfer=transfer)
    return dict(status="STAGED_NOT_SUBMITTED", scope_id=p["scope_id"])

def parse_job_id(raw):
    h.require(type(raw) is str and re.fullmatch(r"[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?\n?", raw), "ambiguous sbatch reply")
    return raw.strip().split(";", 1)[0]

def validate_ready(ready, p, job_id):
    h.require(ready["status"] == "READY_SOURCE_BOUND_COMPUTE_METADATA" and ready["scope_id"] == p["scope_id"]
              and ready["job_id"] == job_id and ready["spec_sha256"] == p["spec_sha256"]
              and ready["node"] == "node-13" and len(ready["affinity"]) == 1
              and ready["cpus_per_task"] == 1 and type(ready["models"]) is int and ready["models"] == 0
              and ready["sources"] == p["sources"] and ready["role"] == p["role"],
              "stale/foreign/malformed READY cannot release payload")

def ready(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); one_shot(root, "ready")
    # One paid observation only. Wait outside this guarded action, then fetch
    # once; protected sleeps consume guardian stop-window/accounting headroom.
    result = run_native(site, ["test", "-f", p["remote_root"] + "/READY.json"])
    if result["returncode"] == 1:
        prior = next((x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED"), None)
        diagnostic = h.read(prior) if prior is not None else None
        error = None
        if diagnostic is None or not diagnostic["terminal"]:
            try:
                # This diagnostic consumes one of the same three throttled
                # accounting intents, within this unchanged six-CPU action.
                diagnostic = observe(site, root)
            except BaseException as exc:
                error = type(exc).__name__ + ": " + str(exc)
        append(root, "READY_ABSENT_DIAGNOSTIC", accounting=diagnostic,
               accounting_error=error, ready_observations=1, automatic_retry=False)
        raise ValueError("READY absent after one observation; diagnostic retained; no automatic retry")
    h.require(result["returncode"] == 0, "READY observation transport failed; no automatic retry")
    one_shot(root, "ready_fetch")
    result = run_sftp(site, ["get " + p["remote_root"] + "/READY.json " + safe_path(str(root / "READY.json"))], root / "ready.sftp")
    h.require(result["returncode"] == 0, "READY transfer incomplete")
    value = h.read(h.pin(root / "READY.json")); validate_ready(value, p, job["job_id"])
    append(root, "READY_VALIDATED", ready=h.pin(root / "READY.json"))
    return value

def release(site, root, bundle):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); ready_value = h.read(h.pin(root / "READY.json"))
    validate_ready(ready_value, p, job["job_id"])
    validate_local_release(root,bundle)
    release_path = h.physical(bundle) / "RELEASE.json"; value = h.read(h.pin(release_path))
    h.require(value["status"] == "ROOT_RELEASED_STARTUP_BATCH_ROLE" and value["scope_id"] == p["scope_id"]
              and value["job_id"] == job["job_id"] and value["ready_sha256"] == digest(root / "READY.json")
              and value["spec_sha256"] == p["spec_sha256"] and value["role"] == p["role"], "actual root READY-bound release required")
    commands = []
    for row in value["files"]:
        relative = str(safe_relative(row["relative"])); local = h.physical(bundle) / relative
        h.require(local.parent == h.physical(bundle) and digest(local) == row["sha256"], "flat exact release metadata required")
        commands.append("put " + safe_path(str(local)) + " " + p["remote_root"] + "/release/" + relative)
    h.require(all(x["relative"] not in {"RELEASE.json", "RELEASE.json.partial"} for x in value["files"]), "reserved release publication filename")
    commands.append("put " + safe_path(str(release_path)) + " " + p["remote_root"] + "/release/RELEASE.json.partial")
    commands.append("rename " + p["remote_root"] + "/release/RELEASE.json.partial " + p["remote_root"] + "/release/RELEASE.json")
    one_shot(root, "release"); append(root, "RELEASE_INTENT", release=h.pin(release_path))
    result = run_sftp(site, commands, root / "release.sftp"); h.require(result["returncode"] == 0, "partial release retained; no retry")
    append(root, "RELEASED", release=h.pin(release_path), transfer=result)
    return dict(status="RELEASED", job_id=job["job_id"])

def CPU_seconds(text):
    match = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d\d):(\d\d(?:\.\d+)?)", text)
    h.require(match is not None, "complete Slurm TotalCPU required")
    days, hours, minutes, seconds = match.groups()
    value = int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes) * 60 + float(seconds)
    h.require(math.isfinite(value) and value >= 0 and int(minutes) < 60 and float(seconds) < 60, "invalid Slurm CPU")
    return value

def parse_accounting(raw, job_id, scope_id):
    lines = [line.split("|") for line in raw.splitlines() if line.strip()]
    h.require(all(len(x) == 11 and x[0] in {job_id, job_id + ".batch", job_id + ".extern"} for x in lines)
              and len({x[0] for x in lines}) == len(lines), "foreign/duplicate/partial accounting row")
    rows = [x for x in lines if x[0] == job_id]
    h.require(len(rows) == 1, "one complete canonical primary Slurm row required")
    x = rows[0]; state = x[1].split()[0]
    h.require(x[6] == scope_id and x[7:9] == ["128x24", "128x24"] and x[5] == "1", "foreign job/account/allocation")
    memory = re.fullmatch(r"([0-9.]+)([KMG])([cn])?", x[9])
    h.require(memory is not None and float(memory[1]) * {"K": 1 / 1024, "M": 1, "G": 1024}[memory[2]] == 8192,
              "actual primary requested memory differs from8GiB")
    cpu = CPU_seconds(x[3]); elapsed = int(x[4]); h.require(cpu <= 600 and 0 <= elapsed <= 1200, "whole batch reservation exceeded")
    required = {job_id, job_id + ".batch"}; actual = {row[0] for row in lines}
    for row in lines:
        h.require(re.fullmatch(r"[0-9]+:[0-9]+", row[2]) and 0 <= int(row[4]) <= 1200
                  and int(row[5]) in (0, 1) and CPU_seconds(row[3]) <= 600, "invalid step/accounting bound")
    complete_rows = required <= actual
    primary_consistent = cpu + .01 >= max((CPU_seconds(row[3]) for row in lines), default=0.)
    complete = complete_rows and primary_consistent and all(row[1].split()[0] == "COMPLETED" and row[2] == "0:0" for row in lines)
    terminal = complete_rows and primary_consistent and all(row[1].split()[0] in TERMINAL for row in lines)
    return dict(job_id=job_id, state=state, exit_code=x[2], canonical_primary_CPU_seconds=cpu,
        elapsed_seconds=elapsed, complete=complete, terminal=terminal, missing_required_rows=sorted(required - actual),
        MaxRSS_raw={row[0]: row[10] or None for row in lines}, unknown_MaxRSS_is_not_zero=True,
        primary_CPU_consistent_with_each_step=primary_consistent,
        raw_sacct=raw, step_rows_diagnostic_not_added=True, primary_charge_counted_once=True)

def observe(site, root):
    p = packet(root); job = known_job(root); past = records(root)
    count = len(list(root.glob("observe_*.intent.json")))
    h.require(count < 3, "finite accounting polls exhausted")
    one_shot(root, "observe_%02d" % count)
    intents = sorted(root.glob("observe_*.intent.json"))
    if len(intents) > 1:
        h.require(h.read(h.pin(intents[-1]))["epoch"] - h.read(h.pin(intents[-2]))["epoch"] >= 300,
                  "minimum300seconds between paid Slurm accounting intents, including failures")
    result = run_native(site, ["sacct", "--jobs", job["job_id"], "--noheader", "--parsable2", "--format",
        "JobIDRaw,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,JobName%128,Account,Partition,ReqMem,MaxRSS"])
    h.require(result["returncode"] == 0, "accounting observation failed")
    value = parse_accounting(result["stdout"], job["job_id"], p["scope_id"])
    path = root / ("accounting_%04d.json" % sum(x["state"] == "OBSERVED" for x in past)); h.write_new(path, value)
    append(root, "OBSERVED", accounting=h.pin(path))
    return value

def validate_manifest(manifest, spec, job_id):
    h.require(manifest["schema"] == "pricefm_startup_batch_return_manifest_v1"
              and manifest["scope_id"] == spec["scope_id"] and manifest["job_id"] == job_id,
              "returned manifest identity differs")
    rows = manifest["files"]; h.require(type(rows) is list and 1 <= len(rows) <= 4096, "bounded return file count required")
    names = [str(safe_relative(x["relative"])) for x in rows]
    h.require(len(set(names)) == len(names) and "RESULT.json" in names
              and all(type(x["bytes"]) is int and 0 <= x["bytes"] <= 16 * 1024**2 for x in rows)
              and sum(x["bytes"] for x in rows) <= 32 * 1024**2, "bounded unique metadata-only return required")
    h.require(all(Path(x).suffix.lower() not in {".rds", ".rda", ".rdata", ".npz", ".npy"} for x in names),
              "scientific binary payload is not a runtime metadata return")

def collect(site, root):
    p = packet(root); job = known_job(root)
    account = next(h.read(x["accounting"]) for x in reversed(records(root)) if x["state"] == "OBSERVED")
    h.require(account["terminal"], "known terminal job required before one-shot return")
    one_shot(root, "collect")
    diagnostics = root / "diagnostics"; diagnostics.mkdir(mode=0o700)
    # Optional raw logs remain useful even if the worker failed before sealing.
    logs = run_sftp(site, ["-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".out "
                           + safe_path(str(diagnostics / "slurm.stdout")),
                         "-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".err "
                           + safe_path(str(diagnostics / "slurm.stderr"))], root / "diagnostics.sftp")
    append(root, "DIAGNOSTICS_FETCHED", transport=logs,
           files=[h.pin(x) for x in sorted(diagnostics.iterdir()) if x.is_file()])
    raw = root / "returned"; raw.mkdir(mode=0o700)
    transfer = run_sftp(site, ["get " + p["remote_root"] + "/result/RETURN_MANIFEST.json "
                              + safe_path(str(raw / "RETURN_MANIFEST.json"))], root / "manifest.sftp")
    h.require(transfer["returncode"] == 0, "manifest return failed; no retry")
    manifest = h.read(h.pin(raw / "RETURN_MANIFEST.json")); validate_manifest(manifest, p, job["job_id"])
    commands = []
    for row in manifest["files"]:
        path = raw / row["relative"]; path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        commands.append("get " + p["remote_root"] + "/result/" + row["relative"] + " " + safe_path(str(path)))
    transfer = run_sftp(site, commands, root / "return.sftp"); h.require(transfer["returncode"] == 0, "partial return retained; no retry")
    for row in manifest["files"]:
        path = raw / row["relative"]
        h.require(path.is_file() and not path.is_symlink() and path.stat().st_size == row["bytes"]
                  and digest(path) == row["sha256"], "returned metadata bytes/hash differ")
    append(root, "RETURNED", manifest=h.pin(raw / "RETURN_MANIFEST.json"), full_return_hash_verified=True)
    return dict(status="COMPLETE_HASH_VERIFIED_RETURN_NOT_YET_ACCEPTED", manifest=h.pin(raw / "RETURN_MANIFEST.json"))

def cancel(site, root):
    p = packet(root); job = known_job(root); one_shot(root, "cancel")
    append(root, "CANCEL_INTENT", job_id=job["job_id"], compute_fee_retained=600)
    value = run_native(site, ["scancel", "--user", site["user"], "--name", p["scope_id"], job["job_id"]])
    h.require(value["returncode"] == 0, "own exact-job cancellation unknown; claim remains")
    append(root, "CANCEL_REQUESTED", result=value)
    return dict(status="CANCEL_REQUESTED_NOT_TERMINAL_PROOF", job_id=job["job_id"])

def retire_failed(config, site, root, actual_review):
    p = packet(root); job = known_job(root); one_shot(root, "retire_failed")
    account_pin = next(x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED")
    account = h.read(account_pin)
    h.require(account["terminal"] and not account["complete"], "failed terminal primary accounting required")
    peer = h.read(h.pin(actual_review))
    h.require(peer["status"] == "PASS_REVIEWED_FAILED_STARTUP_BATCH_RETIREMENT"
              and peer["job_id"] == job["job_id"] and peer["accounting"] == account_pin,
              "actual failed-role retirement review required")
    queue = run_native(site, ["squeue", "--noheader", "--user", site["user"], "--format", "%i"])
    h.require(queue["returncode"] == 0 and job["job_id"] not in queue["stdout"].split(), "failed job still queued/unknown")
    lock = config["remote_namespace"] + "/qualification.lock"
    for argv in (["test", "-f", lock + "/OWNED_" + p["scope_id"]], ["rm", "--", lock + "/OWNED_" + p["scope_id"]], ["rmdir", lock]):
        h.require(run_native(site, argv)["returncode"] == 0, "failed claim release unknown; no retry")
    append(root, "FAILED_RETIRED_NO_RETRY", accounting=account_pin, independent_review=h.pin(actual_review),
           all_fees_and_partial_artifacts_retained=True, same_role_resubmission_forbidden=True)
    return dict(status="FAILED_RETIRED_NO_RETRY", job_id=job["job_id"])



if __name__=='__main__':main()
