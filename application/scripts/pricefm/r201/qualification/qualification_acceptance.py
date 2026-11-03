"""Metadata-only final native/reference qualifier. Cannot manufacture compute evidence."""
import hashlib,importlib.util,json,os,resource,time,argparse
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
_CP=ROOT/'qualification/qualification_contract.py'
_raw=_CP.read_bytes()
if any(x.is_symlink() for x in (_CP,*_CP.parents)) or hashlib.sha256(_raw).hexdigest()!='39a53e52b4c1ebafe076d59b8e509e94f1b5a02706ef1710637654aa0a74ec75':
    raise ValueError('exact closed qualification contract before import')
_sp=importlib.util.spec_from_file_location('_r201_qualification_accept_contract',_CP)
c=importlib.util.module_from_spec(_sp);exec(compile(_raw,str(_CP),'exec'),c.__dict__)
m=c.m
ABI_CASES={'preparation_outside_trace_refused','pre_ack_live_refused','wrong_lifetime_refused',
 'wrong_permit_refused','late_or_repeated_transition_refused','real_TSYNC_ACK',
 'live_identity_permit_rechecks','noreplace_collision_refused','bounded_payload_proof_storage','complete_reap_drain'}
def _suite(pin,spec,launch):
    suite=m.linked(pin)
    m.require(suite.get('schema')=='r201_actual_native_ABI_suite_v1'
      and suite.get('status')=='ACCEPTED_NATIVE_ABI_SUITE_NOT_PRODUCTION'
      and suite.get('source_map_sha256')==spec['source_map_sha256']
      and suite.get('native_library')==launch['native_library']
      and suite.get('native_abi')==launch['native_abi'] and suite.get('node')==spec['node'],
      'actual complete applicable ABI suite, source tests cannot substitute')
    m.require(type(suite.get('cases')) is dict and set(suite['cases'])==ABI_CASES
      and all(type(v) is bool and v is True for v in suite['cases'].values()),'all required actual native cases')
    review=m.linked(suite['independent_review']);core=dict(suite);core.pop('independent_review')
    m.require(review.get('status')=='PASS_REVIEWED_R201_NATIVE_ABI_SUITE'
      and review.get('suite_core_sha256')==m.digest(core),'acyclic independent native suite review')
    accounting=m.linked(suite['accounting'])
    m.require(accounting.get('terminal') is True and accounting.get('complete') is True
      and accounting.get('primary_charge_counted_once') is True,'actual complete ABI stage accounting')
    m.require(type(suite.get('owned_guards')) is list and len(suite['owned_guards'])>=1,'actual traced ABI subjects')
    for p in suite['owned_guards']:
        g=m.linked(p)
        m.require(g.get('schema')=='r157_traced_bootstrap_guard_receipt_v1'
          and g.get('returncode')==0 and all(g.get(k) is True for k in ('reaped','drained','CPU_accounting_complete',
          'all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled'))
          and g.get('remaining_owned_lifetimes')==[],'actual fully owned fixed ABI test subjects')
    return suite
