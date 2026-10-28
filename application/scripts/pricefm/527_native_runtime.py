#!/usr/bin/env python3
"""R157 traced-bootstrap adapter; original numerical R bodies are unchanged."""
import hashlib
import importlib.util
import json
import math
import os
import re
import struct
import sys
import time
from pathlib import Path

HERE=Path(__file__).resolve().parent
def module(name):
    s=importlib.util.spec_from_file_location(name,HERE/(name+'.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
traced=module('526_traced_bootstrap_guard');legacy=module('525_owned_stage_guard')
FLAGS=('reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution',
       'tracer_death_kernel_EXITKILL_enabled','postbootstrap_TSYNC_scientific_fork_denial','scientific_target_access_handshake')

def new_source(source):
    return source.get('branch','').startswith('work/pricefm-r157-native-bootstrap-')

def pin(path):
    p=Path(path)
    if p.is_symlink() or not p.is_file():raise ValueError('regular immutable file required')
    return {'path':str(p.resolve()),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}

def read(value):
    if set(value)!={'path','sha256'} or pin(value['path'])!=value:raise ValueError('exact immutable pin differs')
    return json.loads(Path(value['path']).read_text())

def completed(receipt):
    proof=receipt.get('scientific_filter_kernel_attestation') or {}
    expected=b''.join(struct.pack('<HBBI',*row) for row in traced.scientific_filter_rows())
    paid=receipt.get('child_tree_CPU_seconds')
    return (receipt.get('schema')=='r157_traced_bootstrap_guard_receipt_v1' and
            receipt.get('status')=='EXITED' and type(receipt.get('returncode')) is int and receipt['returncode']==0 and
            all(receipt.get(k) is True for k in FLAGS) and receipt.get('whole_startup_subprocess_creation_kernel_denied') is False and
            receipt.get('bootstrap_subprocess_creation_allowed') is True and not receipt.get('remaining_owned_lifetimes') and
            not receipt.get('unexpected_untraced_child_waits') and proof.get('operation')=='SECCOMP_SET_MODE_FILTER' and
            proof.get('flags')=='TSYNC' and proof.get('kernel_return')==0 and
            proof.get('program_sha256')==hashlib.sha256(expected).hexdigest() and
            proof.get('instruction_count')==len(traced.scientific_filter_rows()) and
            receipt.get('CPU_accounting_basis')=='exclusive_subreaper_RUSAGE_CHILDREN_delta_once; raw_wait4_rows_not_summed' and
            type(paid) in (int,float) and math.isfinite(paid) and paid>=0)

def require_completed(receipt):
    if not completed(receipt):raise ValueError('new traced bootstrap/scientific-boundary receipt incomplete')
    return receipt

def _owner_package(grant):
    value=grant.get('owner_handoff')
    if value is None:raise ValueError('new shared-permit stage requires root owner handoff authority')
    pins=value['source_bindings'];paths={Path(p['path']).name:p for p in pins}
    if not {'handoff.py','policy.py','registry.py'}<=set(paths):raise ValueError('complete handoff package pins required')
    for p in pins:
        if pin(p['path'])!=p:raise ValueError('handoff implementation changed')
    path=Path(paths['handoff.py']['path'])
    if path.parent.name!='pricefm_hb' or any(Path(paths[n]['path']).parent!=path.parent for n in ('policy.py','registry.py')):raise ValueError('handoff package layout differs')
    sys.path.insert(0,str(path.parent.parent))
    from pricefm_hb import handoff,policy
    for name,expected in (('handoff.py',path),('policy.py',Path(paths['policy.py']['path'])),('registry.py',Path(paths['registry.py']['path']))):
        actual=sys.modules.get('pricefm_hb.'+name[:-3])
        if actual is None or Path(actual.__file__).resolve()!=expected.resolve():raise ValueError('cached handoff package differs from pinned package')
    return handoff,policy

def resolve_owner_admission(grant,root_grant_pin):
    """Acyclic: grant -> policy; canonical owner admission -> exact grant.

    The grant contains a scope, never the hash of its own admission envelope.
    Root publishes that envelope after hashing the grant. This function only
    reads, validates and pins it, and cannot create or self-admit an owner.
    """
    if read(root_grant_pin)!=grant:raise ValueError('owner authority is not the exact immutable running grant')
    value=grant.get('owner_handoff')
    if not isinstance(value,dict):raise ValueError('new shared-permit stage requires root owner handoff authority')
    if 'owner_admission_pin' in value:raise ValueError('circular owner-admission pin forbidden inside grant')
    if set(value)!={'source_bindings','policy_pin','scope_id'}:raise ValueError('exact canonical owner handoff fields required')
    scope=value.get('scope_id')
    if scope!=grant.get('scope_id') or not isinstance(scope,str) or not re.fullmatch(r'[A-Za-z0-9_-]{8,160}',scope):raise ValueError('exact canonical owner scope required')
    handoff,policy=_owner_package(grant)
    packet=policy.pinned(value['policy_pin']);policy.validate_policy(packet)
    directory=Path(packet['owner_admission_dir'])
    if not directory.is_absolute():raise ValueError('absolute canonical owner-admission directory required')
    admission_pin=pin(directory/(scope+'.json'));admission=policy.pinned(admission_pin)
    policy.validate_owner_admission(admission,packet,value['policy_pin'])
    if admission.get('scope_id')!=scope or admission.get('stage_grant')!=root_grant_pin:
        raise ValueError('canonical owner admission belongs to another scope or actual grant')
    return handoff,value['policy_pin'],admission_pin

def owner_callback(grant,output,root_grant_pin):
    """Read-only approved-owner captures by the actual FLOCK-holding parent."""
    handoff,policy_pin,admission_pin=resolve_owner_admission(grant,root_grant_pin)
    last=[None,0];counter=[0]
    def capture(fd,phase,proof):
        if not proof['kernel_trace_owned'] or not proof['all_helpers_owned']:raise ValueError('handoff without complete kernel ownership')
        if proof['state']=='UNREAPED_BLOCKED':raise ValueError('unreaped ownership cannot become approved finalization')
        if last[0]==phase and time.monotonic()-last[1]<10:return
        result=handoff.capture_owner_receipt(policy_pin,admission_pin,fd,phase=phase,
            CPU_accounting_complete_so_far=True,unowned_helpers=[])
        result['local_trace_proof']=proof
        counter[0]+=1;traced.immutable(Path(output)/('approved_owner_%04d.json'%counter[0]),result)
        last[:]=[phase,time.monotonic()]
    return capture

def exec_allowlist(runtime):
    paths=(runtime['actual_executable'],'/usr/bin/sh','/usr/bin/which','/usr/bin/uname','/usr/bin/rm')
    return {str(Path(p).resolve()):hashlib.sha256(Path(p).resolve().read_bytes()).hexdigest() for p in paths}

def native_environment(env,runtime,boundary_pin):
    read_pin=pin(boundary_pin['path'])
    if read_pin!=boundary_pin:raise ValueError('scientific boundary library changed')
    home=runtime['R_home'];value=dict(env,TZ='UTC',R_HOME=home,R_SHARE_DIR=home+'/share',R_INCLUDE_DIR=home+'/include',
        R_DOC_DIR=home+'/doc',R_ARCH='',LD_LIBRARY_PATH=home+'/lib',R157_BOUNDARY_LIBRARY=boundary_pin['path'])
    for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','BLIS_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):value[key]='1'
    return value

def native_command(runtime,root,kind,arguments):
    if kind not in ('toy','production'):raise ValueError('unknown exact project payload')
    return [runtime['actual_executable'],'--no-echo','--no-restore','--no-save','--no-environ','--no-site-file','--no-init-file',
            '--file='+str(Path(root)/'application/scripts/pricefm/527_project_bootstrap.R'),'--args',*map(str,arguments)]

def physical_peer_guard(census,disk_path,owned):
    """Add only this tracer's current kernel-held tree as owned exclusions.

    The original hash-bound peer census is never modified on disk. It is checked
    by the original physical-pair/resource primitive, with separately verified
    current ptrace-owned entries. A generic PID or another tracer is rejected.
    """
    original=dict(census);original['allowed_intersecting_processes']=list(census['allowed_intersecting_processes'])
    known={x['pid'] for x in original['allowed_intersecting_processes']};verified=[]
    for expected in owned:
        row=traced.identity(expected['pid'])
        if not traced.same_lifetime(row,expected) or row['boot_id']!=expected['boot_id'] or row['TracerPid']!=os.getpid():raise ValueError('owned exclusion is not an exact current kernel tracee')
        if row['pid'] in known:raise ValueError('owned tracee collides with original peer census PID')
        raw=(Path('/proc')/str(row['pid'])/'cmdline').read_bytes()
        original['allowed_intersecting_processes'].append({'pid':row['pid'],'start_ticks':row['start_ticks'],'boot_id':row['boot_id'],
            'cmdline_sha256':hashlib.sha256(raw).hexdigest(),'allowed_states':['R','S','D','T','t','Z','I']})
        known.add(row['pid']);verified.append(row)
    value=legacy.physical_peer_guard(original,disk_path)
    value['separately_verified_kernel_owned_tracees']=verified
    value['original_peer_census_not_modified']=True
    return value

def compatibility(proof_pin,boundary_pin):
    proof=read(proof_pin);require_completed(proof)
    if proof.get('optimizer_invocations')!=0 or proof.get('real_target_inputs') is not False or proof.get('numerical_parity_proved') is not False:
        raise ValueError('native metadata capability proof is not zero-target/optimizer')
    if proof.get('boundary_library')!=boundary_pin:raise ValueError('native boundary library differs from tested binary')
    for path,sha in proof['source_file_pins'].items():
        if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=sha:raise ValueError('tested native metadata source changed')
    root=HERE.parents[2]
    tested=(root/'application/tests/526_native_metadata_wrapper.R').read_text()
    deployed=(HERE/'527_project_bootstrap.R').read_text()
    first="manifest <- jsonlite::read_json"
    last="stopifnot(isTRUE(.Call('r157_scientific_boundary',NULL)))"
    def prefix(value):return value[value.index(first):value.index(last)+len(last)]
    if prefix(tested)!=prefix(deployed):raise ValueError('deployed package/filter bootstrap differs from actual tested prefix')
    return proof

def grant_compatibility(grant):
    proof=compatibility(grant['native_metadata_proof_pin'],grant['boundary_library_pin'])
    if proof.get('actual_R_runtime_binding')!=grant['actual_R_runtime_binding']:
        raise ValueError('actual native metadata R runtime differs from grant')
    if proof.get('bootstrap_executable_allowlist')!=grant['bootstrap_exec_allowlist']:
        raise ValueError('actual tested native executable closure differs from grant')
    return proof
