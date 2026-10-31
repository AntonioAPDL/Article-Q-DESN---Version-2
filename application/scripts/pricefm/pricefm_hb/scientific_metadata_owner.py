"""Slurm-only, zero-target/zero-optimizer namespace and TSYNC qualification.

Uses the unchanged r157 ptrace owner directly, never below the H child filter.
It cannot execute a toy, bridge, pilot, model or target payload. Every invocation
needs a new exact spec/root/independent-review contract and private job flock.
"""
from __future__ import annotations
import argparse
import datetime as dt
import fcntl
import importlib.util
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import time

from . import startup_helper as h
from . import profile_admission as admission
from . import environment

ROLES={'SCIENTIFIC_NAMESPACE_NO_OPTIMIZER':'scientific_namespace_fixture.R',
       'SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER':'scientific_boundary_fixture.R'}
TRACE_SHA='914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963'
BOUNDARY_SHA='bab70fe340dadb350228d37eaa0ac4521f2c1d100b2a5a8b5f8843cbecb8a6fe'
ELF_SHA='9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
_UNREAPED_LOCK_FDS=[]


def sources(role):
    h.require(role in ROLES,'zero-optimizer role required')
    files=[Path(__file__).absolute(),Path(h.__file__).absolute(),Path(admission.__file__).absolute(),Path(environment.__file__).absolute(),
           Path(__file__).absolute().parent/ROLES[role],Path(__file__).absolute().parent/'scientific_namespace_fixture.R']
    return {str(p):h.pin(p) for p in sorted(set(files))}


def validate(spec_pin,authority_pin,review_pin,*,now=None,environ=None,affinity=None,node=None):
    now=time.time() if now is None else now;environ=os.environ if environ is None else environ
    affinity=os.sched_getaffinity(0) if affinity is None else affinity;node=os.uname().nodename.split('.')[0] if node is None else node
    spec,authority,review=(h.read(p) for p in (spec_pin,authority_pin,review_pin))
    role=spec.get('role');h.require(role in ROLES,'scientific numerical roles are not supported by metadata owner')
    h.require(type(spec.get('nonce')) is str and len(spec['nonce'])==32
              and all(c in '0123456789abcdef' for c in spec['nonce']),'exact hexadecimal fixture nonce required')
    h.require(spec.get('schema')=='r179_scientific_metadata_owner_spec_v1' and spec.get('optimizer_invocations')==0
              and spec.get('scientific_data_read') is False and spec.get('models')==0,'zero-target zero-optimizer spec required')
    h.require(environ.get('SLURM_JOB_ID','').isdigit() and spec.get('job_id')==environ.get('SLURM_JOB_ID')
              and spec.get('node')==environ.get('SLURMD_NODENAME')==node
              and not any(x in node.lower() for x in ['login','head','submit'])
              and environ.get('SLURM_CPUS_PER_TASK')=='1' and environ.get('TZ')=='UTC'
              and len(affinity)==1 and sorted(affinity)==spec.get('affinity'),'actual one-CPU Slurm compute/UTC identity required')
    h.require(all(type(authority.get(k)) in (int,float) and math.isfinite(authority[k]) for k in ['issued_epoch','expires_epoch'])
              and 0<authority['expires_epoch']-authority['issued_epoch']<=7200,'finite at-most-two-hour metadata authority required')
    h.require(authority.get('status')=='ROOT_ADMITTED_R179_SCIENTIFIC_METADATA_ONLY' and authority.get('spec')==spec_pin
              and authority.get('sources')==sources(role) and authority.get('memory_MiB')==8192
              and authority.get('whole_CPU_seconds')==600 and authority.get('whole_wall_seconds')==1200
              and authority.get('owner_CPU_seconds')==550 and authority.get('owner_wall_seconds')==900
              and authority.get('max_calls')==1 and authority['issued_epoch']<=now
              and now+1200<authority['expires_epoch'],'complete new source/job/root/funding window required')
    h.require(review.get('status')=='PASS_REVIEWED_R179_SCIENTIFIC_METADATA_OWNER_AND_SPEC'
              and review.get('spec')==spec_pin and review.get('authority')==authority_pin
              and review.get('sources')==sources(role),'independent exact owner/spec/authority review required')
    h.require(spec['traced_guard']['sha256']==TRACE_SHA and spec['boundary_library']['sha256']==BOUNDARY_SHA
              and spec['R_native']['sha256']==ELF_SHA,'unchanged tracer/boundary/native R source required')
    fixture=Path(__file__).absolute().parent/ROLES[role]
    h.require(spec['fixture']==h.pin(fixture),'exact role-specific zero-optimizer R fixture required')
    for key in ('traced_guard','boundary_library','R_native','namespace_spec'):
        h.read_pin(spec[key],limit=64*1024**2 if key in ('R_native','boundary_library') else 16*1024**2)
    ns=h.read(spec['namespace_spec'])
    h.require(ns.get('job_id')==spec['job_id'] and ns.get('node')==spec['node'] and ns.get('affinity')==spec['affinity']
              and ns.get('schema')=='r179_scientific_namespace_fixture_spec_v1'
              and ns.get('optimizer_invocations')==0 and ns.get('scientific_data_read') is False,'exact installed namespace fixture spec required')
    h.require(ns.get('namespace_fixture')==h.pin(Path(__file__).absolute().parent/'scientific_namespace_fixture.R')
              and ns.get('scientific_boundary_library')==spec['boundary_library'],'namespace/boundary fixture pins differ')
    env=spec['environment'];h.require(set(env)==h.ENV_KEYS and all(env.get(k)=='1' for k in h.THREAD_KEYS)
              and env.get('TZ')=='UTC' and env.get('SLURM_JOB_ID')==spec['job_id']
              and env.get('SLURMD_NODENAME')==spec['node'] and env.get('SLURM_CPUS_PER_TASK')=='1',
              'exact one-thread child job environment required')
    h.require(spec['R_native']['path']==str(Path(env['R_HOME'])/'bin/exec/R')
              and env['R_LIBS_USER']==env['R_LIBS_SITE']==ns['library'],
              'exact installed native R and library environment required')
    return spec,authority


