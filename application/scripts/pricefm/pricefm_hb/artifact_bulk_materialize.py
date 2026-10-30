"""Original tmpfs receive, then exact owned-file durable bulk materialization.

Standalone; PYTHONPATH must select the unchanged original pricefm_hb package.
The complete invocation requires the original whole20CPU/300wall guardian.
No subprocesses, arrays, global writeback, canonical install or acceptance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import time
from pricefm_hb import profile_stream as s

STREAM_SHA='4f8cbb837817296125fd27d3ddf52f90959062526be2142c536814d0411a739c'
SUPERVISOR_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
WIRE_LIMIT=32600121
MEMORY_BUDGET=128*1024**2
SCOPE_ID='r164-profile-feb3840ef66e59cda675336196e1a12d'
ROOT_SCOPE_SHA='5ac75361eafe89aa7b6e933ca9546d0dbecc49c732866ccfbd14501736fe06e8'
ENDPOINT=1793344299.7823877
CONFIG_COMMON={'schema','source_role','scope_id','job_id','authority','memory_root','target_root','stable_anchor','bindings'}


def identity(v):return dict(device=v.st_dev,inode=v.st_ino,uid=v.st_uid,mode=v.st_mode)


def bounded_read(path,limit=s.HEADER_MAX):
    path=s.physical(path);before=s.regular(path);s.require(before.st_size<=limit,'metadata byte bound exceeded')
    with s.source_file(path,s.fingerprint(before)) as f:
        raw=f.read(limit+1);s.require(len(raw)==before.st_size and s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before),'metadata changed')
    s.require(s.fingerprint(s.regular(path))==s.fingerprint(before),'metadata path changed')
    return raw


def pin(path,raw=None):
    raw=bounded_read(path) if raw is None else raw
    return dict(path=str(s.physical(path)),sha256=hashlib.sha256(raw).hexdigest())


def read_pin(value):
    s.require(type(value) is dict and set(value)=={'path','sha256'} and type(value['sha256']) is str and
              re.fullmatch(r'[a-f0-9]{64}',value['sha256']),'exact metadata pin required')
    raw=bounded_read(value['path']);s.require(pin(value['path'],raw)==value,'metadata pin differs')
    return s.decode(raw)



def validate_bindings(role,bindings):
    s.require(role in ('REAL_COMPLETED_SPOOL','SYNTHETIC_FIXTURE'),'exact source role required')
    wanted={'spec','request','source_manifest'} if role=='REAL_COMPLETED_SPOOL' else {'build_scope','original_send','manifest'}
    s.require(type(bindings) is dict and set(bindings)==wanted,'exact role-specific input bindings required')
    for binding in bindings.values():
        s.require(type(binding) is dict and set(binding)=={'path','sha256'} and type(binding['path']) is str and
                  type(binding['sha256']) is str and re.fullmatch(r'[a-f0-9]{64}',binding['sha256']),'exact binding pin required')
        s.physical(binding['path'])


def validate_authority(cfg,receipt_dir,producer):
    auth=read_pin(cfg['authority']);role=cfg['source_role']
    status='ROOT_AUTHORIZED_STRONG_BULK_ARTIFACT_RECOVERY' if role=='REAL_COMPLETED_SPOOL' else 'ROOT_AUTHORIZED_SYNTHETIC_BULK_QUALIFICATION'
    s.require(type(auth) is dict and auth.get('schema')=='r173_bulk_operation_authority_v1' and auth.get('status')==status,
              'actual role-specific operational root authority required')
    expected={k:cfg[k] for k in ('source_role','scope_id','job_id','bindings','memory_root','target_root','stable_anchor')}
    expected.update(source_receipt=cfg['spool_receipt' if role=='REAL_COMPLETED_SPOOL' else 'fixture_receipt'],receipt_dir=str(receipt_dir),
                    producer_source=producer,cpu_seconds=20,wall_seconds=300,wire_limit_bytes=WIRE_LIMIT,
                    memory_budget_bytes=MEMORY_BUDGET,expires_epoch=ENDPOINT,no_guard_or_cap_changes=True,strong_raw_durability=True)
    s.require(all(type(auth.get(k)) is type(v) and auth.get(k)==v for k,v in expected.items()),'operational root authority fields differ')
    s.require(time.time()+300<=ENDPOINT,'complete original operation window does not fit')
    root_pin=auth.get('root_scope');root=read_pin(root_pin)
    s.require(root_pin['sha256']==ROOT_SCOPE_SHA and root.get('expires_epoch')==ENDPOINT,'new purpose root scope differs')
    review=read_pin(auth.get('source_review'));publication=read_pin(auth.get('publication'))
    s.require(review.get('status')=='PASS_REVIEWED_DURABLE_BULK_SOURCES' and
              review.get('bulk_sources',{}).get('artifact_bulk_materialize')==producer,'actual source review differs')
    s.require(publication.get('status')=='VERIFIED_FEATURE_PUBLICATION' and
              publication.get('bulk_sources',{}).get('artifact_bulk_materialize')==producer and
              publication.get('fresh_remote_hash_verified') is True and publication.get('all_37_fetched_source_bytes_verified') is True,
              'actual fresh source publication differs')
    qualification=auth.get('synthetic_qualification')
    if role=='REAL_COMPLETED_SPOOL':
        proof=read_pin(qualification)
        s.require(proof.get('status')=='PASS_QUALIFIED_STRONG_BULK_ALGORITHM' and proof.get('bulk_helper_source')==producer,
                  'actual prior synthetic algorithm qualification required')
    else:s.require(qualification is None,'synthetic qualification must not pretend prior actual qualification')
    return auth


def new_directory(path,sticky_tmpfs=False):
    path=s.physical(path);fd=s.directory_fd(path.parent)
    try:
        parent=os.fstat(fd)
        s.require(parent.st_uid==os.getuid() or sticky_tmpfs and path.parent==Path('/dev/shm') and
                  parent.st_uid==0 and parent.st_mode&stat.S_ISVTX,'owned parent or exact sticky tmpfs root required')
        os.mkdir(path.name,0o700,dir_fd=fd)
    finally:os.close(fd)
    return path


def write_all(f,block):
    view=memoryview(block)
    while view:
        count=f.write(view);s.require(type(count) is int and count>0,'short owned write');view=view[count:]


def ancestors(path,anchor):
    path=s.physical(path);anchor=s.physical(anchor)
    s.require(path==anchor or path.is_relative_to(anchor),'owned stable-anchor boundary differs')
    out=[]
    while True:
        state=path.stat();s.require(stat.S_ISDIR(state.st_mode) and state.st_uid==os.getuid() and
                                  state.st_dev==anchor.stat().st_dev,'owned same-device ancestry required')
        out.append(path)
        if path==anchor:return out
        path=path.parent


def sync_directory(path):
    fd=s.directory_fd(path)
    try:
        before=os.fstat(fd);s.require(before.st_uid==os.getuid(),'owned directory sync only')
        os.fsync(fd);s.require(identity(os.fstat(fd))==identity(before)==identity(path.stat()),'directory sync identity changed')
    finally:os.close(fd)


def sync_ancestry(path,anchor):
    rows=ancestors(path,anchor)
    for directory in rows:sync_directory(directory)
    return [dict(path=str(x),identity=identity(x.stat())) for x in rows]


def save(path,value,anchor):
    path=s.physical(path);raw=json.dumps(value,sort_keys=True,allow_nan=False,separators=(',',':')).encode()+b'\n'
    fd=s.directory_fd(path.parent)
    try:out=os.open(path.name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_NONBLOCK,0o600,dir_fd=fd)
    finally:os.close(fd)
    with os.fdopen(out,'wb',buffering=0) as f:write_all(f,raw);os.fsync(f.fileno())
    sync_ancestry(path.parent,anchor)
    return pin(path,raw)


def system_text(path,limit=1024**2):
    """Only fixed own-process/memory hierarchy metadata; never a process scan."""
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        raw=os.read(fd,limit+1);s.require(len(raw)<=limit,'system metadata bound exceeded');return raw.decode()
    finally:os.close(fd)


def cgroup_memory_margins():
    rows=[x.split(':',2) for x in system_text('/proc/self/cgroup').splitlines()]
    mounts=[]
    for line in system_text('/proc/self/mountinfo').splitlines():
        left,right=line.split(' - ',1);fields=left.split();tail=right.split()
        if tail[0] in ('cgroup','cgroup2'):mounts.append((fields[3],fields[4],tail[0],tail[2].split(',')))
    candidates=[]
    for _,controllers,group in rows:
        s.require(group.startswith('/') and '..' not in Path(group).parts,'noncanonical own cgroup path')
        for root,mount,kind,options in mounts:
            wanted=kind=='cgroup2' and not controllers or kind=='cgroup' and 'memory' in controllers.split(',') and 'memory' in options
            if not wanted:continue
            root_path=Path(root);group_path=Path(group)
            if group_path==root_path:relative=Path('.')
            elif group_path.is_relative_to(root_path):relative=group_path.relative_to(root_path)
            else:continue
            candidates.append((Path(mount)/relative,Path(mount),kind))
    s.require(candidates,'own cgroup memory hierarchy could not be established')
    result=[]
    for directory,mount,kind in candidates:
        directory=s.physical(directory);mount=s.physical(mount)
        while True:
            cap_file=directory/('memory.max' if kind=='cgroup2' else 'memory.limit_in_bytes')
            used_file=directory/('memory.current' if kind=='cgroup2' else 'memory.usage_in_bytes')
            if cap_file.exists():
                text=system_text(str(cap_file),128).strip();used=int(system_text(str(used_file),128).strip())
                cap=None if text=='max' else int(text)
                s.require(used>=0 and (cap is None or cap>=0),'invalid cgroup memory counters')
                margin=None if cap is None else cap-used
                s.require(margin is None or margin>=2*MEMORY_BUDGET,'insufficient own cgroup ancestor margin')
                result.append(dict(path=str(directory),kind=kind,limit=cap,current=used,margin=margin))
            else:result.append(dict(path=str(directory),kind=kind,no_limit_file=True))
            if directory==mount:break
            s.require(directory.is_relative_to(mount),'own cgroup escaped mount');directory=directory.parent
    return result


def memory_headroom():
    info={line.split(':',1)[0]:line.split(':',1)[1].strip() for line in system_text('/proc/meminfo').splitlines() if ':' in line}
    available=int(info['MemAvailable'].split()[0])*1024
    s.require(available>=2*MEMORY_BUDGET,'insufficient actual MemAvailable')
    mounts=system_text('/proc/self/mountinfo').splitlines()
    s.require(any(line.split(' - ',1)[0].split()[4]=='/dev/shm' and line.split(' - ',1)[1].split()[0]=='tmpfs' for line in mounts),
              'exact /dev/shm tmpfs mount required')
    fs=os.statvfs('/dev/shm');free=fs.f_bavail*fs.f_frsize
    s.require(free>=MEMORY_BUDGET,'insufficient tmpfs space')
    return dict(MemAvailable_bytes=available,tmpfs_available_bytes=free,cgroup_ancestors=cgroup_memory_margins(),
                memory_budget_bytes=MEMORY_BUDGET,required_host_and_finite_cgroup_margin_bytes=2*MEMORY_BUDGET,
                reservation_or_availability_guaranteed=False)


def wire_manifest(f):
    f.seek(0);s.require(s.exact(f.read,len(s.MAGIC))==s.MAGIC,'original wire magic differs')
    length=struct.unpack('!Q',s.exact(f.read,8))[0];s.require(0<length<=s.HEADER_MAX,'original header bound exceeded')
    raw=s.exact(f.read,length);value=s.validate_manifest(s.decode(raw),s.BYTE_MAX)
    directories=set()
    for entry in value['files']:
        parent=PurePosixPath(entry['name']).parent
        while str(parent)!='.':directories.add(str(parent));parent=parent.parent
    estimated=sum((entry['bytes']+4095)//4096*4096 for entry in value['files'])+length+65536+8192*(len(value['files'])+len(directories))
    s.require(value['kind']=='directory' and len(value['files'])<=520 and len(directories)<=144 and
              max((len(PurePosixPath(entry['name']).parts) for entry in value['files']),default=0)<=7 and
              estimated<=MEMORY_BUDGET,'bounded task-specific memory decode geometry exceeded')
    return value,hashlib.sha256(raw).hexdigest()


def verify_wire(f,path,before,expected):
    s.require(s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(path)),'wire identity differs')
    f.seek(0);remaining=before.st_size;h=hashlib.sha256()
    while remaining:
        block=f.read(min(s.CHUNK,remaining));s.require(block,'wire truncated');h.update(block);remaining-=len(block)
    s.require(not f.read(1) and h.hexdigest()==expected,'wire byte SHA differs')
    s.require(s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(path)),'wire changed while hashed')


def source_bank(f,wire_path,before,source_pin,anchor,role):
    os.fsync(f.fileno());s.require(s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before),'wire changed during durability barrier')
    receipt_path=s.physical(source_pin['path']);receipt_state=s.regular(receipt_path)
    with s.source_file(receipt_path,s.fingerprint(receipt_state)) as receipt:os.fsync(receipt.fileno())
    dirs={*ancestors(wire_path.parent,anchor),*ancestors(receipt_path.parent,anchor)}
    ordered=sorted(dirs,key=lambda p:(-len(p.parts),str(p)))
    for path in ordered:sync_directory(path)
    s.require(s.fingerprint(s.regular(wire_path))==s.fingerprint(before) and pin(receipt_path)==source_pin,'durable bank source changed')
    return dict(wire_file_fsynced=True,source_receipt_fsynced=True,source_role=role,
                directories_fsynced=[str(x) for x in ordered],stable_anchor=str(anchor),
                wire_identity=identity(before),wire_fingerprint=list(s.fingerprint(before)),source_receipt=source_pin)


def tree_manifest(root,value):
    root=s.physical(root);state=root.stat();expected={entry['name']:entry for entry in value['files']};files={};total=0;directories={root}
    for base,dirs,names in os.walk(root,followlinks=False):
        for name in dirs:
            path=s.physical(Path(base)/name);v=path.stat();s.require(stat.S_ISDIR(v.st_mode) and v.st_uid==os.getuid() and v.st_dev==state.st_dev,'unsafe owned tree directory');directories.add(path)
        for name in names:
            path=Path(base)/name;relative=str(path.relative_to(root));s.require(relative in expected,'unexpected owned tree member')
            entry=expected[relative];before=s.regular(path,state.st_dev);s.require(before.st_size==entry['bytes'] and stat.S_IMODE(before.st_mode)==entry['mode'],'owned file size/mode differs')
            h=hashlib.sha256();count=0
            with s.source_file(path,s.fingerprint(before)) as f:
                while count<before.st_size:
                    block=f.read(min(s.CHUNK,before.st_size-count));s.require(block,'owned file truncated');h.update(block);count+=len(block)
                s.require(not f.read(1) and s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(path)),'owned file changed during verification')
            s.require(h.hexdigest()==entry['sha256'],'owned file SHA differs')
            files[relative]=dict(bytes=count,sha256=h.hexdigest(),mode=stat.S_IMODE(before.st_mode),device=before.st_dev,inode=before.st_ino,uid=before.st_uid,fingerprint=list(s.fingerprint(before)));total+=count
    s.require(set(files)==set(expected) and total==value['total_bytes'],'owned tree member/total differs')
    wanted_dirs={root}
    for name in expected:
        parent=(root/name).parent
        while parent!=root:wanted_dirs.add(parent);parent=parent.parent
    s.require(directories==wanted_dirs,'unexpected owned tree directory')
    return dict(root=str(root),device=state.st_dev,inode=state.st_ino,files=files,file_count=len(files),total_bytes=total)


def materialize(memory_root,target,value,anchor):
    """No payload fsync until every target write/hash/fchmod has completed."""
    source=tree_manifest(memory_root,value);target=new_directory(target);target_state=target.stat()
    s.require(target_state.st_dev!=source['device'],'distinct tmpfs and disk devices required')
    directories={target};written={}
    for entry in value['files']:
        name=entry['name'];path=target/name;fd=s.directory_fd(target)
        try:
            at=target
            for part in PurePosixPath(name).parts[:-1]:
                try:os.mkdir(part,0o700,dir_fd=fd)
                except FileExistsError:pass
                child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd);os.close(fd);fd=child;at=at/part
                ds=os.fstat(fd);s.require(ds.st_uid==os.getuid() and ds.st_dev==target_state.st_dev,'target directory identity differs');directories.add(at)
            out=os.open(path.name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_NONBLOCK,0o600,dir_fd=fd)
        finally:os.close(fd)
        before=s.regular(memory_root/name,source['device']);s.require(list(s.fingerprint(before))==source['files'][name]['fingerprint'],'memory source changed before copy')
        h=hashlib.sha256();count=0
        with os.fdopen(out,'wb',buffering=0) as f,s.source_file(memory_root/name,s.fingerprint(before)) as src:
            while count<entry['bytes']:
                block=src.read(min(s.CHUNK,entry['bytes']-count));s.require(block,'memory source truncated');write_all(f,block);h.update(block);count+=len(block)
            s.require(not src.read(1) and h.hexdigest()==entry['sha256'] and s.fingerprint(os.fstat(src.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(memory_root/name)), 'memory source SHA/identity changed')
            os.fchmod(f.fileno(),entry['mode']);written[name]=s.fingerprint(os.fstat(f.fileno()))
    synced=[]
    for entry in value['files']:
        path=target/entry['name'];before=s.regular(path,target_state.st_dev);s.require(s.fingerprint(before)==written[entry['name']],'target changed before file sync')
        with s.source_file(path,s.fingerprint(before)) as f:
            os.fsync(f.fileno());s.require(s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(path)),'target changed during file sync')
        synced.append(entry['name'])
    directories.update(ancestors(target.parent,anchor));ordered=sorted(directories,key=lambda p:(-len(p.parts),str(p)))
    for path in ordered:sync_directory(path)
    s.require(identity(target.stat())==identity(target_state),'materialized root identity changed')
    return tree_manifest(target,value),synced,[str(x) for x in ordered]


def bulk_materialize(config_path,receipt_dir):
    config_raw=bounded_read(config_path);cfg=s.decode(config_raw)
    s.require(type(cfg) is dict and cfg.get('schema')=='r173_bulk_materialize_task_v1' and
              cfg.get('source_role') in ('REAL_COMPLETED_SPOOL','SYNTHETIC_FIXTURE'),'exact bulk task source role required')
    role=cfg['source_role'];role_key='spool_receipt' if role=='REAL_COMPLETED_SPOOL' else 'fixture_receipt'
    s.require(set(cfg)==CONFIG_COMMON|{role_key},'exact role-specific bulk task keys required')
    if role=='REAL_COMPLETED_SPOOL':
        s.require(cfg['scope_id']==SCOPE_ID and type(cfg['job_id']) is str and re.fullmatch(r'[0-9]{1,12}',cfg['job_id']),'actual D5 identity required')
    else:s.require(type(cfg['scope_id']) is str and re.fullmatch(r'r173-synthetic-[a-zA-Z0-9_-]{1,100}',cfg['scope_id']) and cfg['job_id'] is None,'honest synthetic identity required')
    s.require(hashlib.sha256(bounded_read(Path(s.__file__))).hexdigest()==STREAM_SHA,'original stream source differs')
    source_pin=cfg[role_key];spool=read_pin(source_pin);anchor=s.physical(cfg['stable_anchor'])
    validate_bindings(role,cfg['bindings'])
    s.require(spool.get('scope_id')==cfg['scope_id'] and spool.get('job_id')==cfg['job_id'] and spool.get('bindings')==cfg['bindings'],'source identities differ')
    if role=='REAL_COMPLETED_SPOOL':
        s.require(spool.get('schema')=='r165_artifact_spool_receipt_v1' and spool.get('status')=='WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM' and
                  spool.get('capture_complete') is True and type(spool.get('ssh_returncode')) is int and spool['ssh_returncode']==0 and
                  spool.get('original_stream_source_sha256')==STREAM_SHA and spool.get('original_supervisor_source_sha256')==SUPERVISOR_SHA,
                  'exact successful original spool required')
    else:s.require(spool.get('schema')=='r173_synthetic_wire_source_v1' and spool.get('source_role')==role and
                   spool.get('generated_from_owned_synthetic_bytes') is True and 'ssh_returncode' not in spool,'genuine owned fixture source required')
    wire_path=s.physical(spool['wire']['path']);before=s.regular(wire_path,anchor.stat().st_dev)
    s.require(wire_path.name=='wire.spool' and wire_path.parent==s.physical(source_pin['path']).parent and
              0<before.st_size<=WIRE_LIMIT and before.st_size==spool['wire']['bytes'] and identity(before)==spool['wire']['identity'] and
              list(s.fingerprint(before))==spool['wire']['fingerprint'],'original wire role/identity/size differs')
    memory=s.physical(cfg['memory_root']);target=s.physical(cfg['target_root']);receipts=s.physical(receipt_dir)
    s.require(memory.is_relative_to(Path('/dev/shm')) and memory!=Path('/dev/shm') and target.is_relative_to(anchor) and
              receipts.is_relative_to(anchor) and target.name=='decoded_raw' and 'hb_control_registry' not in target.parts and
              not target.is_relative_to(receipts) and not receipts.is_relative_to(target),'distinct private target/receipt roots required')
    s.require(memory.parent.stat().st_dev==Path('/dev/shm').stat().st_dev and target.parent.stat().st_dev==before.st_dev,'tmpfs/disk target device differs')
    producer=pin(Path(__file__));validate_authority(cfg,receipts,producer)
    root=new_directory(receipts);base=dict(source_role=role,source_receipt=source_pin,scope_id=cfg['scope_id'],job_id=cfg['job_id'],bindings=cfg['bindings'],authority=cfg['authority'],producer_source=producer,config=pin(config_path,config_raw),spool_receipt=source_pin if role=='REAL_COMPLETED_SPOOL' else None,wire=spool['wire'])
    result=dict(schema='r173_bulk_materialization_result_v1',status='FAILED_BULK_MATERIALIZATION',memory_root=str(memory),target_root=str(target),required_outer_guard=dict(cpu=20,wall=300),no_canonical_install=True,**base)
    try:
        save(root/'intent.json',dict(result,schema='r173_bulk_intent_v1'),anchor)
        headroom=memory_headroom()
        with s.source_file(wire_path,s.fingerprint(before)) as f:
            verify_wire(f,wire_path,before,spool['wire']['sha256']);value,digest=wire_manifest(f)
            bank=source_bank(f,wire_path,before,source_pin,anchor,role)
            memory=new_directory(memory,sticky_tmpfs=True);memory_identity=identity(memory.stat())
            f.seek(0);original=s.receive(memory,f.read,s.BYTE_MAX,directory=True)
            s.require(original['manifest_sha256']==digest and s.fingerprint(os.fstat(f.fileno()))==s.fingerprint(before)==s.fingerprint(s.regular(wire_path)),'original receive wire/manifest differs')
            if role=='SYNTHETIC_FIXTURE':s.require(original==spool['original_send_receipt'],'actual receive differs from genuine synthetic send receipt')
            memory_manifest=tree_manifest(memory,value)
            mem=dict(schema='r173_memory_decode_receipt_v1',status='PASS_MEMORY_DECODE',memory_root=str(memory),target_identity=memory_identity,
                     original_receive_receipt=original,wire_manifest=value,wire_manifest_sha256=digest,memory_manifest=memory_manifest,
                     headroom=headroom,volatile=True,completed=True,**base)
            mem_pin=save(root/'memory_decode.json',mem,anchor);result.update(memory_decode=mem_pin,memory_decode_receipt=mem)
            target_manifest,files_synced,dirs_synced=materialize(memory,target,value,anchor)
            verify_wire(f,wire_path,before,spool['wire']['sha256'])
            durable=dict(schema='r173_durable_materialization_receipt_v1',status='PASS_DURABLE_MATERIALIZATION',completed=True,
                         memory_decode=mem_pin,memory_root=str(memory),target_root=str(target),target_identity=identity(target.stat()),
                         target_manifest=target_manifest,files_fsynced=files_synced,directories_fsynced=dirs_synced,
                         all_writes_before_file_sync=True,durable_wire_source=bank,wire_manifest_sha256=digest,**base)
            durable_pin=save(root/'durable_materialization.json',durable,anchor)
            result.update(status='PASS_DURABLE_BULK_MATERIALIZATION',durable_materialization=durable_pin,durable_materialization_receipt=durable,
                          target_identity=identity(target.stat()),target_manifest=target_manifest,wire_manifest=value,wire_manifest_sha256=digest,
                          original_receive_receipt=original,durable_wire_source=bank)
    except BaseException as exc:result['error']=dict(type=type(exc).__name__,message=str(exc)[:2000])
    save(root/'bulk_receipt.json',result,anchor)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--receipt-dir',required=True)
    args=parser.parse_args();result=bulk_materialize(args.config,args.receipt_dir)
    print(json.dumps(result,sort_keys=True,allow_nan=False),flush=True)
    return 0 if result['status']=='PASS_DURABLE_BULK_MATERIALIZATION' else 1


if __name__=='__main__':raise SystemExit(main())
