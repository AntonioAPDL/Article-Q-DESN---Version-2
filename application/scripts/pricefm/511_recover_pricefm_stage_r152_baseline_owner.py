#!/usr/bin/env python3
"""Truthful delegation to immutable cba504 with a bounded proc-read adapter.

The original core still owns numerical dispatch, locks, source identity,
generation seals and guardians. This execution source changes resource reads
only; it never hides a stable live protected process or signals a model.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import signal
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[3]
ENTRY=Path(__file__).resolve()
OLD_ROOT=ROOT.parent/'pricefm_r152_parallel_20261024'
CORE_ENTRY=OLD_ROOT/'application/scripts/pricefm/504_supervise_pricefm_stage_r152_baseline.py'
_CORE=None
_SOURCE_CACHE={}
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
def core():
    global _CORE
    if _CORE is None:_CORE=module('r152_truthfully_delegated_cba504',CORE_ENTRY)
    return _CORE

class RecoverySystem(core().System):
    """Retry exit/exec races with fresh stat proof, bounded to three reads."""
    def stat_sample(self,pid):
        try:raw=(Path('/proc')/str(pid)/'stat').read_text()
        except (FileNotFoundError,ProcessLookupError):return None
        fields=raw[raw.rfind(')')+2:].split()
        if len(fields)<20:raise RuntimeError('incomplete proc stat snapshot')
        return dict(pid=int(pid),state=fields[0],start_ticks=int(fields[19]),ppid=int(fields[1]),
            process_group=int(fields[2]),session_id=int(fields[3]),comm=raw[raw.find('(')+1:raw.rfind(')')])
    def terminal_or_gone(self,sample):return sample is None or sample['state'] in ('Z','X','x')
    def same_stat(self,before,after):return before['pid']==after['pid'] and before['start_ticks']==after['start_ticks']
    def metadata_event(self,kind,pid,sample,raw=None,value=None):
        if not hasattr(self,'metadata_history'):self.metadata_history={};self.metadata_events=[]
        key=(pid,sample.get('start_ticks'),self.boot_id);old=self.metadata_history.get(key)
        new_hash=hashlib.sha256(raw).hexdigest() if raw is not None else (value or {}).get('cmdline_sha256')
        event=dict(kind=kind,pid=pid,start_ticks=sample.get('start_ticks'),boot_id=self.boot_id,
            stat=sample,old_cmdline_sha256=(old or {}).get('cmdline_sha256'),new_cmdline_sha256=new_hash,
            old_argv=(old or {}).get('argv'),new_argv=(value or {}).get('argv'),
            old_cwd=(old or {}).get('cwd'),new_cwd=(value or {}).get('cwd'),epoch=time.time())
        if kind!='READABLE' or (old and (old.get('cmdline_sha256')!=new_hash or old.get('cwd')!=(value or {}).get('cwd'))):
            if kind=='READABLE':event['kind']='LIVE_METADATA_CHANGED'
            self.metadata_events.append(event);self.metadata_events=self.metadata_events[-64:]
        if value is not None and kind=='READABLE':
            self.metadata_history[key]={field:value.get(field) for field in ('cmdline_sha256','argv','cwd')}
            if len(self.metadata_history)>512:self.metadata_history.pop(next(iter(self.metadata_history)))
    def seed_expected(self,state):
        if not hasattr(self,'metadata_history'):self.metadata_history={};self.metadata_events=[]
        for job in state.get('active',{}).values():
            for row in [job.get('process'),*job.get('observed_children',[])]:
                if row:self.metadata_history.setdefault((row['pid'],row['start_ticks'],row['boot_id']),
                    {field:row.get(field) for field in ('cmdline_sha256','argv','cwd')})
    def empty_diagnostic(self,pid,sample,raw,value):
        self.metadata_event('EMPTY_EXIT_OR_EXEC',pid,sample,raw,value)
        return RuntimeError('stable live empty command metadata: '+json.dumps(self.metadata_events[-1],sort_keys=True))
    def administrative_snapshot(self,path):
        """Readable root-owned metadata only; never inspect protected cwd target."""
        before=self.stat_sample(int(path.name))
        if self.terminal_or_gone(before):return None
        status=dict(line.split(':',1) for line in (path/'status').read_text().splitlines() if ':' in line)
        command=(path/'cmdline').read_bytes().replace(b'\0',b' ').decode().strip()
        groups=[]
        for line in (path/'cgroup').read_text().splitlines():
            hierarchy,controllers,group=line.split(':',2)
            if controllers=='name=systemd' or (hierarchy=='0' and controllers==''):groups.append(group)
        owners={name:(path/name).stat().st_uid for name in ('stat','status','comm','cmdline','cgroup')}
        owners['cwd']=(path/'cwd').lstat().st_uid
        comm=(path/'comm').read_text().strip();after=self.stat_sample(int(path.name))
        stable=('pid','start_ticks','ppid','process_group','session_id','comm')
        if self.terminal_or_gone(after) or any(before.get(key)!=after.get(key) for key in stable):return None
        return dict(stat={key:before[key] for key in stable},uid=tuple(int(value) for value in status['Uid'].split()),
            status_pid=int(status['Pid']),status_ppid=int(status['PPid']),status_name=status['Name'].strip(),
            command=command,comm=comm,groups=groups,owners=owners,directory_uid=path.stat().st_uid)
    def verified_administrative_ssh(self,path,anchor):
        """Exclude an SSH session only with a stable privileged-parent proof."""
        try:
            username=pwd.getpwuid(os.getuid()).pw_name
            child=self.administrative_snapshot(path)
            if child is None or not self.same_stat(anchor,child['stat']):return False
            parent_path=Path('/proc')/str(child['stat']['ppid']);parent=self.administrative_snapshot(parent_path)
            if parent is None:return False
            if (child['comm']!='sshd' or child['status_name']!='sshd' or child['stat']['comm']!='sshd'
                    or parent['comm']!='sshd' or parent['status_name']!='sshd' or parent['stat']['comm']!='sshd'
                    or child['uid']!=(os.getuid(),)*4 or parent['uid']!=(0,)*4
                    or child['directory_uid']!=os.getuid() or parent['directory_uid']!=0
                    or any(owner!=0 for row in (child,parent) for owner in row['owners'].values())
                    or not re.fullmatch('sshd: '+re.escape(username)+r'@(notty|pts/[0-9]+)',child['command'])
                    or parent['command']!='sshd: '+username+' [priv]'
                    or child['status_pid']!=child['stat']['pid'] or child['status_ppid']!=parent['stat']['pid']
                    or parent['status_pid']!=parent['stat']['pid'] or parent['status_ppid']!=parent['stat']['ppid']
                    or child['stat']['ppid']!=parent['stat']['pid']
                    or child['stat']['session_id']!=parent['stat']['session_id'] or parent['stat']['session_id']!=parent['stat']['pid']
                    or child['stat']['process_group']!=parent['stat']['pid'] or parent['stat']['process_group']!=parent['stat']['pid']
                    or len(child['groups'])!=1 or child['groups']!=parent['groups']
                    or not re.fullmatch(re.escape('/user.slice/user-'+str(os.getuid())+'.slice/')+r'session-[0-9]+\.scope',child['groups'][0])):
                return False
            # Re-read both complete identities. A role/name match alone never
            # exempts a changing PID, session, command, UID or cgroup.
            return child==self.administrative_snapshot(path) and parent==self.administrative_snapshot(parent_path)
        except (OSError,KeyError,ValueError,TypeError):return False
    def process(self,pid):
        if not int(pid):return None
        anchor=self.stat_sample(pid)
        if self.terminal_or_gone(anchor):return None
        error=None;empty_until=None
        for attempt in range(21):
            raw=None;value=None;empty=False
            try:
                value=super().process(pid);after=self.stat_sample(pid)
                if self.terminal_or_gone(after):
                    if empty_until is not None:self.metadata_event('EMPTY_THEN_TERMINAL_OR_GONE',pid,after or anchor)
                    return None
                if not self.same_stat(anchor,after):raise RuntimeError('PID lifetime changed during bounded resource read')
                raw=(Path('/proc')/str(pid)/'cmdline').read_bytes()
                empty=not raw.strip(b'\0 \t\r\n') or (value is not None and not value.get('argv'))
                if value is not None:
                    if value['start_ticks']!=anchor['start_ticks']:raise RuntimeError('mixed process lifetime snapshot')
                    cwd=os.readlink(Path('/proc')/str(pid)/'cwd')
                    final=self.stat_sample(pid)
                    if self.terminal_or_gone(final):
                        if empty or empty_until is not None:self.metadata_event('EMPTY_THEN_TERMINAL_OR_GONE',pid,final or anchor,raw,value)
                        return None
                    if not self.same_stat(anchor,final):raise RuntimeError('PID lifetime changed after process metadata reread')
                    if not empty and hashlib.sha256(raw).hexdigest()==value['cmdline_sha256'] and cwd==value['cwd']:
                        self.metadata_event('READABLE',pid,final,raw,value);return value
                error=RuntimeError('live process exec metadata remained unstable')
            except (PermissionError,FileNotFoundError,ProcessLookupError) as exc:
                after=self.stat_sample(pid)
                if self.terminal_or_gone(after):
                    if empty_until is not None:self.metadata_event('EMPTY_THEN_TERMINAL_OR_GONE',pid,after or anchor)
                    return None
                if not self.same_stat(anchor,after):raise RuntimeError('PID lifetime changed during protected metadata read') from exc
                error=exc
                try:
                    raw=(Path('/proc')/str(pid)/'cmdline').read_bytes();empty=not raw.strip(b'\0 \t\r\n')
                except (PermissionError,FileNotFoundError,ProcessLookupError):pass
            if empty:
                error=self.empty_diagnostic(pid,after,raw,value)
                if empty_until is None:empty_until=time.monotonic()+.5
            if empty_until is not None:
                if attempt>=20 or time.monotonic()>=empty_until:break
                time.sleep(.025)
            elif attempt<2:time.sleep(.02)
            else:break
        raise error
    def census_process(self,path):
        try:
            if path.stat().st_uid!=os.getuid():return None
            anchor=self.stat_sample(int(path.name))
            if self.terminal_or_gone(anchor):return None
            error=None
            for attempt in range(3):
                try:
                    protected=(path/'cmdline').stat().st_uid!=os.getuid() or (path/'cwd').lstat().st_uid!=os.getuid()
                    if not protected:return self.process(int(path.name))
                    comm=(path/'comm').read_text().strip()
                    if comm=='(sd-pam)':return None
                    if comm=='sshd' and self.verified_administrative_ssh(path,anchor):return None
                    error=PermissionError('stable live protected own-UID process '+path.name)
                except (PermissionError,FileNotFoundError,ProcessLookupError) as exc:error=exc
                after=self.stat_sample(int(path.name))
                if self.terminal_or_gone(after):return None
                if not self.same_stat(anchor,after):raise RuntimeError('PID lifetime changed during protected census read')
                if attempt<2:time.sleep(.02)
            raise error
        except (FileNotFoundError,ProcessLookupError):
            # A final fresh stat, rather than missing cwd metadata, is required
            # before omission of a process that was visible to this census.
            sample=self.stat_sample(int(path.name))
            if self.terminal_or_gone(sample):return None
            raise
    def processes(self):
        result=[]
        for path in Path('/proc').iterdir():
            if path.name.isdigit():
                process=self.census_process(path)
                if process is not None:result.append(process)
        return result

def verify_baseline(runtime,master,system=None,allow_expired=False):
    """Explicit adapter for all cached-health readers; no imported rebinding."""
    c=core();runtime=Path(runtime);system=system or RecoverySystem()
    proof=c.baseline_ownership(runtime,master,system=system,allow_expired=allow_expired)
    state=c.read(runtime/'state.json');source=state.get('execution_control_source')
    if not source:raise RuntimeError('recovered baseline lacks explicit execution-source bridge')
    authority_path=Path(state['owner_recovery_authority_path'])
    if c.sha(authority_path)!=state['owner_recovery_authority_sha256']:raise RuntimeError('baseline recovery authority bytes changed')
    authority=c.read(authority_path);bridge=c.read(authority.get('execution_bridge_path',authority_path.parent/'execution_bridge.json'))
    argv=proof['owner'].get('argv',[])
    delegated=argv.index('--delegated-entry') if '--delegated-entry' in argv else -1
    expected=authority.get('expected_generation')
    if (expected not in (2,3) or proof['generation']!=expected or bridge.get('expected_generation')!=expected
            or delegated<0 or delegated+1>=len(argv) or argv[delegated+1]!=str(CORE_ENTRY) or str(ENTRY) not in argv
            or source!=authority.get('execution_source') or source!=bridge.get('execution_control_source')
            or bridge.get('authority_sha256')!=state['owner_recovery_authority_sha256']
            or bridge.get('master_sha256')!=proof['master_sha256'] or bridge.get('new_unit')!=state['new_unit']
            or bridge.get('config_sha256')!=state['config_sha256']
            or bridge.get('delegated_core_path')!=str(CORE_ENTRY) or bridge.get('delegated_core_sha256')!=c.sha(CORE_ENTRY)
            or not c.same_process(bridge.get('actual_process',{}),proof['owner'])):
        raise RuntimeError('baseline core/adapter/owner bridge differs')
    key=(source['head'],state['owner_recovery_authority_sha256']);now=time.monotonic()
    if _SOURCE_CACHE.get('key')!=key or now-_SOURCE_CACHE.get('verified',float('-inf'))>=5 or now<_SOURCE_CACHE.get('verified',now):
        release=module('r152_baseline_adapter_source_guard',ENTRY.with_name('510_release_pricefm_stage_r152_parent_recovery.py'))
        release.verify_source(source);_SOURCE_CACHE.update(key=key,verified=now)
    return proof

def run(authority_path,unit,delegated_entry, *, validator=None,system=None):
    c=core();system=system or RecoverySystem();authority_path=Path(authority_path).resolve()
    if Path(delegated_entry).resolve()!=CORE_ENTRY:raise RuntimeError('delegated entry is not the exact immutable cba504 core')
    validator=validator or module('r152_baseline_recovery_authority',ENTRY.with_name('512_release_pricefm_stage_r152_baseline_owner.py')).validate_authority
    authority=validator(authority_path,require_staged=True)
    expected_generation=authority.get('expected_generation')
    if unit!=authority['new_unit'] or expected_generation not in (2,3):raise RuntimeError('bounded owner generation authority differs')
    config=c.read_config(authority['config_path'])
    if config['new_unit']!=unit or c.sha(authority['config_path'])!=authority['config_sha256']:raise RuntimeError('append-only recovery configuration differs')
    if expected_generation>config['max_owner_generations']:raise RuntimeError('original bounded owner generations exhausted')
    runtime=Path(authority['baseline_runtime']);shared=Path(authority['shared_runtime']);master=c.read(shared/'master.json')
    if c.sha(shared/'master.json')!=authority['original_master']['sha256']:raise RuntimeError('original master bytes changed')
    deadline=time.monotonic()+20;attestation=Path(authority['attestation_path'])
    while not attestation.is_file():
        if time.monotonic()>=deadline:raise RuntimeError('bounded baseline launch attestation wait expired')
        time.sleep(.025)
    capsule=c.read(attestation);props=c.require_own_service(config,system);current=system.process(os.getpid())
    if (capsule.get('unit')!=unit or capsule.get('attested',{}).get('InvocationID')!=props.get('InvocationID')
            or not c.same_process(current,capsule.get('process',{}))
            or capsule.get('source_head')!=authority['execution_source']['head']
            or capsule.get('source_entry_path')!=str(ENTRY) or capsule.get('source_entry_sha256')!=c.sha(ENTRY)
            or str(CORE_ENTRY) not in current.get('argv',[]) or '--delegated-entry' not in current.get('argv',[])):
        raise RuntimeError('truthful delegated core/new adapter launch bridge differs')
    try:return _delegate_owned(authority_path,authority,unit,config,runtime,shared,master,props,current,system)
    except BaseException as error:
        state_path=runtime/'state.json';state=c.read(state_path)
        if (state.get('new_unit')!=unit or state.get('scope_id')!=master['scope_id']
                or state.get('owner_recovery_authority_sha256')!=c.sha(authority_path)
                or c.sha(shared/'master.json')!=authority['original_master']['sha256']):
            raise RuntimeError('refusing failure-state writes outside the attested owner authority') from error
        if getattr(system,'metadata_events',None):
            c.immutable(authority_path.parent/('wrapper_metadata_events.'+str(os.getpid())+'.json'),dict(
                error=repr(error),scope_id=master['scope_id'],metadata_events=system.metadata_events,
                expected_active_processes={lane:[job.get('process'),*job.get('observed_children',[])] for lane,job in state.get('active',{}).items()}))
        if state.get('phase')!='blocked':
            archive=authority_path.parent/('wrapper_before_failure.'+str(os.getpid())+'.json')
            data=state_path.read_bytes();fd,temporary=tempfile.mkstemp(prefix='.wrapper-state-',dir=authority_path.parent)
            try:
                with os.fdopen(fd,'wb') as stream:stream.write(data);stream.flush();os.fsync(stream.fileno())
                os.link(temporary,archive)
            finally:Path(temporary).unlink(missing_ok=True)
            state.update(phase='blocked',error=repr(error),epoch=time.time(),wrapper_failure_preserved_jobs=True)
            c.atomic(state_path,state);c.atomic(runtime/'blocked.json',dict(state,baseline_children_signalled=False,old_R145_resumed=False))
            epoch_path=runtime/'resource_ownership_epoch.json'
            if epoch_path.is_file() and c.same_process(c.read(epoch_path).get('owner',{}),current):
                c.publish_owner(runtime,state,system,master)
        raise

def _delegate_owned(authority_path,authority,unit,config,runtime,shared,master,props,current,system):
    c=core()
    state=c.read(runtime/'state.json');epoch=c.read(runtime/'resource_ownership_epoch.json')
    if (state.get('new_unit')!=unit or state.get('config_path')!=authority['config_path']
            or state.get('scope_id')!=master['scope_id'] or state.get('source')!=c.source_identity(config)
            or state.get('execution_control_source')!=authority['execution_source']
            or epoch.get('generation') not in (authority['expected_generation']-1,authority['expected_generation'])):
        raise RuntimeError('staged current baseline state/source/generation differs')
    if epoch['generation']==authority['expected_generation'] and not c.same_process(epoch['owner'],current):raise RuntimeError('authorized generation already belongs to another owner')
    if hasattr(system,'seed_expected'):system.seed_expected(state)
    bridge=dict(schema_version=1,scope_id=master['scope_id'],master_sha256=authority['original_master']['sha256'],
        original_start_epoch=master['start_epoch'],original_expires_epoch=master['expires_epoch'],
        delegated_core_path=str(CORE_ENTRY),delegated_core_sha256=c.sha(CORE_ENTRY),
        original_resource_source=state['source'],execution_control_source=authority['execution_source'],
        authority_path=str(authority_path),authority_sha256=c.sha(authority_path),new_unit=unit,
        expected_generation=authority['expected_generation'],actual_process=current,actual_invocation_id=props['InvocationID'],
        config_path=authority['config_path'],config_sha256=authority['config_sha256'],epoch=time.time())
    bridge_path=authority_path.parent/'execution_bridge.json'
    if bridge_path.exists():
        old=c.read(bridge_path)
        if not c.same_process(old['actual_process'],current):raise RuntimeError('execution bridge already belongs to another owner')
    else:c.immutable(bridge_path,bridge)
    return c.run(config,runtime,shared,Path(authority['pending_path']),config_path=Path(authority['config_path']),system=system)

def publish_private_generation_two(path):
    c=core();system=RecoverySystem();path=Path(path).resolve()
    c.probe_authority(path,system)
    source=module('r152_private_generation_two_source',ENTRY.with_name('510_release_pricefm_stage_r152_parent_recovery.py'))
    source.verify_source(c.read(path/'authority.json')['execution_source'])
    master=c.read(path/'private_master.json');state=c.read(path/'private_state.json')
    epoch=c.publish_owner(path,state,system,master)
    if epoch['generation']!=2:raise RuntimeError('private child did not publish generation2')
    return c.immutable(path/'generation_two_receipt.json',epoch)

def private_record(process,argv,system):
    sample=system.stat_sample(process.pid)
    return dict(pid=process.pid,start_ticks=sample['start_ticks'] if sample else None,boot_id=system.boot_id,
        declared_argv=list(argv),declared_cwd=str(OLD_ROOT))

def drain_private_record(record,system):
    signals=[]
    def live():
        value=system.stat_sample(record['pid'])
        return value is not None and value['start_ticks']==record['start_ticks'] and not system.terminal_or_gone(value)
    if record['start_ticks'] is None:
        if system.stat_sample(record['pid']) is not None:raise RuntimeError('unrecorded private helper lifetime remains')
        return dict(record,cleanup_verified=True,signals=[])
    for number in (signal.SIGTERM,signal.SIGKILL):
        if not live():return dict(record,cleanup_verified=True,signals=signals)
        current=system.process(record['pid'])
        if (current is None or current['start_ticks']!=record['start_ticks'] or current['boot_id']!=record['boot_id']
                or current['argv']!=record['declared_argv'] or current['cwd']!=record['declared_cwd']):
            raise RuntimeError('private helper metadata/lifetime differs; no signal sent')
        os.kill(record['pid'],number);signals.append(number)
        until=time.monotonic()+2
        while live() and time.monotonic()<until:time.sleep(.02)
    if live():raise RuntimeError('exact private helper did not drain')
    return dict(record,cleanup_verified=True,signals=signals)

def private_exit_stress(path):
    """Owned ordinary Python children, strict original session checks, no fits."""
    c=core();system=RecoverySystem();path=Path(path).resolve();c.probe_authority(path,system)
    owner=system.process(os.getpid());iterations=[]
    for index in range(12):
        argv=[c.read_config()['python_runtime'],'-B','-c','import time; time.sleep(.08)']
        child=subprocess.Popen(argv,
            cwd=str(OLD_ROOT),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        record=private_record(child,argv,system)
        expected=None;until=time.monotonic()+2
        try:
            while child.poll() is None and time.monotonic()<until:
                current=system.process(child.pid)
                if current is not None and '-c' in current['argv']:expected=current;break
            if expected is None:
                child.wait(timeout=2);iterations.append(dict(index=index,pid=child.pid,ready_snapshot=False,exit_confirmed=True));continue
            job=dict(process=owner,session_id=owner['session_id'],cpus=owner['cpus'],observed_children=[expected])
            system.seed_expected(dict(active=dict(private=job)));checks=0
            while child.poll() is None and time.monotonic()<until:
                c.session_members(job,system);checks+=1
                current=system.process(child.pid)
                if current is not None and not current.get('argv'):raise RuntimeError('private exit stress returned live empty argv')
            child.wait(timeout=2)
            if system.process(child.pid) is not None:raise RuntimeError('private exited child did not become absent')
            iterations.append(dict(index=index,pid=child.pid,start_ticks=expected['start_ticks'],ready_snapshot=True,strict_session_checks=checks,exit_confirmed=True))
        finally:
            if child.poll() is None:
                try:child.wait(timeout=2)
                except subprocess.TimeoutExpired:drain_private_record(record,system);child.wait(timeout=2)
    checks=sum(row.get('strict_session_checks',0) for row in iterations)
    adequate=checks>0 and any(row['ready_snapshot'] for row in iterations) and all(row['exit_confirmed'] for row in iterations)
    result=c.immutable(path/'exit_stress.json',dict(status='PASS_PRIVATE_EXIT_STRESS' if adequate else 'FAIL_PRIVATE_EXIT_STRESS',iterations=iterations,
        strict_session_checks=checks,
        observed_empty_transition_events=sum(row['kind']=='EMPTY_EXIT_OR_EXEC' for row in getattr(system,'metadata_events',[])),
        metadata_events=getattr(system,'metadata_events',[]),scientific_runs=0,production_units=0))
    if not adequate:raise RuntimeError('private exit stress did not exercise a ready child/session boundary')
    return result

def capability_probe(output,generation=2):
    """Actual private orphan and bounded owner adoption, zero numerical work."""
    c=core();release=module('r152_private_adoption_source',ENTRY.with_name('510_release_pricefm_stage_r152_parent_recovery.py'))
    source=release.source_identity();master=c.read(release.MASTER);system=RecoverySystem();began=time.monotonic()
    temporary=Path(tempfile.mkdtemp(prefix='pricefm-r152-baseline-probe-',dir='/tmp'));job=None;cleanup=None;extra_private=[];coverage_limited=False
    owner=system.process(os.getpid());config=c.read_config()
    if generation not in (2,3):raise RuntimeError('private owner generation is outside the original bound')
    c.immutable(temporary/'authority.json',dict(source=c.source_identity(config),execution_source=source,owner=owner,disposable=True))
    result=dict(schema_version=1,status='FAIL_R152_PRIVATE_BASELINE_ADOPTION_PROBE',execution_source=source,
        original_master_sha256=c.sha(release.MASTER),scope_id=master['scope_id'],original_start_epoch=master['start_epoch'],
        original_expires_epoch=master['expires_epoch'],generation=generation,exact_orphan_adoption=False,exact_cleanup=False,
        delegated_core_path=str(CORE_ENTRY),delegated_core_sha256=c.sha(CORE_ENTRY),adapter_sha256=c.sha(ENTRY),
        probe_namespace=str(temporary),numerical_dispatches=0,scientific_runs=0,production_units=0,cleanup_errors=[])
    try:
        publisher=subprocess.Popen([config['python_runtime'],'-B',str(CORE_ENTRY),'probe-orphan','--probe-runtime',str(temporary)],
            cwd=str(OLD_ROOT),start_new_session=True,preexec_fn=lambda:os.sched_setaffinity(0,{29}),
            stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        stdout,stderr=publisher.communicate(timeout=10)
        if publisher.returncode:raise RuntimeError('private immutable-core publisher failed: '+stderr)
        job=c.read(temporary/'orphan_job.json');adopted=c.session_members(job,system)
        if not any(c.same_process(row,job['child']) for row in adopted):raise RuntimeError('private exact orphan adoption failed')
        state=dict(scope_id=master['scope_id'],attempt='private-probe',source=c.source_identity(config),phase='running',
            guardian_unit='private-no-service',max_owner_generations=3)
        first=dict(schema_version=1,scope_id=master['scope_id'],attempt='private-probe',source=state['source'],
            generation=1,owner=job['process'],guardian_unit=state['guardian_unit'],heartbeat=time.time(),phase='blocked',
            expires_epoch=master['expires_epoch'],predecessor_sha256=None)
        c.immutable(temporary/'owner_epochs/001.json',first);c.atomic(temporary/'resource_ownership_epoch.json',first)
        if generation==2:
            final=c.publish_owner(temporary,state,system,master);prior=c.sha(temporary/'owner_epochs/001.json')
        else:
            c.immutable(temporary/'private_master.json',master);c.immutable(temporary/'private_state.json',state)
            argv=[config['python_runtime'],'-B',str(ENTRY),'publish-two','--probe-runtime',str(temporary)]
            child=subprocess.Popen(argv,
                cwd=str(OLD_ROOT),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            extra_private.append(private_record(child,argv,system))
            stdout,stderr=child.communicate(timeout=10)
            if child.returncode:raise RuntimeError('private generation2 publisher failed: '+stderr)
            second=c.read(temporary/'generation_two_receipt.json')
            if second['generation']!=2 or system.process(second['owner']['pid']) is not None:
                raise RuntimeError('private generation2 predecessor was not absent')
            result['generation_two_predecessor_absent']=True
            prior=c.sha(temporary/'owner_epochs/002.json');final=c.publish_owner(temporary,state,system,master)
            result['generation_three_predecessor_sha256_matches']=final['predecessor_sha256']==prior
            argv=[config['python_runtime'],'-B',str(ENTRY),'exit-stress','--probe-runtime',str(temporary)]
            stress=subprocess.Popen(argv,
                cwd=str(OLD_ROOT),start_new_session=True,preexec_fn=lambda:os.sched_setaffinity(0,{29}),
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            extra_private.append(private_record(stress,argv,system))
            stdout,stderr=stress.communicate(timeout=15)
            if stress.returncode:raise RuntimeError('private exit stress failed: '+stderr)
            result['exit_stress']=c.read(temporary/'exit_stress.json')
        if (final['generation']!=generation or final['predecessor_sha256']!=prior
                or final['scope_id']!=master['scope_id'] or final['expires_epoch']!=master['expires_epoch']):
            raise RuntimeError('private original-clock owner adoption failed')
        result['exact_orphan_adoption']=True
    except BaseException as error:
        result['error']=repr(error);coverage_limited=isinstance(error,subprocess.TimeoutExpired)
    finally:
        try:
            cleanup=c.cleanup_disposable_probe(temporary,system,job)
            result['exact_cleanup']=cleanup['cleanup_verified']
            cleanup_path=temporary/'cleanup.json'
            if cleanup_path.is_file():
                result.update(owned_cleanup_receipt_path=str(cleanup_path),owned_cleanup_receipt_sha256=c.sha(cleanup_path))
        except BaseException as error:result['exact_cleanup']=False;result['cleanup_errors'].append(repr(error))
        result['additional_private_lifetimes']=extra_private;result['additional_private_cleanup']=[]
        for record in extra_private:
            try:result['additional_private_cleanup'].append(drain_private_record(record,system))
            except BaseException as error:result['exact_cleanup']=False;result['cleanup_errors'].append(repr(error))
        if coverage_limited:
            result['exact_cleanup']=False;result['cleanup_errors'].append('private helper timed out; descendant coverage not inferred from orphan cleanup')
        result.update(orphan_CPU_bound_seconds=time.monotonic()-began+5.,epoch=time.time())
        if result['exact_orphan_adoption'] and result['exact_cleanup'] and not result['cleanup_errors']:
            result['status']='PASS_R152_PRIVATE_BASELINE_ADOPTION_PROBE' if generation==2 else 'PASS_R152_PRIVATE_BASELINE_GENERATION_THREE_PROBE'
        result['probe_driver_CPU_seconds']=time.process_time()+os.times().children_user+os.times().children_system+5.
        result['baseline_control_charged_CPU_seconds']=result['probe_driver_CPU_seconds']+result['orphan_CPU_bound_seconds']
        c.immutable(output,result)
    if not result['status'].startswith('PASS_'):raise RuntimeError('private adoption failed; exact cleanup/debit receipt preserved')
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',nargs='?',choices=('run','probe','publish-two','exit-stress'),default='run')
    parser.add_argument('--authority',type=Path);parser.add_argument('--unit');parser.add_argument('--delegated-entry',type=Path)
    parser.add_argument('--output',type=Path);parser.add_argument('--generation',type=int,choices=(2,3),default=2)
    parser.add_argument('--probe-runtime',type=Path);args=parser.parse_args()
    if args.action=='probe':value=capability_probe(args.output,args.generation)
    elif args.action=='publish-two':value=publish_private_generation_two(args.probe_runtime)
    elif args.action=='exit-stress':value=private_exit_stress(args.probe_runtime)
    else:value=run(args.authority,args.unit,args.delegated_entry)
    print(json.dumps(value,sort_keys=True))
if __name__=='__main__':main()
