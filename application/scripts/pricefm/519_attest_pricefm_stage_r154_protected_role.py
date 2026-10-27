#!/usr/bin/env python3
"""Include one attested protected GNOME lifetime; never omit census rows."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import time

ENTRY=Path(__file__).resolve()
EXPECTED_PID=3567285
EXPECTED_ARGV=['/usr/bin/gnome-keyring-daemon','--start','--foreground','--components=secrets']


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def expected_path(runtime):return Path(runtime)/'protected_nonnum'/(sha(ENTRY)+'.json')


def fields(path):
    return dict(line.split(':',1) for line in path.read_text().splitlines() if ':' in line)


def sample_stat(path):
    raw=(path/'stat').read_text();value=raw[raw.rfind(')')+2:].split()
    return dict(pid=int(path.name),state=value[0],ppid=int(value[1]),process_group=int(value[2]),
        session_id=int(value[3]),start_ticks=int(value[19]),comm=raw[raw.find('(')+1:raw.rfind(')')])


def unavailable_link(path):
    try:
        os.readlink(path)
    except PermissionError:return 'UNAVAILABLE_PERMISSION_DENIED'
    raise RuntimeError('protected-role access policy changed; require new reviewed attestation')


def snapshot(path):
    path=Path(path);before=sample_stat(path)
    if before['pid']!=EXPECTED_PID or before['comm']!='gnome-keyring-d' or before['state']!='S':
        raise RuntimeError('protected process identity/state differs')
    uid=os.getuid();status=fields(path/'status');raw=(path/'cmdline').read_bytes()
    argv=[v.decode('utf-8') for v in raw.split(b'\0') if v]
    if (argv!=EXPECTED_ARGV or not raw.endswith(b'\0') or path.stat().st_uid!=uid
            or tuple(int(v) for v in status['Uid'].split())!=(uid,)*4
            or int(status['Pid'])!=EXPECTED_PID or int(status['Tgid'])!=EXPECTED_PID
            or int(status['PPid'])!=before['ppid']):
        raise RuntimeError('protected exact argv/UID/parent differs')
    thread_rows=[]
    for task in sorted((path/'task').iterdir(),key=lambda p:int(p.name)):
        start=sample_stat(task);s=fields(task/'status');cpus=sorted(os.sched_getaffinity(int(task.name)))
        if (tuple(int(v) for v in s['Uid'].split())!=(uid,)*4 or int(s['Tgid'])!=EXPECTED_PID
                or int(s['Pid'])!=int(task.name) or not cpus or start['state']!='S'):
            raise RuntimeError('protected thread UID/TGID/state/affinity differs')
        if sample_stat(task)!=start:raise RuntimeError('protected thread lifetime changed during read')
        thread_rows.append(dict(stat=start,cpus=cpus,cpu_status=s['Cpus_allowed_list'].strip()))
    if not thread_rows or EXPECTED_PID not in {t['stat']['pid'] for t in thread_rows}:
        raise RuntimeError('protected thread census incomplete')
    links={name:unavailable_link(path/name) for name in ('cwd','exe')}
    binary=Path(EXPECTED_ARGV[0]);bs=binary.stat()
    if binary.is_symlink() or bs.st_uid!=0 or bs.st_mode&0o022 or not stat.S_ISREG(bs.st_mode):
        raise RuntimeError('declared GNOME executable file is not fixed root-owned regular bytes')
    declared=dict(path=str(binary),sha256=sha(binary),device=bs.st_dev,inode=bs.st_ino,
        uid=bs.st_uid,mode=stat.S_IMODE(bs.st_mode),size=bs.st_size,
        evidence='DECLARED_ARGV0_FILE_ONLY_PROC_EXE_UNAVAILABLE')
    cgroups=[line.split(':',2)[2] for line in (path/'cgroup').read_text().splitlines()]
    after=sample_stat(path)
    if before!=after or (path/'cmdline').read_bytes()!=raw:
        raise RuntimeError('protected identity or argv changed during read')
    return dict(stat=before,boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        uid=uid,argv=argv,cmdline_sha256=hashlib.sha256(raw).hexdigest(),threads=thread_rows,
        cgroups=cgroups,missing_metadata=links,declared_executable_file=declared)


def collect():
    if socket.gethostname().split('.')[0].lower()!='jerez':raise RuntimeError('protected role attestation is Jerez-only')
    path=Path('/proc')/str(EXPECTED_PID);first=snapshot(path);second=snapshot(path)
    if first!=second:raise RuntimeError('protected snapshot is not stable across complete rereads')
    return first


def make_attestation(source):
    value=collect()
    return dict(schema_version=1,kind='R154_EXACT_INCLUDED_PROTECTED_NONNUMERICAL_ROLE',
        created_epoch=time.time(),creation_source=source,adapter_entry=str(ENTRY),adapter_sha256=sha(ENTRY),
        included_not_omitted=True,proc_executable_or_cwd_proved=False,expected=value,
        scope='Exact pre-existing protected GNOME lifetime only; unknown protected processes remain blocking')


def included_record(attestation_path,path):
    authority=json.loads(Path(attestation_path).read_text())
    if (authority.get('kind')!='R154_EXACT_INCLUDED_PROTECTED_NONNUMERICAL_ROLE'
            or authority.get('adapter_entry')!=str(ENTRY) or authority.get('adapter_sha256')!=sha(ENTRY)
            or authority.get('included_not_omitted') is not True
            or authority.get('proc_executable_or_cwd_proved') is not False
            or authority.get('expected',{}).get('argv')!=EXPECTED_ARGV
            or authority.get('expected',{}).get('stat',{}).get('pid')!=EXPECTED_PID
            or Path(path)!=Path('/proc')/str(EXPECTED_PID)):
        raise RuntimeError('protected resource attestation identity differs')
    current=collect()
    if current!=authority['expected']:raise RuntimeError('protected identity/argv/thread/resource state drifted')
    s=current['stat'];cpus=sorted({c for row in current['threads'] for c in row['cpus']})
    return dict(pid=s['pid'],start_ticks=s['start_ticks'],boot_id=current['boot_id'],state=s['state'],
        session_id=s['session_id'],ppid=s['ppid'],uid=current['uid'],argv=current['argv'],
        cmdline_sha256=current['cmdline_sha256'],cpus=cpus,cgroups=current['cgroups'],cwd=None,
        executable=None,partial_protected_metadata=True,missing_metadata=current['missing_metadata'],
        declared_executable_file=current['declared_executable_file'],all_threads=current['threads'],
        protected_attestation_path=str(attestation_path),protected_attestation_sha256=sha(attestation_path))
