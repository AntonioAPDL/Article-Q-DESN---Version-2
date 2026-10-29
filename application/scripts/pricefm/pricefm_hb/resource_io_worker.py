"""Standalone opaque resource I/O qualification; no numerical libraries/work.

Only an exact prospective contract permits streaming old bytes and copying
them into this worker's new owned scratch tree. Existing inputs are immutable.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import resource
import shutil
import signal
import socket
import stat
import sys
import tempfile
import time

SCHEMA = 'r162_opaque_io_qualification_v1'
PURPOSE = 'OPAQUE_RESOURCE_IO_QUALIFICATION_NO_NUMERICAL_WORK'
BASE = Path('/mnt/beegfs/home/jaguir26/pricefm_hb_r156_20261027')
RETAINED = {'FI': BASE/'r157-d47c2bf25dcb47e9b86ab307d1ae69fa',
            'DK2': BASE/'r157-65d1272c98474638a317fa5a89a893f4'}
COUNTS = {'FI': (1578, 627842856), 'DK2': (1623, 621960058)}
RESOURCES = dict(cpus=1, memory_MiB=4096, wall_seconds=120, cpu_seconds=120)
SOURCE_NAMES = {'resource_io_worker.py', 'run_io.sh'}
IMPORT_MONOTONIC = time.monotonic()


class QualificationError(ValueError):
    pass


def require(value, message):
    if not value:
        raise QualificationError(message)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def physical(path, *, owned=False, regular=False):
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts, 'absolute physical path required')
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'symlink path rejected')
    if owned:
        require(path.stat().st_uid == os.getuid(), 'owned path required')
    if regular:
        require(stat.S_ISREG(path.stat().st_mode), 'regular file required')
    return path


def relative(name):
    require(isinstance(name, str) and name and '\\' not in name and all(ord(c) >= 32 for c in name), 'safe relative member required')
    p = PurePosixPath(name)
    require(not p.is_absolute() and '..' not in p.parts and str(p) == name and len(p.parts) > 1 and p.parts[0] == 'stage', 'exact stage-relative member required')
    return Path(name)


def fingerprint(path):
    s = path.stat()
    return dict(device=s.st_dev, inode=s.st_ino, bytes=s.st_size, mtime_ns=s.st_mtime_ns)


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def read_json(path, maximum=2*1024**2):
    path=physical(path,owned=True,regular=True)
    require(path.stat().st_size <= maximum, 'bounded JSON required')
    return json.loads(path.read_text())


def atomic_new(path, value):
    path=Path(path);physical(path.parent,owned=True)
    data=(json.dumps(value,sort_keys=True,indent=2,allow_nan=False)+'\n').encode()
    require(len(data)<=2*1024**2,'bounded output metadata required')
    temp=path.parent/('.'+path.name+'.'+str(os.getpid())+'.tmp')
    with temp.open('xb') as stream:
        stream.write(data);stream.flush();os.fsync(stream.fileno())
    try:
        os.link(str(temp),str(path))  # atomic create-only; never replaces prior evidence
    finally:
        temp.unlink()
    return dict(path=str(path),sha256=digest_bytes(data),bytes=len(data))


def validate_contract(contract, contract_sha256, sourcefilebase):
    require(isinstance(contract,dict) and contract.get('schema')==SCHEMA and contract.get('purpose')==PURPOSE, 'exact qualification purpose required')
    require(re.fullmatch(r'[a-f0-9]{64}',contract_sha256 or '') is not None,'contract SHA256 required')
    scope=contract.get('scope_id','');require(re.fullmatch(r'r162_io_[a-f0-9]{32}',scope) is not None,'new exact scope identity required')
    require(contract.get('remote_root')==str(BASE/scope),'fresh qualification root required')
    created=contract.get('created_epoch');expires=contract.get('expires_epoch');now=time.time()
    require(finite(created) and finite(expires) and created<=now<expires<=created+1800,'finite unexpired original contract required')
    require(contract.get('resources')==RESOURCES and all(type(v) is int for v in contract['resources'].values()),'exact oneCPU/fourGiB/120CPU/120wall required')
    require(contract.get('account')=='128x24' and contract.get('partition')=='128x24' and contract.get('qos')=='normal','exact scheduler allocation required')
    require(contract.get('node')=='node-13','exact reviewed node required')
    n=contract.get('max_tasks');require(type(n) is int and n in (2,4) and contract.get('max_concurrent')==n,'explicit two/four task scope required')
    tasks=contract.get('tasks');require(isinstance(tasks,list) and len(tasks)==n and all(isinstance(t,dict) for t in tasks),'whole explicitly admitted array required')
    require([t.get('task_id') for t in tasks]==list(range(n)) and all(type(t.get('task_id')) is int for t in tasks),'exact ordered array task IDs required')
    originals={}
    for task in tasks:
        study='FI' if task['task_id']%2==0 else 'DK2'
        require(task.get('study')==study and task.get('retained_root')==str(RETAINED[study]),'exact alternating retained accepted roots required')
        files=task.get('files');require(isinstance(files,dict),'full opaque input allowlist required')
        for name,record in files.items():
            relative(name)
            require(isinstance(record,dict) and set(record)=={'sha256','bytes'} and integer(record['bytes']) and re.fullmatch(r'[a-f0-9]{64}',record['sha256'] or '') is not None,'exact opaque member pin required')
        require((len(files),sum(v['bytes'] for v in files.values()))==COUNTS[study],'complete original stage count/byte total required')
        require(study not in originals or originals[study]==files,'repeated study must retain identical input bytes')
        originals[study]=files
    source=contract.get('source_files');require(isinstance(source,dict) and set(source)==SOURCE_NAMES,'exact worker/launcher source membership required')
    base=physical(sourcefilebase,owned=True)
    for name,record in source.items():
        path=physical(base/name,owned=True,regular=True)
        require(isinstance(record,dict) and set(record)=={'sha256','bytes'} and integer(record['bytes'],1),'complete source pin required')
        require(record['bytes']<=1024**2 and path.stat().st_size==record['bytes'] and digest_bytes(path.read_bytes())==record['sha256'],'qualification source changed')
    require(source['resource_io_worker.py']['sha256']==digest_bytes(Path(__file__).read_bytes()),'executed worker source differs')
    contract_path=physical(base/'contract.json',owned=True,regular=True)
    require(contract_path.stat().st_size<=2*1024**2,'bounded contract required')
    raw=contract_path.read_bytes()
    require(digest_bytes(raw)==contract_sha256 and json.loads(raw)==contract,'exact original contract bytes required')
    for entry in base.iterdir():
        physical(entry,owned=True)
        require(entry.name in SOURCE_NAMES|{'contract.json','authorization.json'} if entry.is_file() else entry.is_dir() and entry.name in {'logs','results','rendezvous'},'unexpected qualification root member')
    return contract


def validate_authorization(authority, contract, contract_sha256, context, *, now=None):
    now=time.time() if now is None else now
    require(isinstance(authority,dict) and authority.get('schema')=='r162_io_job_authorization_v1'
        and authority.get('status')=='ROOT_AUTHORIZED_OPAQUE_IO_QUALIFICATION','post-held root authorization required')
    require(authority.get('scope_id')==contract['scope_id'] and authority.get('contract_sha256')==contract_sha256
        and authority.get('slurm_array_job_id')==context['array_job_id'],'exact submitted array authority required')
    require(authority.get('resources')==RESOURCES and all(type(v) is int for v in authority['resources'].values())
        and authority.get('max_tasks')==contract['max_tasks'] and type(authority.get('max_tasks')) is int
        and authority.get('max_concurrent')==contract['max_concurrent'] and type(authority.get('max_concurrent')) is int
        and authority.get('source_files')==contract['source_files'],'exact source/resource/concurrency authority required')
    created=authority.get('created_epoch');expires=authority.get('expires_epoch')
    require(finite(created) and finite(expires) and contract['created_epoch']<=created<=now and now+RESOURCES['wall_seconds']<=expires<=contract['expires_epoch'],'whole declared allocation must fit original authority clock')
    require(authority.get('scientific_scale_admitted',False) is False and authority.get('new_model_fits',0)==0,'opaque authority cannot admit science')
    return authority


def allocation(contract, env=None):
    env=os.environ if env is None else env
    node=contract['node'];n=contract['max_tasks']
    require(socket.gethostname().split('.')[0]==node and env.get('SLURMD_NODENAME')==node,'actual compute node required')
    require(pwd.getpwuid(os.getuid()).pw_name=='jaguir26','actual qualification user required')
    require(env.get('SLURM_CPUS_PER_TASK')=='1' and env.get('SLURM_MEM_PER_NODE')=='4096' and env.get('SLURM_NTASKS')=='1','actual CPU/memory/task allocation differs')
    for key,value in (('SLURM_JOB_ACCOUNT','128x24'),('SLURM_JOB_PARTITION','128x24'),('SLURM_JOB_QOS','normal')):
        require(env.get(key,value)==value,'scheduler environment differs: '+key)
    parent=env.get('SLURM_ARRAY_JOB_ID','');task_id=env.get('SLURM_ARRAY_TASK_ID','');job=env.get('SLURM_JOB_ID','')
    require(parent.isdigit() and task_id.isdigit() and env.get('SLURM_ARRAY_TASK_COUNT')==str(n),'actual whole array identity required')
    tid=int(task_id);require(0<=tid<n and re.fullmatch(r'\d+(?:_\d+)?',job) is not None,'actual one-use array task/job required')
    require('_' not in job or job==parent+'_'+task_id,'array parent/task job identity differs')
    cpus=sorted(os.sched_getaffinity(0));require(len(cpus)==1,'exact single logical CPU affinity required')
    cpu=cpus[0];top=Path('/sys/devices/system/cpu')/('cpu'+str(cpu))/'topology'
    topology={name:(top/name).read_text().strip() for name in ('physical_package_id','core_id','thread_siblings_list')}
    fields=Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()
    return dict(job_id=job,array_job_id=parent,array_task_id=tid,array_task_count=n,node=node,affinity=cpus,
        physical_core=topology,uid=os.getuid(),user='jaguir26',pid=os.getpid(),start_ticks=int(fields[19]),
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),cpus_per_task=1,memory_MiB=4096)


class Limit:
    def __init__(self, expires_epoch):
        self.deadline=min(IMPORT_MONOTONIC+90,time.monotonic()+expires_epoch-time.time())
    def check(self):
        cpu=sum(resource.getrusage(resource.RUSAGE_SELF)[:2])+sum(resource.getrusage(resource.RUSAGE_CHILDREN)[:2])
        require(cpu<95 and time.monotonic()<self.deadline,'qualification aggregate CPU/wall boundary reached')
    def install(self):
        self.check();hard=resource.getrlimit(resource.RLIMIT_CPU)[1]
        require(hard==resource.RLIM_INFINITY or hard>=100,'compute CPU hard maximum insufficient')
        resource.setrlimit(resource.RLIMIT_CPU,(98,100))
        old=resource.getrlimit(resource.RLIMIT_AS)[1];memory=4096*1024**2
        require(old==resource.RLIM_INFINITY or old>=memory,'compute memory hard maximum insufficient')
        resource.setrlimit(resource.RLIMIT_AS,(memory,old))
        def stop(*args):raise QualificationError('hard qualification CPU/wall limit')
        signal.signal(signal.SIGALRM,stop);signal.signal(signal.SIGXCPU,stop)
        signal.setitimer(signal.ITIMER_REAL,max(.001,self.deadline-time.monotonic()))


def tree_members(root):
    root=physical(root,owned=True);result=set()
    for directory,dirs,files in os.walk(str(root),followlinks=False):
        for name in dirs:
            physical(Path(directory)/name,owned=True)
        for name in files:
            path=physical(Path(directory)/name,owned=True,regular=True)
            result.add(str(path.relative_to(root)))
    return result


def stream(path, expected, check, destination=None):
    path=physical(path,owned=True,regular=True);before=fingerprint(path);h=hashlib.sha256();count=0
    flags=os.O_RDONLY|getattr(os,'O_NOFOLLOW',0);fd=os.open(str(path),flags)
    output=None
    try:
        actual=os.fstat(fd);require((actual.st_dev,actual.st_ino)==(before['device'],before['inode']),'opened source identity changed')
        if destination is not None:
            physical(destination.parent,owned=True);output=destination.open('xb')
        with os.fdopen(fd,'rb',closefd=False) as src:
            while True:
                check();block=src.read(1024*1024)
                if not block:break
                count+=len(block);require(count<=expected['bytes'],'opaque member grew')
                h.update(block)
                if output is not None:output.write(block)
        if output is not None:output.flush();os.fsync(output.fileno())
    finally:
        if output is not None:output.close()
        os.close(fd)
    require(fingerprint(path)==before and count==expected['bytes'] and h.hexdigest()==expected['sha256'],'opaque source/hash/size changed')
    return dict(before,sha256=h.hexdigest())


def phase(name, function, check):
    check();start=time.time();mono=time.monotonic();cpu=time.process_time();io=Path('/proc/self/io').read_text()
    value=function();check()
    return dict(name=name,started_epoch=start,ended_epoch=time.time(),wall=time.monotonic()-mono,CPU=time.process_time()-cpu,
        proc_io_before=io,proc_io_after=Path('/proc/self/io').read_text(),details=value)


def cleanup_owned(root, identity, marker):
    root=physical(root,owned=True);require(fingerprint(root)['device']==identity['device'] and fingerprint(root)['inode']==identity['inode'],'owned scratch identity changed')
    require((root/'OWNED.json').read_bytes()==marker,'owned scratch marker changed')
    tree_members(root)
    require(getattr(shutil.rmtree,'avoids_symlink_attacks',False),'safe scratch removal unavailable')
    shutil.rmtree(str(root))


def execute_io(task, scratch_parent, *, check=lambda:None, scope_id='private_test', phase_hook=None):
    """Only opaque bytes; test fixtures may use tiny private temporary trees."""
    retained=physical(task['retained_root'],owned=True);files=task['files'];expected={str(relative(n).relative_to('stage')) for n in files}
    require(tree_members(retained/'stage')==expected,'retained stage membership differs')
    total=sum(v['bytes'] for v in files.values());parent=physical(scratch_parent,owned=False)
    require(parent.is_dir(),'scratch parent directory required')
    require(not(parent==retained or retained in parent.parents or parent in retained.parents),'scratch parent must be outside retained tree/ancestors')
    require(shutil.disk_usage(parent).free>=2*total+1024**3,'scratch disk floor not met')
    phases=[];source_before={}
    def verify_source():
        for name,record in sorted(files.items()):source_before[name]=stream(retained/relative(name),record,check)
        return dict(files=len(files),bytes=total,manifest_sha256=digest_bytes(json.dumps(files,sort_keys=True).encode()))
    phases.append(phase('source_hash',verify_source,check))
    root=Path(tempfile.mkdtemp(prefix='pricefm_'+scope_id+'_task'+str(task['task_id'])+'_',dir=str(parent)))
    identity=fingerprint(root);marker=(json.dumps(dict(scope_id=scope_id,task_id=task['task_id'],uid=os.getuid(),root=str(root)),sort_keys=True)+'\n').encode()
    with (root/'OWNED.json').open('xb') as f:f.write(marker)
    def copy():
        for name,record in sorted(files.items()):
            dest=root/relative(name);dest.parent.mkdir(parents=True,exist_ok=True);stream(retained/relative(name),record,check,dest)
        return dict(files=len(files),bytes=total)
    try:
        phases.append(phase('copy_to_scratch',copy,check))
        if phase_hook is not None:phase_hook(root)
        def verify_scratch():
            require(tree_members(root/'stage')==expected,'scratch membership differs')
            for name,record in sorted(files.items()):stream(root/relative(name),record,check)
            return dict(files=len(files),bytes=total)
        phases.append(phase('scratch_hash',verify_scratch,check))
        require(all(fingerprint(retained/relative(n))=={k:v for k,v in rec.items() if k!='sha256'} for n,rec in source_before.items()),'retained file metadata changed')
        result=dict(phases=phases,source_fingerprints=source_before,source_device=retained.stat().st_dev,scratch_device=root.stat().st_dev,
            distinct_source_scratch_devices=retained.stat().st_dev!=root.stat().st_dev,scratch_path=str(root),cache_state='UNKNOWN',
            source_immutable=True,total_bytes=total,files=len(files))
        cleanup_owned(root,identity,marker);result['scratch_cleanup']='OWNED_TREE_REMOVED';return result
    except BaseException as exc:
        raise QualificationError('opaque I/O failed; owned scratch retained at '+str(root)+': '+str(exc)) from exc


def aggregate_scratch_floor(contract, scratch):
    """Reserve for all simultaneous copies, even if scratch is shared."""
    scratch=physical(scratch,owned=False)
    total=sum(record['bytes'] for task in contract['tasks'] for record in task['files'].values())
    require(shutil.disk_usage(scratch).free>=2*total+1024**3,'aggregate scratch disk floor not met')
    return dict(all_task_bytes=total,required_free_bytes=2*total+1024**3,
        observed_free_bytes=shutil.disk_usage(scratch).free,device=scratch.stat().st_dev)


def rendezvous(contract, context, contract_sha, check):
    root=physical(contract['remote_root'],owned=True);directory=root/'rendezvous';directory.mkdir(exist_ok=True);physical(directory,owned=True)
    ready=dict(schema=SCHEMA,purpose=PURPOSE,scope_id=contract['scope_id'],contract_sha256=contract_sha,created_epoch=time.time(),allocation=context)
    atomic_new(directory/('task_'+str(context['array_task_id'])+'.ready.json'),ready)
    deadline=min(time.monotonic()+15,IMPORT_MONOTONIC+90);peers={}
    while len(peers)<contract['max_tasks']:
        check();require(time.monotonic()<deadline,'finite array rendezvous incomplete')
        for tid in range(contract['max_tasks']):
            path=directory/('task_'+str(tid)+'.ready.json')
            if not path.exists():continue
            value=read_json(path,65536);c=value.get('allocation',{})
            require(value.get('schema')==SCHEMA and value.get('purpose')==PURPOSE and value.get('scope_id')==contract['scope_id'] and value.get('contract_sha256')==contract_sha and c.get('array_task_id')==tid and type(c.get('array_task_id')) is int
                and c.get('array_job_id')==context['array_job_id'] and c.get('node')==context['node'] and c.get('uid')==context['uid']
                and c.get('array_task_count')==contract['max_tasks'] and c.get('cpus_per_task')==1 and c.get('memory_MiB')==4096
                and finite(value.get('created_epoch')) and 0<=time.time()-value['created_epoch']<=20,'peer ready identity/freshness differs')
            peers[str(tid)]=value
        if len(peers)<contract['max_tasks']:time.sleep(.05)
    return dict(observed_epoch=time.time(),peers=peers,interpretation='Ready overlap is observed; actual phase/Slurm allocation overlap and physical-core distinctness require controller reconciliation. No scientific scaling admitted.')


def import_guard(event,args):
    if event=='import' and args[0].split('.')[0] in {'numpy','scipy','pandas','rpy2','torch','sklearn'}:
        raise QualificationError('numerical import forbidden')
    if event=='subprocess.Popen':raise QualificationError('subprocess/R forbidden in opaque worker')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--contract',required=True);parser.add_argument('--contract-sha256',required=True);args=parser.parse_args(argv)
    sys.addaudithook(import_guard);output=None;started=time.time()
    try:
        require(sys.dont_write_bytecode,'-B required')
        path=physical(args.contract,owned=True,regular=True);require(path.stat().st_size<=2*1024**2,'bounded contract required')
        raw=path.read_bytes();require(digest_bytes(raw)==args.contract_sha256,'exact contract required')
        contract=validate_contract(json.loads(raw),args.contract_sha256,path.parent)
        require(path.name=='contract.json' and physical(Path(__file__).parent,owned=True)==path.parent==Path(contract['remote_root']),'actual source/contract qualification root differs')
        context=allocation(contract)
        parent=path.parent/'results';parent.mkdir(exist_ok=True);physical(parent,owned=True);output=parent/('task_'+str(context['array_task_id']));output.mkdir(exist_ok=False)
        auth_path=physical(path.parent/'authorization.json',owned=True,regular=True)
        require(auth_path.stat().st_size<=65536,'bounded job authorization required')
        auth_bytes=auth_path.read_bytes()
        authority=validate_authorization(json.loads(auth_bytes),contract,args.contract_sha256,context)
        authorization_sha=digest_bytes(auth_bytes)
        limit=Limit(min(contract['expires_epoch'],authority['expires_epoch']));limit.install()
        peers=rendezvous(contract,context,args.contract_sha256,limit.check)
        scratch=os.environ.get('SLURM_TMPDIR') or os.environ.get('TMPDIR') or '/tmp'
        scratch_floor=aggregate_scratch_floor(contract,scratch)
        io=execute_io(contract['tasks'][context['array_task_id']],scratch,check=limit.check,scope_id=contract['scope_id']);limit.check()
        result=dict(schema=SCHEMA,status='OPAQUE_IO_COMPLETE_NO_SCIENTIFIC_SCALE_ADMISSION',purpose=PURPOSE,scope_id=contract['scope_id'],contract_sha256=args.contract_sha256,authorization_sha256=authorization_sha,
            source_files=contract['source_files'],allocation=context,study=contract['tasks'][context['array_task_id']]['study'],rendezvous=peers,io=io,aggregate_scratch_floor=scratch_floor,
            started_epoch=started,ended_epoch=time.time(),aggregate_CPU_seconds=sum(resource.getrusage(resource.RUSAGE_SELF)[:2])+sum(resource.getrusage(resource.RUSAGE_CHILDREN)[:2]),
            elapsed_seconds=time.monotonic()-IMPORT_MONOTONIC,peak_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            new_model_fits=0,numerical_arrays_deserialized=0,new_predictions=0,scientific_scale_admitted=False,cache_state='UNKNOWN')
        receipt=atomic_new(output/'result.json',result);limit.check()
        atomic_new(output/'completed_evidence.json',dict(schema=SCHEMA,status='COMPLETE_OPAQUE_IO_ONLY',scope_id=contract['scope_id'],contract_sha256=args.contract_sha256,authorization_sha256=authorization_sha,
            task_id=context['array_task_id'],allocation=context,result_sha256=receipt['sha256'],source_files=contract['source_files'],scientific_scale_admitted=False))
        print(json.dumps(dict(status=result['status'],task_id=context['array_task_id'],result=receipt)))
    except BaseException as exc:
        if output is not None and not (output/'failure.json').exists():
            try:atomic_new(output/'failure.json',dict(schema=SCHEMA,status='FAILED_OPAQUE_IO_RETAINED_NO_RETRY',error_type=type(exc).__name__,error=str(exc),ended_epoch=time.time(),scientific_scale_admitted=False))
            except BaseException:pass
        print(json.dumps(dict(status='FAILED_OPAQUE_IO_RETAINED_NO_RETRY',error_type=type(exc).__name__,error=str(exc))),file=sys.stderr)
        raise


if __name__=='__main__':main()