def accepted_guard(receipt,role):
    flags=['reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled']
    h.require(receipt.get('schema')=='r157_traced_bootstrap_guard_receipt_v1'
              and receipt.get('status')=='EXITED' and receipt.get('returncode')==0
              and all(receipt.get(k) is True for k in flags)
              and receipt.get('remaining_owned_lifetimes')==[] and receipt.get('unexpected_untraced_child_waits')==[],
              'complete original ptrace ownership/CPU/drain proof required')
    if role=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER':
        att=receipt.get('scientific_filter_kernel_attestation') or {}
        h.require(receipt.get('postbootstrap_TSYNC_scientific_fork_denial') is True
                  and receipt.get('scientific_target_access_handshake') is True
                  and att.get('operation')=='SECCOMP_SET_MODE_FILTER' and att.get('flags')=='TSYNC'
                  and att.get('kernel_return')==0,'actual kernel TSYNC/ACK proof required')
    return True


def run(spec_pin,authority_pin,review_pin):
    started=time.monotonic();spec,authority=validate(spec_pin,authority_pin,review_pin)
    allocation={'job_id':spec['job_id']}
    scheduler=admission.scheduler_evidence(allocation)
    h.require(scheduler['memory_MiB']==8192 and 0<scheduler['cgroup_memory_limit_bytes']<=8192*1024**2
              and scheduler['cpus']==scheduler['tasks']==scheduler['nodes']==1
              and scheduler['wall_seconds']<=1200 and scheduler['end_epoch']>time.time()+900,
              'live whole one-CPU/8GiB/nonrequeueing scheduler+cgroup envelope required')
    for path,sha in spec['bootstrap_exec_allowlist'].items():h.read_pin({'path':path,'sha256':sha},limit=64*1024**2)
    h.require(spec['R_native']['path'] in spec['bootstrap_exec_allowlist'],'native R must be in exact bootstrap exec allowlist')
    out=h.physical(spec['output']);root=h.physical(spec['remote_namespace'])
    h.require(out.is_relative_to(root) and out!=root and not out.exists() and root.stat().st_uid==os.getuid()
              and stat.S_IMODE(root.stat().st_mode)&0o022==0,'new private job namespace required')
    out.mkdir(mode=0o700);h.write_new(out/'INTENT.json',{'status':'STARTED_SCIENTIFIC_METADATA_NOT_SUCCESS','spec':spec_pin,'authority':authority_pin,'review':review_pin,'sources':sources(spec['role'])})
    lock=out/'scientific_metadata.lock';fd=os.open(lock,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
    module_spec=importlib.util.spec_from_file_location('r179_unchanged_r157_traced_owner',spec['traced_guard']['path'])
    trace=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(trace)
    core=set(spec['affinity']);job=spec['job_id']
    def peer(owned):
        h.require(os.sched_getaffinity(0)==core and admission.cgroup_memory_limit()<=8192*1024**2,
                  'current allocated CPU/memory boundary changed')
        text=Path('/proc/self/cgroup').read_text()
        h.require('job_'+job in text or '/'+job+'/' in text,'own cgroup lost exact Slurm job identity')
        for expected in owned:
            row=trace.identity(expected['pid'])
            h.require(trace.same_lifetime(row,expected) and row['TracerPid']==os.getpid() and set(row['affinity'])==core,
                      'current tracee UID/birth/owner/affinity differs')
        return {'schema':'r179_current_own_Slurm_boundary_v1','job_id':job,'affinity':sorted(core),
                'cgroup_memory_limit_bytes':admission.cgroup_memory_limit(),'owned_lifetimes':len(owned),
                'Muscat_global_permit_or_peer_allowance_reused':False}
    command=[spec['R_native']['path'],'--no-echo','--no-restore','--no-save','--no-environ','--no-site-file','--no-init-file',
             '--file='+spec['fixture']['path'],'--args',spec['namespace_spec']['path'],spec['namespace_spec']['sha256'],spec['nonce']]
    safe_close=False
    try:
        with (out/'child.stdout').open('xb') as stdout,(out/'child.stderr').open('xb') as stderr:
            receipt=trace.run_traced(command,env=spec['environment'],stdout=stdout,stderr=stderr,lock_fd=fd,
              affinity=spec['affinity'],wall_seconds=900,maximum_combined_CPU_seconds=550,
              absolute_deadline_UTC=dt.datetime.fromtimestamp(min(authority['expires_epoch'],scheduler['end_epoch']),dt.timezone.utc).isoformat(),
              peer_callback=peer,bootstrap_exec_allowlist=spec['bootstrap_exec_allowlist'],owner_path=out/'owned_tree.json',
              scope=spec['scope_id'],source={'kind':'UNCHANGED_R157_TRACER_R179_METADATA_OWNER'},authority_pin=authority_pin,
              preexec_fn=lambda:resource.setrlimit(resource.RLIMIT_FSIZE,(1024**2,1024**2)),
              require_science_handshake=spec['role']=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER')
        h.write_new(out/'owned_guard.json',receipt)
        safe_close=receipt.get('reaped') is True and receipt.get('drained') is True and receipt.get('remaining_owned_lifetimes')==[]
        accepted_guard(receipt,spec['role'])
        raw=(out/'child.stdout').read_bytes();h.require(len(raw)<=1024**2,'bounded complete metadata stdout required')
        frames=[h.strict_json(line) for line in raw.splitlines() if line.lstrip().startswith(b'{')]
        expected=1 if spec['role']=='SCIENTIFIC_NAMESPACE_NO_OPTIMIZER' else 2
        h.require(len(frames)==expected and frames[0].get('status')=='PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY'
                  and all(f.get('nonce')==spec['nonce'] and f.get('optimizer_invocations')==0 and f.get('scientific_data_read') is False for f in frames),
                  'exact zero-target/optimizer namespace/boundary fixture frames required')
        if expected==2:h.require(frames[1].get('status')=='BOUNDARY_CHILD_ACKNOWLEDGED_AWAIT_PARENT_KERNEL_PROOF','boundary child ACK frame differs')
        u=resource.getrusage(resource.RUSAGE_SELF);c=resource.getrusage(resource.RUSAGE_CHILDREN);cpu=u.ru_utime+u.ru_stime+c.ru_utime+c.ru_stime
        h.require(cpu<600 and time.monotonic()-started<1200 and time.time()<authority['expires_epoch'],'whole new metadata-stage accounting failed')
        status='PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY' if expected==1 else 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
        result={'status':status,'schema':'r179_scientific_metadata_result_v1','spec':spec_pin,'authority':authority_pin,'review':review_pin,
                'owned_guard':h.pin(out/'owned_guard.json'),'namespace_frames':frames,'job_id':job,'node':spec['node'],
                'scheduler':scheduler,'whole_parent_plus_reaped_CPU':cpu,'wall_seconds':time.monotonic()-started,
                'original_guard_source_preserved':True,'optimizer_invocations':0,'scientific_data_read':False,
                'numerical_parity_proved':False,'production_admission':False,'requires_outer_reap_and_primary_Slurm_return_acceptance':True}
        h.write_new(out/'RESULT.json',result);return result
    except BaseException as error:
        h.write_new(out/'FAILED.json',{'status':'FAILED_SCIENTIFIC_METADATA_COST_RETAINED_NO_RETRY','error_type':type(error).__name__,'error':str(error),'optimizer_invocations':0})
        raise
    finally:
        if safe_close:os.close(fd)
        else:
            # No released-lock or approved drain is claimed. Keep the live
            # interpreter's FD and consumed output quarantined; process death
            # still requires fresh scheduler/owned-tree reconciliation.
            _UNREAPED_LOCK_FDS.append(fd)


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['spec','authority','review']:
        p.add_argument('--'+name,required=True);p.add_argument('--'+name+'-sha256',required=True)
    args=p.parse_args(argv);resource.setrlimit(resource.RLIMIT_CPU,(600,600));signal.alarm(1200)
    pins=[{'path':getattr(args,n),'sha256':getattr(args,n+'_sha256')} for n in ['spec','authority','review']]
    result=run(*pins);print(json.dumps({k:result[k] for k in ['status','job_id','node','optimizer_invocations','production_admission']},sort_keys=True))


if __name__=='__main__':main()
