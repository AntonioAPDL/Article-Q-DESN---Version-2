"""Exact owned-file streams over strict SSH; no rsync, archive extraction or science.

Remote send/receive modes are one stdlib process under the existing supervisor.
The local transfer helper owns one SSH child in its supervised session.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import shlex
import stat
import struct
import subprocess
import sys
import time
import uuid

MAGIC=b'PFMSTRM1'; END=b'PFMEND1\n'; CHUNK=65536
HEADER_MAX=16*1024**2; FILES_MAX=16384; BYTE_MAX=8*1024**3; RESPONSE_MAX=65536


def require(value,message):
    if not value:raise ValueError(message)


def physical(path):
    path=Path(path)
    require(path.is_absolute() and '..' not in path.parts,'absolute physical path required')
    require(not {'.ssh','.git','.codex'}.intersection(path.parts),'credential/Git/agent paths prohibited')
    for p in (path,*path.parents):require(not p.is_symlink(),'symlink path prohibited')
    return path


def safe_name(name):
    require(type(name) is str and 0<len(name.encode())<=4096 and
            re.fullmatch(r'[A-Za-z0-9_./-]+',name) and not name.startswith('/') and
            str(PurePosixPath(name))==name and len(PurePosixPath(name).parts)<=64 and
            not ({'.','..','.ssh','.git','.codex'} & set(PurePosixPath(name).parts)),
            'unsafe stream member path')
    return name


def fingerprint(s):return (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)


def publication_identity(value):
    # Link/unlink legitimately change ctime and nlink, but none of these fields.
    return (value.st_dev,value.st_ino,value.st_uid,value.st_mode,value.st_size,value.st_mtime_ns)


def publish_noreplace(fd,part,final,expected_part):
    """BeeGFS-supported create-only link, validated cleanup, then durable ACK.

    A concurrent marker consumer must wait for nlink1. A crash before unlink
    deliberately leaves nlink2 and cannot become numerical authority.
    """
    source=os.open(part,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
    target=None
    try:
        before=os.fstat(source);named=os.stat(part,dir_fd=fd,follow_symlinks=False)
        require(stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid() and before.st_nlink==1
                and fingerprint(before)==expected_part and fingerprint(named)==fingerprint(before)
                and publication_identity(named)==publication_identity(before) and named.st_nlink==1,
                'pending publication file identity changed')
        try:os.link(part,final,src_dir_fd=fd,dst_dir_fd=fd,follow_symlinks=False)
        except FileExistsError:raise ValueError('create-only atomic destination already exists') from None
        target=os.open(final,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
        def linked_state(links):
            held=os.fstat(source);published=os.fstat(target)
            current=os.stat(final,dir_fd=fd,follow_symlinks=False)
            require(all(stat.S_ISREG(v.st_mode) and v.st_nlink==links and
                        publication_identity(v)==publication_identity(before) and
                        fingerprint(v)==fingerprint(held) for v in (held,published,current)),
                    'linked publication identity or link count changed')
            return held
        linked=linked_state(2)
        named=os.stat(part,dir_fd=fd,follow_symlinks=False)
        require(named.st_nlink==2 and publication_identity(named)==publication_identity(before)
                and fingerprint(named)==fingerprint(linked),'pending publication path changed before unlink')
        os.unlink(part,dir_fd=fd)
        linked_state(1);os.fsync(fd);linked_state(1)
    finally:
        if target is not None:os.close(target)
        os.close(source)


def directory_fd(path):
    path=physical(path);require(len(path.parts)<=128,'absolute directory depth exceeded')
    fd=os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        for part in path.parts[1:]:
            child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
            os.close(fd);fd=child
        return fd
    except BaseException:
        os.close(fd);raise


def source_file(path,before):
    parent=directory_fd(path.parent)
    try:fd=os.open(path.name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=parent)
    finally:os.close(parent)
    try:
        s=os.fstat(fd);require(stat.S_ISREG(s.st_mode) and s.st_uid==os.getuid() and s.st_nlink==1 and
                              fingerprint(s)==before,'source initial FD identity differs')
        return os.fdopen(fd,'rb')
    except BaseException:os.close(fd);raise


def regular(path,device=None):
    path=physical(path);s=path.stat()
    require(stat.S_ISREG(s.st_mode) and s.st_uid==os.getuid() and s.st_nlink==1,
            'owned single-link regular source required')
    require(device is None or s.st_dev==device,'cross-filesystem source prohibited')
    return s


def decode(raw):
    def pairs(rows):
        out={}
        for k,v in rows:
            require(k not in out,'duplicate JSON key');out[k]=v
        return out
    def bad(value):raise ValueError('nonfinite JSON '+value)
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=bad)


def manifest(source,max_bytes=BYTE_MAX):
    require(type(max_bytes) is int and 0<max_bytes<=BYTE_MAX,'bounded stream byte cap required')
    source=physical(source);kind='file' if source.is_file() else 'directory'
    require(source.exists() and source.stat().st_uid==os.getuid(),'owned stream source required')
    paths=[];device=source.stat().st_dev;directory_count=0
    if kind=='file':paths=[(source,source.name)]
    else:
        require(source.is_dir(),'regular source file or directory required')
        for root,dirs,files in os.walk(source,followlinks=False):
            for name in dirs:
                directory_count+=1;require(directory_count<=FILES_MAX,'source directory count exceeded')
                p=physical(Path(root)/name);s=p.stat()
                require(stat.S_ISDIR(s.st_mode) and s.st_uid==os.getuid() and s.st_dev==device,'unsafe source directory')
                safe_name(str(p.relative_to(source)))
            for name in files:
                p=Path(root)/name;paths.append((p,str(p.relative_to(source))))
                require(len(paths)<=FILES_MAX,'stream file count exceeded')
    entries=[];sources={};total=0
    for path,name in sorted(paths,key=lambda x:x[1]):
        safe_name(name);before=regular(path,device);total+=before.st_size
        require(total<=max_bytes,'stream total byte cap exceeded before hashing')
        h=hashlib.sha256()
        with source_file(path,fingerprint(before)) as f:
            require(fingerprint(os.fstat(f.fileno()))==fingerprint(before),'source replaced before read')
            remaining=before.st_size
            while remaining:
                block=f.read(min(CHUNK,remaining));require(block,'source truncated while hashed');h.update(block);remaining-=len(block)
            require(not f.read(1),'source grew past initial-size hash bound')
            require(fingerprint(os.fstat(f.fileno()))==fingerprint(before)==fingerprint(regular(path,device)),
                    'source changed while hashed')
        entries.append(dict(name=name,bytes=before.st_size,sha256=h.hexdigest(),mode=stat.S_IMODE(before.st_mode)&0o700))
        sources[name]=(path,fingerprint(before))
    return dict(schema='r164_exact_file_stream_v1',kind=kind,total_bytes=total,files=entries),sources


def validate_manifest(value,max_bytes):
    require(type(max_bytes) is int and 0<max_bytes<=BYTE_MAX,'bounded stream byte cap required')
    require(type(value) is dict and set(value)=={'schema','kind','total_bytes','files'} and
            value['schema']=='r164_exact_file_stream_v1' and value['kind'] in ('file','directory'), 'exact stream manifest required')
    require(type(value['files']) is list and len(value['files'])<=FILES_MAX,'bounded stream member count required')
    names=[];total=0
    for entry in value['files']:
        require(type(entry) is dict and set(entry)=={'name','bytes','sha256','mode'},'exact stream member required')
        names.append(safe_name(entry['name']))
        require(type(entry['bytes']) is int and 0<=entry['bytes']<=max_bytes,'stream file byte cap exceeded')
        require(type(entry['sha256']) is str and re.fullmatch(r'[0-9a-f]{64}',entry['sha256']), 'invalid stream hash')
        require(type(entry['mode']) is int and entry['mode']&~0o700==0 and entry['mode']&0o400,'safe owner permission mode required')
        total+=entry['bytes'];require(total<=max_bytes,'stream total byte cap exceeded')
    require(names==sorted(set(names)) and type(value['total_bytes']) is int and total==value['total_bytes'],
            'duplicate/reordered members or total mismatch')
    require(value['kind']!='file' or len(names)==1,'one member required for file stream')
    return value


def send(source,write,max_bytes=BYTE_MAX):
    value,sources=manifest(source,max_bytes);header=json.dumps(value,sort_keys=True,separators=(',',':')).encode()
    require(len(header)<=HEADER_MAX,'stream header cap exceeded')
    write(MAGIC+struct.pack('!Q',len(header))+header)
    for entry in value['files']:
        path,before=sources[entry['name']];require(fingerprint(regular(path))==before,'source changed before streaming')
        h=hashlib.sha256();count=0
        with source_file(path,before) as f:
            require(fingerprint(os.fstat(f.fileno()))==before,'source replaced before streaming')
            while count<entry['bytes']:
                block=f.read(min(CHUNK,entry['bytes']-count));require(block,'source truncated during streaming')
                write(block);h.update(block);count+=len(block)
            require(not f.read(1) and fingerprint(os.fstat(f.fileno()))==before==fingerprint(regular(path)), 'source grew/changed during streaming')
        require(h.hexdigest()==entry['sha256'],'streamed source SHA mismatch')
    digest=hashlib.sha256(header).digest();write(END+digest)
    return dict(manifest_sha256=digest.hex(),files=len(value['files']),bytes=value['total_bytes'])


def exact(read,n):
    out=bytearray()
    while len(out)<n:
        block=read(n-len(out));require(block,'truncated stream');require(len(block)<=n-len(out),'reader exceeded requested size');out.extend(block)
    return bytes(out)


def receive(target,read,max_bytes=BYTE_MAX,directory=False):
    require(exact(read,len(MAGIC))==MAGIC,'stream magic differs')
    length=struct.unpack('!Q',exact(read,8))[0];require(0<length<=HEADER_MAX,'stream header length exceeded')
    header=exact(read,length);value=validate_manifest(decode(header),max_bytes)
    target=physical(target);as_file=value['kind']=='file' and not directory
    root=target.parent if as_file else target
    root_state=root.stat()
    require(stat.S_ISDIR(root_state.st_mode) and root_state.st_uid==os.getuid(),'owned existing destination directory required')
    device=root_state.st_dev
    pending=[];nonce=uuid.uuid4().hex;root_fd=directory_fd(root)
    def parent_fd(name):
        fd=os.dup(root_fd)
        try:
            for part in PurePosixPath(name).parts[:-1]:
                try:os.mkdir(part,mode=0o700,dir_fd=fd)
                except FileExistsError:pass
                child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=fd)
                s=os.fstat(child);require(s.st_uid==os.getuid() and s.st_dev==device,'unsafe destination ancestry')
                os.close(fd);fd=child
            return fd
        except BaseException:os.close(fd);raise
    def absent(fd,name):
        try:os.stat(name,dir_fd=fd,follow_symlinks=False)
        except FileNotFoundError:return
        raise ValueError('create-only destination already exists')
    try:
        opened_root=os.fstat(root_fd)
        require((opened_root.st_dev,opened_root.st_ino,opened_root.st_uid,opened_root.st_mode)==
                (root_state.st_dev,root_state.st_ino,root_state.st_uid,root_state.st_mode),
                'opened destination root identity changed')
        for entry in value['files']:
            name=target.name if as_file else entry['name'];safe_name(name);fd=parent_fd(name)
            final=PurePosixPath(name).name;part='.'+final+'.profile-part-'+nonce
            try:
                absent(fd,final);output=os.open(part,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_NONBLOCK,0o600,dir_fd=fd)
                h=hashlib.sha256();remaining=entry['bytes']
                with os.fdopen(output,'wb') as f:
                    while remaining:
                        block=exact(read,min(CHUNK,remaining));f.write(block);h.update(block);remaining-=len(block)
                    f.flush();os.fchmod(f.fileno(),entry['mode']);os.fsync(f.fileno());part_state=os.fstat(f.fileno())
                require(h.hexdigest()==entry['sha256'],'received file SHA mismatch');pending.append((name,part,fingerprint(part_state)))
            finally:os.close(fd)
        expected=hashlib.sha256(header).digest()
        require(exact(read,len(END))==END and exact(read,32)==expected,'stream trailer/manifest SHA mismatch')
        require(not read(1),'trailing stream bytes prohibited')
        for name,part,expected_part in pending:
            fd=parent_fd(name);final=PurePosixPath(name).name
            try:
                absent(fd,final);publish_noreplace(fd,part,final,expected_part)
            finally:os.close(fd)
    finally:os.close(root_fd)
    return dict(manifest_sha256=expected.hex(),files=len(value['files']),bytes=value['total_bytes'])


class Pipes:
    """Bounded nonblocking duplex SSH IO; diagnostics never mix with file bytes."""
    def __init__(self,process,wall):
        self.p=process;self.deadline=time.monotonic()+wall;self.err=bytearray();self.out=bytearray();self.eof=set()
        for stream in (process.stdin,process.stdout,process.stderr):os.set_blocking(stream.fileno(),False)
    def _wait(self,write=False):
        remaining=self.deadline-time.monotonic();require(remaining>0,'stream wall deadline exhausted')
        reads=[self.p.stderr] if 'stderr' not in self.eof else []
        if 'stdout' not in self.eof:reads.append(self.p.stdout)
        return select.select(reads,[self.p.stdin] if write else [],[],min(remaining,1))[:2]
    def _read_ready(self,reads,stdout_limit=RESPONSE_MAX):
        for stream in reads:
            try:block=os.read(stream.fileno(),CHUNK)
            except BlockingIOError:continue
            name='stderr' if stream is self.p.stderr else 'stdout'
            if not block:self.eof.add(name);continue
            dest=self.err if name=='stderr' else self.out;dest.extend(block)
            require(len(dest)<=(RESPONSE_MAX if name=='stderr' else stdout_limit),'bounded SSH diagnostic/response exceeded')
    def write(self,data):
        view=memoryview(data)
        while view:
            reads,writes=self._wait(True);self._read_ready(reads)
            if writes:
                try:n=os.write(self.p.stdin.fileno(),view[:CHUNK])
                except BlockingIOError:continue
                view=view[n:]
    def read(self,n):
        while not self.out and 'stdout' not in self.eof:
            reads,_=self._wait();self._read_ready(reads,CHUNK*2)
        block=bytes(self.out[:n]);del self.out[:len(block)];return block
    def finish(self):
        if self.p.stdin and not self.p.stdin.closed:self.p.stdin.close()
        while len(self.eof)<2:
            reads,_=self._wait();self._read_ready(reads)
        code=self.p.wait(timeout=max(.001,self.deadline-time.monotonic()))
        require(code==0,'SSH stream failed: '+bytes(self.err).decode(errors='replace')[-2000:])
        return bytes(self.out)


def transfer(source,target,ssh_argv,remote_helper_source,cpu,wall,max_bytes,scope):
    require(type(cpu) is int and 2<=cpu<=300 and type(wall) is int and 0<wall<=1800 and
            type(max_bytes) is int and 0<max_bytes<=BYTE_MAX,'finite transfer caps required')
    require(type(ssh_argv) is list and ssh_argv and all(type(x) is str and '\x00' not in x for x in ssh_argv),'exact strict SSH argv required')
    require(type(remote_helper_source) is str and 0<len(remote_helper_source.encode())<=HEADER_MAX,'pinned remote supervisor source required')
    require(type(scope) is str and re.fullmatch(r'[A-Za-z0-9_-]{8,160}',scope),'exact transfer scope required')
    prefix=ssh_argv[-1]+':';upload=target.startswith(prefix);download=source.startswith(prefix)
    require(upload!=download,'exactly one endpoint must use the supplied SSH destination')
    remote_path=(target if upload else source)[len(prefix):]
    require(re.fullmatch(r'/(?:home|mnt/beegfs/home)/jaguir26/[A-Za-z0-9_./-]+',remote_path) and '..' not in Path(remote_path).parts,
            'owned safe HB endpoint required')
    local=source if upload else target;remote_source=Path(__file__).read_text()
    mode='--receive' if upload else '--send'
    payload=['/usr/bin/python3','-I','-B','-c',remote_source,mode,'--path',remote_path,'--max-bytes',str(max_bytes)]
    if upload and target.endswith('/'):payload.append('--directory')
    command=['/usr/bin/python3','-I','-B','-c',remote_helper_source,'--cpu',str(cpu),'--wall',str(wall),
             '--output-cap',str(max_bytes+HEADER_MAX+128),'--passthrough','--',*payload]
    p=subprocess.Popen([*ssh_argv,shlex.join(command)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    io=Pipes(p,wall)
    try:
        if upload:
            result=send(local,io.write,max_bytes);io.p.stdin.close();ack=decode(io.finish())
            require(ack==result,'remote receipt differs from sent manifest')
        else:
            io.p.stdin.close();result=receive(local,io.read,max_bytes,directory=target.endswith('/'));io.finish()
        return dict(status='COMPLETE_EXACT_OWNED_FILE_STREAM',direction='upload' if upload else 'download',scope=scope,**result)
    finally:
        for stream in (p.stdin,p.stdout,p.stderr):
            if stream and not stream.closed:stream.close()
        # Cancellation/reaping belongs to the outer session supervisor, which
        # also accounts this helper and its SSH child as one owned subtree.


def main():
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--task');mode.add_argument('--send',action='store_true');mode.add_argument('--receive',action='store_true')
    parser.add_argument('--path');parser.add_argument('--max-bytes',type=int,default=BYTE_MAX);parser.add_argument('--directory',action='store_true')
    args=parser.parse_args()
    if args.task:
        p=physical(args.task);require(p.suffix=='.json' and p.stat().st_size<=HEADER_MAX,'bounded JSON transfer task required')
        task=decode(p.read_bytes());require(set(task)=={'source','target','ssh_argv','remote_helper_source','cpu','wall','max_bytes','scope'},'exact transfer task fields required')
        print(json.dumps(transfer(**task),sort_keys=True))
    elif args.send:send(args.path,lambda block:sys.stdout.buffer.write(block),args.max_bytes);sys.stdout.buffer.flush()
    else:print(json.dumps(receive(args.path,sys.stdin.buffer.read,args.max_bytes,args.directory),sort_keys=True),flush=True)


if __name__=='__main__':main()
