"""One explicit R146 metadata waiter role; no generic Python/PID exemption.

All observations are read-only. Imported libraries are standard-library only.
The existing process keeps its observed broad affinity; this helper never moves,
signals, starts or changes it. Any incomplete proof leaves the old conflict.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time


def lifetime(p):
    return tuple(p.get(k) for k in ('boot_id','pid','start_ticks','cmdline_sha256'))


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def _identity(pid,details=False):
    root=Path('/proc')/str(pid);raw=(root/'stat').read_text();fields=raw[raw.rfind(')')+2:].split()
    cmd=(root/'cmdline').read_bytes();status=(root/'status').read_text().splitlines()
    uid=next(line.split()[1:] for line in status if line.startswith('Uid:'))
    value=dict(pid=pid,start_ticks=int(fields[19]),state=fields[0],ppid=int(fields[1]),
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        cmdline_sha256=hashlib.sha256(cmd).hexdigest(),argv=[v.decode() for v in cmd.split(b'\0') if v],
        executable=os.readlink(root/'exe'),uid=list(map(int,uid)))
    if details:
        value['cwd']=os.readlink(root/'cwd')
        value['threads']=[dict(tid=int(p.name),cpus=sorted(os.sched_getaffinity(int(p.name)))) for p in (root/'task').iterdir()]
        env={part.split(b'=',1)[0].decode():part.split(b'=',1)[1].decode()
             for part in (root/'environ').read_bytes().split(b'\0') if b'=' in part}
        value['_environment']=env
    return value


def _command(argv):
    result=subprocess.run(argv,text=True,capture_output=True,timeout=5)
    if result.returncode:raise RuntimeError('required read-only command failed: '+argv[0])
    return result.stdout.strip()


def _static(rule):
    pins=[rule['script'],rule['interpreter'],rule['parent']['executable_pin'],rule['unit']['fragment_pin'],*rule['configuration_pins']]
    hashes={p['path']:digest(p['path']) for p in pins}
    root=rule['source_root']
    source=dict(branch=_command(['git','-C',root,'branch','--show-current']),
        head=_command(['git','-C',root,'rev-parse','HEAD']),
        clean=not bool(_command(['git','-C',root,'status','--porcelain'])))
    return dict(hashes=hashes,source=source)


def observe_legacy_490(process,rule,prior_verified=None):
    """Collect fresh proof; no signal, new service or numerical-library import.

    A verified same-lifetime cache avoids repeated DBus only. Source, byte pins,
    parent, actual argv/environment/thread masks and identity remain freshly read.
    No unknown departed process can use that cache.
    """
    observation=dict(schema='r155_legacy_490_observation_v1',epoch=time.time(),observed=False,
        candidate_lifetime=list(lifetime(process)),cache_used=False)
    try:
        # A cheap exact-prefix test prevents full proof commands for other peers.
        if process.get('argv')!=rule['argv_exact']:return observation
        if time.time()>=rule['expires_epoch']:return observation
        static=_static(rule);observation.update(static)
        current=_identity(process['pid'],True)
        if lifetime(current)!=lifetime(process):return observation
        env=current.pop('_environment')
        observation['environment']={k:env.get(k) for k in rule['expected_thread_environment']}
        observation['environment_absent']={k:k not in env for k in rule['environment_must_be_absent']}
        observation['current']=current;observation['parent']=_identity(current['ppid'])
        cache=prior_verified if isinstance(prior_verified,dict) else {}
        if cache.get('positive_match') is True and cache.get('candidate_lifetime')==list(lifetime(process)):
            observation['unit']=cache['unit'];observation['unit_by_PID']=cache['unit_by_PID']
            observation['unit_proof_epoch']=cache['unit_proof_epoch'];observation['cache_used']=True
        else:
            fields=('Id','LoadState','ActiveState','SubState','MainPID','ExecMainPID','ExecStart','InvocationID',
                    'WorkingDirectory','FragmentPath','Restart','KillMode')
            raw=_command(['systemctl','--user','show',rule['unit']['Id'],*['--property='+k for k in fields]])
            observation['unit']=dict(line.split('=',1) for line in raw.splitlines() if '=' in line)
            obj=shlex.split(_command(['busctl','--user','call','org.freedesktop.systemd1','/org/freedesktop/systemd1',
                'org.freedesktop.systemd1.Manager','GetUnitByPID','u',str(process['pid'])]))
            if len(obj)!=2 or obj[0]!='o':raise RuntimeError('ambiguous DBus unit object')
            name=shlex.split(_command(['busctl','--user','get-property','org.freedesktop.systemd1',obj[1],
                'org.freedesktop.systemd1.Unit','Id']))
            if len(name)!=2 or name[0]!='s':raise RuntimeError('ambiguous DBus unit name')
            observation['unit_by_PID']=name[1];observation['unit_proof_epoch']=time.time()
        observation['closing_identity']=_identity(process['pid'])
        observation['observed']=True
    except (OSError,ValueError,KeyError,RuntimeError,subprocess.SubprocessError,StopIteration) as exc:
        observation['unavailable']=type(exc).__name__+': '+str(exc)
    return observation


def match_legacy_490(process,rule,observation):
    """Return false for every absent/mismatching/ambiguous required fact."""
    try:
        if not observation.get('observed') or time.time()>=rule['expires_epoch']:return False
        if rule['schema']!='r155_legacy_490_metadata_role_v1' or not rule['no_model_fit_forecast_dispatch']:return False
        if observation['candidate_lifetime']!=list(lifetime(process)):return False
        current=observation['current'];closing=observation['closing_identity'];parent=observation['parent']
        if lifetime(current)!=lifetime(process) or lifetime(closing)!=lifetime(process):return False
        if process.get('argv')!=rule['argv_exact'] or current['state']=='Z' or current['argv']!=rule['argv_exact'] or closing['argv']!=rule['argv_exact']:return False
        if current['cwd']!=rule['cwd_exact'] or current['executable']!=rule['resolved_executable']:return False
        if current['uid']!=[rule['owner_uid']]*4:return False
        if len(current['threads'])!=1 or current['threads'][0]['tid']!=current['pid']:return False
        if current['threads'][0]['cpus']!=rule['thread_mask_exact']:return False
        if observation['environment']!=rule['expected_thread_environment'] or not all(observation['environment_absent'].values()):return False
        if set(observation['environment_absent'])!=set(rule['environment_must_be_absent']):return False
        expected=rule['parent']
        if any(parent.get(k)!=expected[k] for k in ('pid','start_ticks','boot_id','cmdline_sha256','executable')):return False
        if parent['uid']!=[expected['uid']]*4 or current['ppid']!=expected['pid']:return False
        pins=[rule['script'],rule['interpreter'],expected['executable_pin'],rule['unit']['fragment_pin'],*rule['configuration_pins']]
        if any(observation['hashes'].get(p['path'])!=p['sha256'] for p in pins):return False
        if observation['source']!=rule['source']:return False
        unit=observation['unit'];contract=rule['unit']
        checks=dict(Id=contract['Id'],LoadState=contract['required_LoadState'],ActiveState=contract['required_ActiveState'],
            SubState=contract['required_SubState'],MainPID=str(current['pid']),ExecMainPID=str(current['pid']),
            WorkingDirectory=contract['WorkingDirectory'],FragmentPath=contract['FragmentPath'],
            Restart=contract['Restart'],KillMode=contract['KillMode'])
        if any(unit.get(k)!=v for k,v in checks.items()) or not unit.get('InvocationID'):return False
        start=re.fullmatch(r'\{ path=([^;]+) ; argv\[\]=([^;]+) ; ignore_errors=no ; .* \}',unit['ExecStart'])
        if start is None or start.group(1)!=rule['interpreter']['path'] or shlex.split(start.group(2))!=contract['ExecStart_argv_exact']:return False
        if observation['unit_by_PID']!=contract['Id']:return False
        return True
    except (KeyError,TypeError,ValueError,AttributeError):return False
