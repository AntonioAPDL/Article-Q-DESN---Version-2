"""Compute-only code installer for a NEW scientific namespace qualification.

This is a distinct reviewed4096-file/384MiB code-only purpose. The old2048-file
startup role remains unchanged. No R, target input or optimizer is executed.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import stat
import tarfile
import time

from . import runtime_archive as a
from . import scientific_namespace_plan as n

BASE_MANIFEST_SHA='60eb4229602956510631bb6989de7d20ccd47cae7f6ab32bbfd6841d64af28e6'
BASE_ARCHIVE_SHA='c94cadf4c75a56113355e86f2e485b1bba0c6e61ffee058bd22f681f4ba7132a'


def sources():
    return {p.name:a.pin(p) for p in (Path(__file__).absolute(),Path(a.__file__).absolute(),Path(n.__file__).absolute())}


def validate(spec_pin,authority_pin,review_pin,*,now=None,environment=None,affinity=None,node=None):
    now=time.time() if now is None else now;environment=os.environ if environment is None else environment
    affinity=os.sched_getaffinity(0) if affinity is None else affinity;node=os.uname().nodename.split('.')[0] if node is None else node
    spec,authority,review=(a.read(p) for p in (spec_pin,authority_pin,review_pin))
    a.require(spec.get('schema')=='r179_scientific_code_install_spec_v1' and spec.get('purpose')==n.PURPOSE,
              'new scientific code namespace role required')
    a.require(spec.get('bounds')=={'files':n.MAX_FILES,'bytes':n.MAX_BYTES,'one_file_bytes':n.MAX_FILE},'explicit new code limits required')
    a.require(spec.get('R_executions')==0 and spec.get('scientific_target_data') is False and spec.get('optimizer_invocations')==0,
              'no R/target/optimizer authority in code installer')
    a.require(environment.get('SLURM_JOB_ID','').isdigit() and environment['SLURM_JOB_ID']==spec.get('job_id')
              and environment.get('SLURMD_NODENAME')==spec.get('node')==node
              and environment.get('SLURM_CPUS_PER_TASK')=='1' and len(affinity)==1
              and sorted(affinity)==spec.get('affinity') and not any(x in node.lower() for x in ['login','head','submit']),
              'actual one-CPU compute job identity required')
    a.require(authority.get('status')=='ROOT_ADMITTED_NEW_SCIENTIFIC_CODE_NAMESPACE_ONLY'
              and authority.get('spec')==spec_pin and authority.get('sources')==sources()
              and authority['issued_epoch']<=now and now+600<authority['expires_epoch']
              and authority.get('memory_MiB')==8192 and authority.get('max_calls')==1,
              'new exact source/spec/root/job funding authority required')
    a.require(review.get('status')=='PASS_REVIEWED_SCIENTIFIC_CODE_INSTALL_SOURCE_AND_SPEC'
              and review.get('spec')==spec_pin and review.get('authority')==authority_pin
              and review.get('sources')==sources(),'independent exact new-role source/spec review required')
    return spec


def install_one(archive_pin,manifest,out,seen):
    path=a.physical(archive_pin['path']);a.require(a.pin(path)==archive_pin,'staged code archive differs')
    a.validate_archive(path,manifest['files'])
    expected={row['relative']:row for row in manifest['files']}
    before=a.binding(path)
    with tarfile.open(path,'r:gz') as source:
        for info in source:
            name=a.member_name(info.name);a.require(info.isreg() and name in expected and name not in seen,'unexpected/overwritten installed code member')
            row=expected[name];a.require(info.size==row['bytes'] and info.mode==row['mode'],'installed code size/mode differs')
            target=out/name;target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
            a.physical(target)
            fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            h=hashlib.sha256();count=0
            with os.fdopen(fd,'wb') as dest,source.extractfile(info) as data:
                for chunk in iter(lambda:data.read(1024**2),b''):
                    count+=len(chunk);a.require(count<=row['bytes'],'installed code grew');h.update(chunk);dest.write(chunk)
                dest.flush();os.fsync(dest.fileno());os.fchmod(dest.fileno(),row['mode'])
            a.require(count==row['bytes'] and h.hexdigest()==row['sha256'],'installed code hash differs')
            seen.add(name)
    a.require(a.binding(path)==before and a.pin(path)==archive_pin,'code archive changed during extraction')


def install(spec):
    a.require(spec['base_manifest']['sha256']==BASE_MANIFEST_SHA and spec['base_archive']['sha256']==BASE_ARCHIVE_SHA,
              'exact previously verified base archive must be reused')
    base=a.read(spec['base_manifest']);addon=a.read(spec['addon_manifest'])
    envelope=n.validate_closure(base,addon)
    parts=[a.read(item['manifest']) for item in spec['addons']]
    members=n.validate_part_members(base,parts)
    a.require(members['files']==envelope['assembled_files'] and members['bytes']==envelope['assembled_bytes'],
              'exact base+addon file/byte geometry differs')
    a.require(len(spec['addons'])==len(addon['parts']) and spec['base_archive']['sha256']==addon['base_archive']['sha256']
              and spec['base_manifest']['sha256']==addon['base_manifest']['sha256'],
              'code parts or base binding differs')
    for staged,original in zip(spec['addons'],addon['parts']):
        a.require(staged['archive']['sha256']==original['archive']['sha256']
                  and staged['manifest']['sha256']==original['manifest']['sha256'],'addon delivery hash differs')
    out=a.physical(spec['output']);root=a.physical(spec['remote_namespace'])
    a.require(out.is_relative_to(root) and out!=root and not out.exists() and root.stat().st_uid==os.getuid()
              and stat.S_IMODE(root.stat().st_mode)&0o022==0,'new private owned namespace required; old base job must remain untouched')
    out.mkdir(mode=0o700);seen=set()
    a.write_json(out/'INSTALL_INTENT.json',{'status':'CODE_INSTALL_STARTED_NOT_COMPLETE','R_executions':0,'job_id':spec['job_id'],'purpose':n.PURPOSE})
    try:
        install_one(spec['base_archive'],base,out,seen)
        for staged,manifest in zip(spec['addons'],parts):install_one(staged['archive'],manifest,out,seen)
        a.require(len(seen)==envelope['assembled_files'],'incomplete scientific code installation')
        record={'status':'INSTALLED_CODE_BYTES_ONLY_NOT_NAMESPACE_OR_SCIENTIFIC_PROOF','schema':'r179_scientific_code_install_result_v1',
                'job_id':spec['job_id'],'node':spec['node'],'files':len(seen),'bytes':envelope['assembled_bytes'],
                'library':str(out/'R_HOME/library'),'R_HOME':str(out/'R_HOME'),'native_library_path':[str(out/'R_HOME/lib'),str(out/'lib')],
                'R_executions':0,'scientific_data_access':False,'namespace_startup_proved':False,'scientific_boundary_proved':False,
                'old_qualified_base_job_namespace_modified':False,'new_envelope':envelope}
        a.write_json(out/'INSTALL_RESULT.json',record);return record
    except BaseException as error:
        a.write_json(out/'INSTALL_FAILED.json',{'status':'FAILED_CODE_INSTALL_PARTIAL_RETAINED_NO_RETRY','error_type':type(error).__name__,'error':str(error),'R_executions':0})
        raise


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['spec','authority','review']:
        p.add_argument('--'+name,required=True);p.add_argument('--'+name+'-sha256',required=True)
    args=p.parse_args(argv)
    resource.setrlimit(resource.RLIMIT_CPU,(60,60));signal.alarm(600)
    pins=[{'path':getattr(args,name),'sha256':getattr(args,name+'_sha256')} for name in ['spec','authority','review']]
    spec=validate(*pins);record=install(spec)
    print(json.dumps({k:record[k] for k in ['status','job_id','node','files','bytes','R_executions']},sort_keys=True))


if __name__=='__main__':main()
