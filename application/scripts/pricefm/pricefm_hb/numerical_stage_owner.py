"""New-purpose Slurm owner for frozen525 toy or one zero-update NO3 bridge.

No optimizer or target is admitted by importing/preparing this module. Each
compute invocation requires exact new source/spec/root/peer/READY binding and a
current r157 TSYNC+ACK before the R entrypoint evaluates any scientific input.
The metadata owner and its authority are never widened or reused.
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
import re
import signal
import stat
import time

from . import startup_helper as h
from . import scientific_allocation as allocation
from . import profile_admission as admission
from . import numerical_stage_contract as c
from . import numerical_physical_admission as physical
from . import scientific_namespace_contract as namespace_contract

SOURCE_KIND = 'UNCHANGED_R157_TRACER_R182_FROZEN525_NUMERICAL_OWNER'
_UNREAPED_LOCK_FDS=[]


def sources():
    names=['numerical_stage_owner.py','numerical_stage_contract.py','numerical_stage_bootstrap.R',
           'startup_helper.py','scientific_allocation.py','profile_admission.py','environment.py',
           'numerical_physical_admission.py','scientific_namespace_contract.py']
    root=Path(__file__).absolute().parent
    return {name:h.pin(root/name) for name in names}


def validate_prerequisites(bundle,expected_node=None,expected_route_id=None):
    """Resolve copied metadata bytes without relabeling old logical pins."""
    h.require(bundle.get('status')=='PREPARED_ACTUAL_ACCEPTED_BOUNDARY_EVIDENCE_NOT_EXECUTION_AUTHORITY',
              'actual accepted evidence bundle required')
    aliases={}
    alias_sizes={}
    for row in bundle.get('artifacts',[]):
        original=c.strict_pin(row['logical']);actual=c.strict_pin(row.get('staged') or row['local'])
        h.require(original['sha256']==actual['sha256'] and original['path'] not in aliases,
                  'unique byte-identical logical proof aliases')
        h.require(type(row.get('bytes')) is int and 0<=row['bytes']<=32*1024**2,
                  'explicit bounded logical proof length')
        h.require(len(h.read_pin(actual,limit=32*1024**2))==row['bytes'],'actual copied proof byte length')
        aliases[original['path']]=actual
        alias_sizes[original['path']]=row['bytes']
    h.require(1<=len(aliases)<=128,'bounded complete metadata proof closure')
    def read(pin):
        c.strict_pin(pin);h.require(pin['path'] in aliases and aliases[pin['path']]['sha256']==pin['sha256'],
                                  'closed original proof pin required')
        return h.read(aliases[pin['path']])
    if expected_node is not None:
        h.require(bundle.get('qualification_node')==expected_node
                  and bundle.get('qualification_route_id')==expected_route_id,
                  'fresh boundary bundle must bind selected qualification node and route')
    accepted=bundle['accepted_boundary']
    h.require(accepted.get('status')=='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
              and accepted.get('role')=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'
              and accepted.get('namespace_proved') is True and accepted.get('scientific_boundary_proved') is True,
              'complete applicable outer accepted namespace and TSYNC record')
    guard=read(accepted['actual_accept_action_guard'])
    flags=['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter','orphan_subreaper',
           'guardian_included_in_CPU','inherited_waited_history_included_once']
    h.require(guard.get('returncode')==guard.get('command_returncode')==0 and guard.get('cap_reason') is None
              and guard.get('CPU_limit')==5 and 0<=guard.get('aggregate_CPU_seconds',float('inf'))<5
              and 0<=guard.get('complete_lifecycle_wall_seconds',float('inf'))<=180
              and guard.get('guardian_forced_monitor_stop') is False and all(guard.get(k) is True for k in flags),
              'actual successful outer guarded acceptance')
    candidate=h.strict_json(guard['stdout'])
    h.require(dict(candidate,status=accepted['status'],actual_accept_action_guard=accepted['actual_accept_action_guard'])==accepted,
              'accepted boundary must equal its actual guarded candidate')
    account=read(accepted['accounting']);peer=read(accepted['independent_review']);result=read(accepted['result'])
    h.require(account.get('terminal') is True and account.get('complete') is True
              and account.get('job_id')==accepted['job_id'] and account.get('primary_charge_counted_once') is True
              and account.get('canonical_primary_CPU_seconds')==accepted['canonical_primary_CPU_seconds'],
              'actual complete primary qualified accounting')
    h.require(peer.get('status')=='PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
              and peer.get('job_id')==accepted['job_id'] and peer.get('role')==accepted['role']
              and peer.get('result')==accepted['result'] and peer.get('accounting')==accepted['accounting']
              and peer.get('return_manifest')==accepted['full_return_manifest'],'actual independent complete boundary return')
    h.require(result.get('status')=='PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER'
              and result.get('job_id')==accepted['job_id'] and result.get('role')==accepted['role']
              and result.get('node')==(expected_node or 'node-13')
              and (expected_node is None or accepted.get('qualification_route_id')==result.get('qualification_route_id')==expected_route_id),'actual applicable complete boundary worker')
    outcome=result['outcome'];h.require(outcome.get('status')=='PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
                                     and outcome.get('original_guard_source_preserved') is True,'actual native boundary result')
    accepted_guard(read(outcome['owned_guard']))
    manifest=read(accepted['full_return_manifest'])
    h.require(manifest.get('job_id')==accepted['job_id'] and manifest.get('scope_id')==accepted['scope_id'],
              'qualified complete return identity')
    for row in manifest['files']:
        relative=Path(row['relative']);h.require(not relative.is_absolute() and '..' not in relative.parts,'safe exact qualified member')
        logical=str(Path(bundle['return_remote_root'])/relative)
        h.require(logical in aliases and aliases[logical]['sha256']==row['sha256'] and alias_sizes[logical]==row['bytes'],
                  'every complete-return member binds exact logical path, byte length and hash; duplicate bytes cannot substitute')
    inventory=read(bundle['inventory']);inventory_rows=[r for r in manifest['files'] if r['relative']=='INVENTORY.json']
    h.require(len(inventory_rows)==1 and bundle['inventory']['sha256']==inventory_rows[0]['sha256']
              and inventory.get('job_id')==accepted['job_id'] and inventory.get('node')==(expected_node or 'node-13')
              and (expected_node is None or inventory.get('qualification_route_id')==expected_route_id),
              'actual accepted scientific runtime inventory')
    installation=result.get('installation',{})
    h.require(installation.get('status')=='INSTALLED_CODE_BYTES_ONLY_NOT_NAMESPACE_OR_SCIENTIFIC_PROOF'
              and installation.get('files')==2279 and installation.get('bytes')==275498747
              and installation.get('job_id')==accepted['job_id'],'actual accepted code namespace install result')
    return dict(accepted=accepted,installation=installation,inventory=inventory)


def validate_runtime_reuse(reuse,prerequisite,expected_node=None,expected_route_id=None):
    qualified=validate_prerequisites(prerequisite,expected_node,expected_route_id);installation=qualified['installation']
    h.require(reuse.get('status')=='PREPARED_ACCEPTED_NAMESPACE_RUNTIME_REUSE_NOT_EXECUTION_AUTHORITY'
              and reuse.get('accepted_boundary')==qualified['accepted']
              and reuse.get('inventory')==qualified['inventory']
              and reuse.get('native_R')==dict(path=installation['R_HOME']+'/bin/exec/R',sha256=c.NATIVE_SHA),
              'byte/runtime context reuse derives from actual applicable accepted namespace')
    if expected_node is not None:
        h.require(reuse.get('qualification_node')==expected_node
                  and reuse.get('qualification_route_id')==expected_route_id,
                  'current runtime reuse must bind fresh selected-node qualification')
    expected=[];total=0;names=set()
    labels=['base_manifest.json','addon01_manifest.json','addon02_manifest.json']
    h.require(set(reuse.get('manifest_inputs',{}))==set(labels),'closed code-only manifest inputs')
    code_root=str(Path(installation['R_HOME']).parent)
    for label in labels:
        pin=reuse['manifest_inputs'][label]
        h.require(pin['sha256']==namespace_contract.INPUT_HASHES[label],'original exact code manifest identity')
        manifest=h.read(pin)
        for row in manifest['files']:
            relative=Path(row['relative'])
            h.require(not relative.is_absolute() and '..' not in relative.parts and str(relative) not in names,
                      'disjoint closed code runtime member')
            names.add(str(relative));total+=row['bytes'];expected.append(dict(path=code_root+'/'+str(relative),sha256=row['sha256']))
    h.require(len(expected)==2279 and total==275498747 and reuse.get('runtime_files')==expected,
              'runtime code read set is exactly the three original manifests, not arbitrary payloads')
    return qualified


def validate(spec_pin,authority_pin,review_pin,*,now=None,environ=None,affinity=None,node=None):
    now=time.time() if now is None else now;env=os.environ if environ is None else environ
    affinity=os.sched_getaffinity(0) if affinity is None else affinity
    node=os.uname().nodename.split('.')[0] if node is None else node
    spec,authority,review=(h.read(v) for v in [spec_pin,authority_pin,review_pin])
    h.require(spec.get('schema')=='r182_frozen525_numerical_owner_spec_v1'
              and spec.get('role') in c.ROLES,'separate supported numerical-purpose spec required')
    c.validate_role(spec['role'],spec['role_limits']);c.validate_delivery(spec['role'],spec['target_delivery'])
    h.require(env.get('SLURM_JOB_ID','').isdigit() and spec.get('job_id')==env['SLURM_JOB_ID']
              and spec.get('node')==env.get('SLURMD_NODENAME')==node
              and re.fullmatch(r'node-(?:1[5-9]|2[01])',node)
              and type(spec.get('qualification_route_id')) is str and re.fullmatch('[0-9a-f]{32}',spec['qualification_route_id'])
              and env.get('SLURM_CPUS_PER_TASK')=='1' and env.get('TZ')=='UTC'
              and len(affinity)==1 and spec.get('affinity')==sorted(affinity),
              'actual exact one-CPU Slurm compute placement required')
    h.require(authority.get('status')=='ROOT_ADMITTED_R182_FROZEN525_NUMERICAL_STAGE'
              and authority.get('spec')==spec_pin and authority.get('sources')==sources()
              and authority.get('role')==spec['role'] and authority.get('max_calls')==1
              and authority.get('memory_MiB')==8192 and authority.get('whole_CPU_seconds')==600
              and authority.get('whole_wall_seconds')==1200 and authority.get('owner_CPU_seconds')==450
              and authority.get('owner_wall_seconds')==300 and authority.get('R_child_CPU_seconds')==300,
              'new complete purpose-bound owner/root funding required')
    h.require(all(type(authority.get(k)) in (int,float) and math.isfinite(authority[k])
                  for k in ['issued_epoch','expires_epoch'])
              and authority['issued_epoch']<=now and now+300<authority['expires_epoch']<=spec['expires_epoch']
              and 0<authority['expires_epoch']-authority['issued_epoch']<=7200,
              'fresh bounded complete numerical lifecycle window')
    h.require(review.get('status')=='PASS_REVIEWED_R182_FROZEN525_NUMERICAL_OWNER_AND_SPEC'
              and review.get('spec')==spec_pin and review.get('authority')==authority_pin
              and review.get('sources')==sources() and review.get('role')==spec['role'],
              'independent numerical owner/spec/root review required')
    h.require(spec['traced_guard']['sha256']==c.TRACE_SHA
              and spec['boundary_library']['sha256']==c.BOUNDARY_SHA
              and spec['R_native']['sha256']==c.NATIVE_SHA
              and spec['bootstrap']==h.pin(Path(__file__).absolute().with_name('numerical_stage_bootstrap.R')),
              'unchanged original native tracer/boundary and exact new bootstrap required')
    for pin in [spec['traced_guard'],spec['boundary_library'],spec['R_native'],spec['bootstrap'],spec['bootstrap_spec']]:
        h.read_pin(pin,limit=64*1024**2)
    grant=h.read(spec['stage_grant']);c.validate_grant(spec,grant,now=now)
    source_review=h.read(grant['source_review'])
    h.require(source_review.get('status')=='PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'
              and all(source_review.get(k)==grant[k] for k in ['role','job_id','node','scope_id','execution_adapter_source','source_bindings'])
              and grant['execution_adapter_source']==h.pin(Path(__file__).absolute())
              and grant.get('source',{}).get('kind')=='R154_project_fullstate_consumer_pinned_CRAN111'
              and grant['source'].get('head')==spec.get('source_commit'),
              'independent current-role scientific source and published adapter identity')
    h.require(grant['scientific_boundary_qualification']==spec['boundary_qualification']
              and grant['execution_adapter_source']==spec['execution_adapter_source']
              and grant['entrypoint']==spec['entrypoint']
              and grant['source_bindings']==spec['scientific_source_bindings'],
              'R grant and compute owner must bind the same scientific source')
    h.require(set(spec['scientific_sources'])==set(c.SCIENCE_HASHES)
              and {name:pin['sha256'] for name,pin in spec['scientific_sources'].items()}==c.SCIENCE_HASHES,
              'closed unchanged mathematical consumers and authority-only ports')
    entry_name='application/tests/r179_hb_toy.R' if spec['role']=='TOY_PARITY' else 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R'
    h.require(spec['entrypoint']==spec['scientific_sources'][entry_name]
              and all(pin in spec['scientific_source_bindings'] for pin in spec['scientific_sources'].values()),
              'exact role-specific immutable mathematical entrypoint')
    for pin in spec['scientific_source_bindings']:h.read_pin(pin,limit=16*1024**2)
    h.require(spec['entrypoint'] in spec['scientific_source_bindings'], 'exact pinned scientific entrypoint')
    bundle=h.read(spec['prerequisite_bundle']);validate_prerequisites(bundle,spec['node'],spec['qualification_route_id'])
    h.require(spec['accepted_boundary']==bundle['accepted_boundary'],'exact imported accepted boundary record')
    gate=h.read(spec['boundary_qualification']);oldguard=h.read(gate['owned_guard'])
    h.require(gate.get('status')=='PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
              and gate.get('original_guard_source_preserved') is True,
              'applicable actual namespace and TSYNC qualification required')
    accepted_guard(oldguard)
    h.require(spec['accepted_boundary'].get('status')=='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
              and spec['accepted_boundary'].get('scientific_boundary_proved') is True
              and spec['accepted_boundary'].get('role')=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER',
              'outer accepted boundary record required, not a worker PASS')
    runtime=h.read(grant['actual_R_runtime_binding'])
    h.require(runtime['actual_executable']==spec['R_native']['path']
              and runtime['actual_executable_sha256']==spec['R_native']['sha256'],
              'actual exact scientific R runtime binding required')
    bootstrap=h.read(spec['bootstrap_spec'])
    h.require(bootstrap.get('schema')=='r182_hb_numerical_bootstrap_v1'
              and all(bootstrap.get(k)==spec[k] for k in ['role','job_id','node','nonce'])
              and bootstrap.get('scientific_entrypoint')==spec['entrypoint']
              and bootstrap.get('boundary_library')==spec['boundary_library']
              and bootstrap.get('expected_stock_body_sha256')==c.STOCK_BODY_SHA
              and bootstrap.get('source_parse_files')==c.ordered_science_pins(spec['scientific_sources']),
              'exact current-run numerical bootstrap/entrypoint boundary')
    expected_args=[spec['science_root'],spec['stage_grant']['path'],spec['stage_grant']['sha256'],spec['output']+'/toy']
    if spec['role']=='ZERO_UPDATE_BRIDGE':
        expected_args=['bridge',spec['science_root'],spec['execution_manifest']['path'],spec['stage_grant']['path'],
                       spec['stage_grant']['sha256'],spec['output']+'/bridge']
    h.require(bootstrap.get('entrypoint_args')==expected_args,'closed original toy/bridge argument contract; no pilot')
    childenv=spec['environment'];required=set(h.ENV_KEYS)|{'R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED',
        'R154_PROJECT_ROOT_ADMITTED','R154_PROJECT_MODE','R154_PROJECT_ADMISSION_PATH',
        'R154_PROJECT_ADMISSION_SHA256','R154_PROJECT_RUNTIME_PATH','R154_PROJECT_RUNTIME_SHA256'}
    h.require(set(childenv)==required and all(childenv.get(k)=='1' for k in h.THREAD_KEYS)
              and childenv.get('SLURM_JOB_ID')==spec['job_id']
              and childenv.get('SLURMD_NODENAME')==node and childenv.get('SLURM_CPUS_PER_TASK')=='1'
              and childenv.get('TZ')=='UTC' and childenv.get('PATH')=='/usr/bin:/bin',
              'closed single-thread scientific child environment required')
    h.require(childenv['R154_PROJECT_MODE']==('toy' if spec['role']=='TOY_PARITY' else 'bridge')
              and childenv['R154_PROJECT_ROOT_ADMITTED']==('0' if spec['role']=='TOY_PARITY' else '1')
              and childenv['R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED']==('1' if spec['role']=='TOY_PARITY' else '0'),
              'environment cannot enable pilot or another role')
    rhome=str(Path(spec['R_native']['path']).parents[2]);library=rhome+'/library';root=spec['remote_namespace']
    closed=dict(PATH='/usr/bin:/bin',LANG='C',LC_ALL='C',TZ='UTC',HOME=root,TMPDIR=root+'/tmp',R_HOME=rhome,R_ARCH='',
        R_DOC_DIR=rhome+'/doc',R_INCLUDE_DIR=rhome+'/include',R_SHARE_DIR=rhome+'/share',R_LIBS_USER=library,R_LIBS_SITE=library,
        LD_LIBRARY_PATH=rhome+'/lib:'+str(Path(rhome).parent/'lib'),SLURM_JOB_ID=spec['job_id'],SLURMD_NODENAME=node,SLURM_CPUS_PER_TASK='1',
        R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED='1' if spec['role']=='TOY_PARITY' else '0',
        R154_PROJECT_ROOT_ADMITTED='0' if spec['role']=='TOY_PARITY' else '1',R154_PROJECT_MODE='toy' if spec['role']=='TOY_PARITY' else 'bridge',
        R154_PROJECT_ADMISSION_PATH=spec['stage_grant']['path'],R154_PROJECT_ADMISSION_SHA256=spec['stage_grant']['sha256'],
        R154_PROJECT_RUNTIME_PATH=grant['actual_R_runtime_binding']['path'],R154_PROJECT_RUNTIME_SHA256=grant['actual_R_runtime_binding']['sha256'])
    closed.update({key:'1' for key in h.THREAD_KEYS})
    h.require(childenv==closed and bootstrap['library']==library,'closed actual R library/loader/job/scientific environment')
    h.require(spec['output']==spec['remote_namespace']+'/result/numerical'
              and spec['resource_lock']==spec['remote_namespace']+'/numerical.lock',
              'new exact private scientific output and resource lock')
    snapshot=h.read(spec['physical_snapshot']);proof=h.read(spec['physical_core_proof']);physical_review=h.read(spec['physical_core_review'])
    h.require(proof.get('actual_snapshot')==physical_review.get('actual_snapshot')==spec['physical_snapshot'],
              'root and independent physical review must bind this exact current READY snapshot')
    h.require(snapshot['filesystem']['path']==spec['remote_namespace'],'current numerical namespace filesystem must be observed')
    physical.validate(snapshot,proof,physical_review,job_id=spec['job_id'],node=node,affinity=spec['affinity'],now=now)
    return spec,authority


def accepted_guard(guard):
    flags=['reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution',
           'tracer_death_kernel_EXITKILL_enabled','postbootstrap_TSYNC_scientific_fork_denial','scientific_target_access_handshake']
    att=guard.get('scientific_filter_kernel_attestation') or {}
    h.require(guard.get('schema')=='r157_traced_bootstrap_guard_receipt_v1'
              and guard.get('status')=='EXITED' and guard.get('returncode')==0
              and all(guard.get(k) is True for k in flags)
              and guard.get('remaining_owned_lifetimes')==[]
              and guard.get('unexpected_untraced_child_waits')==[]
              and att.get('operation')=='SECCOMP_SET_MODE_FILTER' and att.get('flags')=='TSYNC'
              and att.get('kernel_return')==0,'actual complete current-run kernel TSYNC/ACK/ownership/drain proof')
    return True


def parse_gate(spec,raw,phase,state):
    h.require(phase=='SCIENTIFIC_FORK_DENIED' and state.get('state')=='LIVE'
              and state.get('kernel_trace_owned') is True and state.get('scientific_filter_accepted') is True,
              'kernel-attested original tracer pre-ACK transition required')
    h.require(len(raw)<=1024**2,'bounded pre-ACK scientific parse output')
    frames=[h.strict_json(line) for line in raw.splitlines() if line.lstrip().startswith(b'{')]
    h.require(len(frames)==1 and frames[0].get('status')=='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT'
              and all(frames[0].get(k)==spec[k] for k in ['role','job_id','node','nonce'])
              and frames[0].get('source_files')==c.ordered_science_pins(spec['scientific_sources'])
              and frames[0].get('optimizer_invocations')==0 and frames[0].get('scientific_target_data_read') is False,
              'owner must independently validate exact five-source parse before ACK permits evaluation')
    return frames[0]


def validate_core(role,core,grant,grant_pin,output,verify_bytes=None):
    verify_bytes=(lambda pin:h.read_pin(pin,limit=c.MAX_RETURN_FILE)) if verify_bytes is None else verify_bytes
    if role=='TOY_PARITY':
        h.require(core.get('status')=='NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF'
                  and core.get('schema')=='r154_project_adapter_validation_core_v1'
                  and core.get('root_grant_pin')==grant_pin and core.get('source')==grant['source']
                  and core.get('actual_R_runtime_binding')==grant['actual_R_runtime_binding'], 'actual exact toy core')
        flags=['toy_default_and_import_parity_pass','checkpoint_all_factors_schedules_RNG_IO_verified',
               'stock_AST_exactly_preserved','no_production_data_used','production_gate_unchanged_and_rejects_synthetic']
        h.require(all(core.get(k) is True for k in flags)
                  and core.get('toy_optimizer_invocations')==8 and core.get('total_toy_optimizer_iterations')==30
                  and core.get('maximum_n')==128 and core.get('maximum_p')==32
                  and core.get('production_fit_invocations')==core.get('production_passflags_written')==0,
                  'exact full-state, AST, 8-call/30-iteration synthetic proof')
        groups=core.get('checkpoints',[])
        h.require([g.get('count') for g in groups]==[4,4,1,4], 'exact thirteen checkpoint inventory')
        for group in groups:
            h.require(group.get('label','').startswith('synthetic_NONCANDIDATE_')
                      and [x.get('completed_sweep') for x in group['entries']]==list(range(1,group['count']+1)),
                      'exact contiguous synthetic checkpoint history')
            for entry in group['entries']:
                pin=entry['state_pin'];path=h.physical(pin['path'])
                h.require(path.is_relative_to(output) and path.suffix=='.rds', 'exact private synthetic checkpoint')
                verify_bytes(pin)
        h.require(core.get('stock_body_sha256')==c.STOCK_BODY_SHA,'exact stock mathematical body')
    else:
        h.require(core.get('schema')=='r154_conditional_state_bridge_v1'
                  and core.get('status')=='VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE'
                  and core.get('target_name')==c.TARGET and core.get('optimizer_updates')==0
                  and core.get('source')==grant['source'] and core.get('production_acceptance_authority') is False
                  and core.get('exact_optimizer_resume') is False, 'exact zero-update NO3 bridge core')
        flags=['full_state_factors_verified','explicit_factor_elbo_verified','original_seven_certificate_computed',
               'rhs_unit_and_dispersed_verified','source_recipe_reproduced']
        h.require(all(core.get(k) is True for k in flags) and core.get('original_failed_state_modified') is False,
                  'full state/objective/original seven gate/both starts proof')
        for key in ['factor_state','baseline_certificate_pin']:
            pin=core[key];h.require(h.physical(pin['path']).is_relative_to(output),'private exact bridge output')
            verify_bytes(pin)
    return True


def run(spec_pin,authority_pin,review_pin,ready_identity):
    started=time.monotonic();spec,authority=validate(spec_pin,authority_pin,review_pin)
    scheduler=allocation.live(spec['job_id'],spec['node'],spec['affinity'],minimum_remaining=300)
    root=h.physical(spec['remote_namespace']);out=h.physical(spec['output'])
    h.require(root.stat().st_uid==os.getuid() and root.stat().st_mode&0o022==0 and not out.exists(),
              'new private owned job output required')
    out.mkdir(mode=0o700)
    if spec['role']=='ZERO_UPDATE_BRIDGE':(out/'bridge').mkdir(mode=0o700)
    current_physical=physical.capture(spec['job_id'],spec['node'],spec['known_prior_jobs'],disk_root=root)
    initial_physical=h.read(spec['physical_snapshot'])
    h.require(current_physical['topology']==initial_physical['topology']
              and current_physical['Slurm_core_policy']==initial_physical['Slurm_core_policy']
              and current_physical['job_cpuset']==initial_physical['job_cpuset']
              and current_physical['online_thread_siblings']==initial_physical['online_thread_siblings']
              and current_physical['filesystem']['path']==spec['remote_namespace'],
              'current exact physical allocation policy/topology changed before scientific launch')
    h.write_new(out/'PHYSICAL_BEFORE_R.json',current_physical)
    fd=os.open(spec['resource_lock'],os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
    h.write_new(out/'INTENT.json',dict(status='STARTED_NUMERICAL_STAGE_NOT_PASS',spec=spec_pin,
        authority=authority_pin,review=review_pin,sources=sources(),role=spec['role']))
    module=importlib.util.spec_from_file_location('r182_unchanged_r157',spec['traced_guard']['path'])
    trace=importlib.util.module_from_spec(module);module.loader.exec_module(trace)
    def peer(owned):
        allocation.exact_cgroup(Path('/proc/self/cgroup').read_text(),spec['job_id'],os.getuid())
        h.require(os.sched_getaffinity(0)==set(spec['affinity'])
                  and 0<admission.cgroup_memory_limit()<=8192*1024**2,'current scientific CPU/memory boundary')
        h.require(physical.topology(spec['affinity'][0])==h.read(spec['physical_core_proof'])['topology'],
                  'current physical core/SMT topology changed')
        h.require(physical.job_cpuset(spec['job_id'])==initial_physical['job_cpuset'],
                  'current kernel job-core allocation changed')
        online=sorted(set(physical.topology(spec['affinity'][0])['thread_siblings'])&set(physical.cpu_list(Path('/sys/devices/system/cpu/online').read_text())))
        h.require(online==initial_physical['online_thread_siblings']
                  and online==initial_physical['job_cpuset']['effective_cpus'],
                  'online SMT sibling ownership changed')
        for prior in owned:
            current=trace.identity(prior['pid'])
            h.require(trace.same_lifetime(current,prior) and current['TracerPid']==os.getpid()
                      and current['affinity']==spec['affinity'],'current exact ptrace owner and CPU')
        return dict(job_id=spec['job_id'],affinity=spec['affinity'],owned_lifetimes=len(owned))
    env=dict(spec['environment'],R154_GLOBAL_PERMIT_LOCK_FD=str(fd))
    command=[spec['R_native']['path'],'--no-echo','--no-restore','--no-save','--no-environ','--no-site-file','--no-init-file',
             '--file='+spec['bootstrap']['path'],'--args',spec['bootstrap_spec']['path'],spec['bootstrap_spec']['sha256'],spec['nonce']]
    safe=False;parent_parse=None
    try:
        for path,sha in spec['bootstrap_exec_allowlist'].items():h.read_pin(dict(path=path,sha256=sha),limit=64*1024**2)
        def child_limits():
            resource.setrlimit(resource.RLIMIT_CPU,(300,300))
            resource.setrlimit(resource.RLIMIT_FSIZE,(c.MAX_RETURN_FILE,c.MAX_RETURN_FILE))
        with (out/'child.stdout').open('xb') as stdout,(out/'child.stderr').open('xb') as stderr:
            def capture(lock_fd,phase,state):
                nonlocal parent_parse
                if phase=='SCIENTIFIC_FORK_DENIED' and state.get('state')=='LIVE' and parent_parse is None:
                    parent_parse=parse_gate(spec,(out/'child.stdout').read_bytes(),phase,state)
                    filesystem=physical.filesystem_facts(root)
                    h.write_new(out/'PARSE_PARENT_GATE.json',dict(status='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK',
                        role=spec['role'],job_id=spec['job_id'],node=spec['node'],scope_id=spec['scope_id'],
                        frame=parent_parse,authority=authority_pin,original_tracer_pre_ACK_capture_callback=True,
                        kernel_ACK_still_requires_original_guard_completion=True,filesystem_before_ACK=filesystem))
            receipt=trace.run_traced(command,env=env,stdout=stdout,stderr=stderr,lock_fd=fd,
                affinity=spec['affinity'],wall_seconds=300,maximum_combined_CPU_seconds=450,
                absolute_deadline_UTC=dt.datetime.fromtimestamp(min(authority['expires_epoch'],scheduler['end_epoch']),dt.timezone.utc).isoformat(),
                peer_callback=peer,bootstrap_exec_allowlist=spec['bootstrap_exec_allowlist'],owner_path=out/'owned_tree.json',
                scope=spec['scope_id'],source=dict(kind=SOURCE_KIND),authority_pin=authority_pin,
                preexec_fn=child_limits,require_science_handshake=True,owner_capture_callback=capture)
        h.write_new(out/'owned_guard.json',receipt)
        safe=receipt.get('reaped') is True and receipt.get('drained') is True and receipt.get('remaining_owned_lifetimes')==[]
        accepted_guard(receipt);tree=h.read(h.pin(out/'owned_tree.json'))
        stdout=(out/'child.stdout').read_bytes();h.require(len(stdout)<=1024**2,'bounded scientific stdout')
        frames=[h.strict_json(line) for line in stdout.splitlines() if line.lstrip().startswith(b'{')]
        h.require(parent_parse is not None and len(frames)==1 and frames[0]==parent_parse
                  and frames[0].get('status')=='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT'
                  and all(frames[0].get(k)==spec[k] for k in ['role','job_id','node','nonce'])
                  and frames[0].get('source_files')==c.ordered_science_pins(spec['scientific_sources'])
                  and frames[0].get('optimizer_invocations')==0 and frames[0].get('scientific_target_data_read') is False,
                  'actual current-kernel-ACK parse frame before numerical entrypoint')
        h.require(tree.get('state')=='CLOSED' and tree.get('scope')==spec['scope_id']
                  and tree.get('authority_pin')==authority_pin and tree.get('source')==dict(kind=SOURCE_KIND),
                  'current exact numerical scope/root/tracer source')
        for actual in [receipt['supervisor'],tree['supervisor']]:
            h.require(all(actual.get(k)==ready_identity[k] for k in ['pid','start_ticks','boot_id','affinity']),
                      'the current READY worker must own every tracee')
        corepath=out/('toy/validation_core.json' if spec['role']=='TOY_PARITY' else 'bridge/bridge_validation.json')
        core=h.read(h.pin(corepath));grant=h.read(spec['stage_grant'])
        validate_core(spec['role'],core,grant,spec['stage_grant'],out)
        h.require(time.time()<authority['expires_epoch'] and time.monotonic()-started<300,
                  'complete numerical owner window')
        result=dict(status=('PASS_HB_FROZEN525_SYNTHETIC_TOY' if spec['role']=='TOY_PARITY' else 'PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE'),
            role=spec['role'],spec=spec_pin,authority=authority_pin,review=review_pin,core=h.pin(corepath),
            owned_guard=h.pin(out/'owned_guard.json'),owned_tree=h.pin(out/'owned_tree.json'),job_id=spec['job_id'],node=spec['node'],
            current_TSYNC_and_parent_ACK=True,production_fits=0,production_admission=False,pilot_fits=0,
            source_parse_pass_before_numerical_entrypoint=frames[0],
            owner_validated_parse_before_kernel_ACK=h.pin(out/'PARSE_PARENT_GATE.json'),
            canonical_Slurm_accounting_and_peer_return_still_required=True)
        h.write_new(out/'RESULT.json',result);return result
    except BaseException as error:
        h.write_new(out/'FAILED.json',dict(status='FAILED_NUMERICAL_STAGE_FEES_RETAINED_NO_RETRY',error=type(error).__name__+': '+str(error)))
        raise
    finally:
        if safe:os.close(fd)
        else:_UNREAPED_LOCK_FDS.append(fd)