def candidate(request_pin,result_output):
    m.require(os.sched_getaffinity(0)=={31} and resource.getrlimit(resource.RLIMIT_CPU)==(5,5)
      and os.getpid()==os.getsid(0)==os.getpgrp(),'actual new administrative H5 acceptance context')
    st=dict(x.split(':',1) for x in Path('/proc/self/status').read_text().splitlines() if ':' in x)
    m.require(st.get('NoNewPrivs','').strip()=='1' and st.get('Seccomp','').strip()=='2','actual kernel H guard')
    r=m.linked(request_pin)
    m.closed(r,{'schema','spec','owner_candidate','return_finalization','native_abi_suite','accounting','independent_review'},'qualification acceptance request')
    m.require(r['schema']=='r201_native_reference_acceptance_request_v1','closed actual acceptance request')
    spec=m.linked(r['spec']);c.inspect_spec_metadata(spec);c.quote_and_funding(spec);launch=m.linked(spec['owner_launch'])
    m.require(spec['issued_epoch']<=time.time()<spec['expires_epoch'],'whole qualification/acceptance interval current')
    m.physical(result_output)
    owner=m.linked(r['owner_candidate'])
    m.require(owner.get('status')=='R201_REFERENCE_RETURN_CANDIDATE_AWAIT_COMPLETE_INDEPENDENT_ACCEPTANCE'
      and owner.get('role')==c.ROLE and owner.get('spec')==r['spec']
      and owner.get('job_id')==spec['job_id'] and owner.get('node')==spec['node'],'actual initial owner, not production')
    g=m.linked(owner['owned_guard'])
    flags=('reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution',
      'tracer_death_kernel_EXITKILL_enabled','postbootstrap_TSYNC_scientific_fork_denial','scientific_target_access_handshake')
    att=g.get('scientific_filter_kernel_attestation') or {}
    m.require(g.get('schema')=='r157_traced_bootstrap_guard_receipt_v1' and g.get('status')=='EXITED'
      and g.get('returncode')==0 and all(g.get(k) is True for k in flags)
      and g.get('remaining_owned_lifetimes')==[] and g.get('unexpected_untraced_child_waits')==[]
      and att.get('operation')=='SECCOMP_SET_MODE_FILTER' and att.get('flags')=='TSYNC'
      and att.get('kernel_return')==0,'actual complete real native kernel handshake')
    final=m.linked(r['return_finalization']);accounting=m.linked(r['accounting'])
    m.require(final.get('schema')=='r201_reference_return_finalization_v1'
      and final.get('status')=='VERIFIED_EXACT_R201_REFERENCE_RETURN_INVENTORY'
      and final.get('spec')==r['spec'] and final.get('owner_candidate')==r['owner_candidate']
      and final.get('accounting')==r['accounting'] and final.get('complete') is True
      and final.get('all_required_proofs_returned') is True
      and accounting.get('job_id')==spec['job_id'] and accounting.get('terminal') is True
      and accounting.get('complete') is True and accounting.get('primary_charge_counted_once') is True,
      'complete returned inventory and actual accounting')
    summary_pin=final.get('qualification_summary');summary=m.linked(summary_pin)
    m.require(summary.get('schema')=='r200_analytic_reference_result_v1'
      and summary.get('status')=='COMPUTE_ANALYTIC_COMPONENT_FIXTURES_PASSED_NOT_TARGET_ACCEPTANCE'
      and summary.get('cases')==9 and type(summary.get('cases')) is int
      and summary.get('precision_evaluations')==27 and type(summary.get('precision_evaluations')) is int
      and summary.get('optimizer_updates')==0 and type(summary.get('optimizer_updates')) is int
      and summary.get('new_posterior_fits')==0 and type(summary.get('new_posterior_fits')) is int
      and summary.get('role')==c.ROLE and summary.get('job_id')==spec['job_id']
      and summary.get('source_map_sha256')==spec['source_map_sha256']
      and summary.get('native_ACK_and_live_identity_verified') is True
      and summary.get('production_admission') is False and summary.get('scientific_acceptance') is False,
      'actual complete analytic component evidence, no full target or production transfer')
    _suite(r['native_abi_suite'],spec,launch)
    result=dict(summary,native_abi_suite=r['native_abi_suite'],owner_candidate=r['owner_candidate'],
      actual_owned_guard=owner['owned_guard'],return_finalization=r['return_finalization'],
      startup_python=launch['native_executable'],native_build_acceptance=spec['build_acceptance'],
      native_deployment_acceptance=spec['deployment_acceptance'],qualified_role='LT_NO4_REFERENCE',
      fullsize_price_earned=False,original_target_export_earned=False,full_scientific_error_budget_earned=False)
    # Caller supplies this exact prospective path in the already-reviewed request's review.
    review=m.linked(r['independent_review'])
    m.require(review.get('status')=='PASS_REVIEWED_R200_RUNTIME_QUALIFICATION'
      and review.get('acceptance_request_core_sha256')==m.digest({k:v for k,v in r.items() if k!='independent_review'})
      and review.get('accounting')==r['accounting'],'independent complete runtime qualification review')
    # Canonical result identity avoids any review<->request/result pin cycle.
    raw=(json.dumps(result,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
    actual_pin={'path':str(m.absolute(result_output)),'sha256':hashlib.sha256(raw).hexdigest()}
    m.require(review.get('result')==actual_pin,'independent review pins exact prepared result bytes')
    with m.absolute(result_output).open('xb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
    return dict(schema='r200_actual_runtime_qualification_v1',
      status='CANDIDATE_R201_NATIVE_REFERENCE_QUALIFICATION_AWAIT_H5',
      source_map_sha256=spec['source_map_sha256'],role='LT_NO4_REFERENCE',node=spec['node'],job_id=spec['job_id'],
      all_required_build_ABI_boundary_tests_passed=True,result=actual_pin,
      independent_review=r['independent_review'],accounting=r['accounting'],
      native_abi_suite=r['native_abi_suite'],no_production_price_target_export_or_scientific_error_transfer=True,
      command_pid=os.getpid(),command_birth_ticks=int(Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19]))
def finalize(candidate_pin,actual_guard_pin,output):
    v=m.linked(candidate_pin);g=m.linked(actual_guard_pin);c.guard(g,5)
    m.require(m.strict_json(g['stdout'])==v and v.get('schema')=='r200_actual_runtime_qualification_v1'
      and v.get('status')=='CANDIDATE_R201_NATIVE_REFERENCE_QUALIFICATION_AWAIT_H5'
      and v.get('role')=='LT_NO4_REFERENCE' and g['session_id']==v.get('command_pid')
      and g['leader_start_ticks']==v.get('command_birth_ticks'),'actual new H5 qualifier candidate/PID/birth, never source preparation')
    accepted=dict(v,status='ACCEPTED_QUALIFIED_R200_RUNTIME',actual_accept_guard=actual_guard_pin)
    return m.write_new(output,accepted)

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('phase',choices=['candidate','finalize'])
    for name in ('request','request-sha256','result-output','candidate','candidate-sha256','guard','guard-sha256','output'):
        ap.add_argument('--'+name)
    a=ap.parse_args()
    if a.phase=='candidate':
        m.require(all(x is not None for x in (a.request,a.request_sha256,a.result_output)),'candidate arguments')
        value=candidate(dict(path=a.request,sha256=a.request_sha256),a.result_output)
    else:
        m.require(all(x is not None for x in (a.candidate,a.candidate_sha256,a.guard,a.guard_sha256,a.output)),'finalize arguments')
        value=finalize(dict(path=a.candidate,sha256=a.candidate_sha256),dict(path=a.guard,sha256=a.guard_sha256),a.output)
    print(json.dumps(value,sort_keys=True,allow_nan=False))
if __name__=='__main__':main()
