"""Root metadata issuer/finalizer; source preparation never earns native evidence.

Operational candidates run only in a new original H5. Pure finalizers require
the exact healthy guard/stdout/PID/birth and independent review. All files are
create-only. No compiler, FFI, targets, Slurm submission or polling exists here.
"""
import hashlib,importlib.util,json,os,re,sys,time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
P=ROOT/'peer/independent_peer.py'
_PEER_SHA='b2f124fd3d10d4cd28a255b32fa4ba0ddfe57204a0cf8d673892083dec3dccd7'
def _peer():
    # Source interpretation is gated by the frozen independent source review in
    # the CLI manifest; native owner code never imports this administrative file.
    raw=P.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=_PEER_SHA:raise ValueError('authenticated independent peer before interpretation')
    sp=importlib.util.spec_from_file_location('_r203_root_independent_peer',P)
    x=importlib.util.module_from_spec(sp);exec(compile(raw,str(P),'exec'),x.__dict__)
    return x
e=_peer();m=e.m
def birth():
    return int(Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19])
def _same_input_manifest(manifest):
    m.closed(manifest,{'schema','status','administrative_grant','source_publication','source_review','issuer_source','peer_source','operation','inputs','output_root'},'closed Root operator manifest')
    m.require(manifest['schema']=='r203_root_metadata_operator_manifest_v1'
      and manifest['status']=='ROOT_AUTHORIZED_R203_ONE_METADATA_OPERATION','one explicit Root metadata operation')
    m.require(manifest['issuer_source']==m.pin_file(__file__) and manifest['peer_source']==m.pin_file(P),'exact issuer and peer source')
    pub=m.linked(manifest['source_publication']);review=m.linked(manifest['source_review'])
    m.require(pub.get('schema')=='r203_control_source_publication_v1' and pub.get('status')=='PASS_PUBLISHED_R203_CONTROL_SOURCE_PREPARATION'
      and pub.get('commit')==pub.get('remote_readback') and pub.get('runtime_admitted') is False
      and pub['files']['peer/issuer_finalize.py']==manifest['issuer_source']['sha256']
      and pub['files']['peer/independent_peer.py']==manifest['peer_source']['sha256']
      and review.get('status')=='PASS_REVIEWED_R203_CONTROL_SOURCE_PREPARATION_ONLY'
      and {k:v['sha256'] for k,v in review['source_pins'].items()}==pub['files'],'published exact independently reviewed control code, no qualification transfer')
    return manifest
def _put(root,name,value):return m.write_new(root/name,value)
def _core(value,exclude):return {k:v for k,v in value.items() if k not in exclude}
def attach_review(core_pin,review_pin,kind,output):
    value=m.linked(core_pin);review=m.linked(review_pin)
    fields={'QUOTE':('quote_core_sha256','PASS_REVIEWED_R203_CONTROL_STAGE_QUOTE'),
      'BASELINE':('baseline_core_sha256','PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN'),
      'PROFILE':('profile_core_sha256','PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE'),'CLEAN_LAUNCH':('clean_launch_core_sha256','PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER')}
    m.require(kind in fields,'closed static plan kind');key,status=fields[kind]
    m.require('independent_review' not in value and review.get('status')==status
      and review.get(key)==m.digest(value),'acyclic actual independent static review')
    value['independent_review']=review_pin;return m.write_new(output,value)
def promote(candidate_pin,guard_pin,candidate_status,accepted_status,output):
    m.require((candidate_status,accepted_status) in {('CANDIDATE_R203_CONTROL_STAGE_ADMISSION_AWAIT_H5','ADMITTED_R203_ONE_DIRECT_SLURM_STAGE'),('CANDIDATE_SOURCE_BUILD_ONLY_AWAIT_H5','ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME'),('CANDIDATE_R203_FACILITY_ROUTE_AWAIT_H5','ACCEPTED_R203_SAME_PATH_FACILITY_ROUTE_NOT_DEPLOYMENT'),('CANDIDATE_READONLY_NAMESPACE_ONLY_AWAIT_H5','ACCEPTED_READONLY_NAMESPACE_ONLY_NOT_RUNTIME')},'only three closed acceptance promotions')
    candidate=m.linked(candidate_pin);guard=m.linked(guard_pin);e._guard_value(guard,candidate,5)
    m.require(candidate['status']==candidate_status and 'actual_accept_guard' not in candidate,'exact one actual H5 candidate')
    accepted=dict(candidate,status=accepted_status,actual_accept_guard=guard_pin)
    return m.write_new(output,accepted)
def admission_candidate(preview_pin,core_pin,review_pin,output):
    e.admin_before_records(5);t,q=e.prospective(preview_pin);core=m.linked(core_pin);review=m.linked(review_pin)
    m.require(review['status']=='PASS_REVIEWED_R203_CONTROL_STAGE_ADMISSION'
      and review['admission_core_sha256']==m.digest(_core(core,{'issued_epoch','status'})),'independent logical admission review before actual candidate')
    a=dict(core,status='CANDIDATE_R203_CONTROL_STAGE_ADMISSION_AWAIT_H5',independent_review=review_pin,
      issued_epoch=time.time(),command_pid=os.getpid(),command_birth_ticks=birth())
    e.admission_evidence(a,t,q);_put(Path(output).parent,Path(output).name,a);return a
def assemble_template(preview_pin,admission_pin,proofs,output_root):
    t,q=e.prospective(preview_pin);t['admission']=admission_pin
    e.validate_admission(t,q,True)
    root=m.physical(output_root);root.mkdir(mode=0o700)
    m.require(type(proofs) is list and len(proofs)<=512,'explicit schema-required prejob closure')
    # All required entries must already exist byte-identically on this main
    # server. Installation copies these exact bytes to original canonical paths.
    for p in proofs:m.linked(p)
    now=time.time();core=dict(t);core.pop('bootstrap_authority')
    boot=dict(schema='r203_control_metadata_bootstrap_authority_v1',status='ROOT_AUTHORIZED_R203_METADATA_STARTUP_ONLY',
      template_core_sha256=m.digest(core),**{k:t[k] for k in ('purpose','nonce','stage','node','control_publication','control_map_sha256',
        'runtime_publication','runtime_map_sha256','scope','ledger','quote','admission','output_root')},
      parameters_sha256=m.digest(t['parameters']),maximum_jobs=1,maximum_owner_calls=1,optimizer_invocations=0,
      scientific_target_data_read=False,issued_epoch=now,expires_epoch=t['expires_epoch'],canonical_input_proofs=proofs)
    bp=_put(root,'BOOTSTRAP.json',boot);t['bootstrap_authority']=bp
    template_pin=_put(root,'TEMPLATE.json',t)
    # Producer preflight uses the actual owner metadata reader to prove the
    # supplied canonical closure is complete. It creates no owner context.
    cp=ROOT/'common/contract.py';source=m.read_regular(cp,limit=1024**2,expected_sha='3090fb684b3c8796bc7754b036b5b4c3a1f92a92051f1ccc700e5d3d657900a7')
    spec=importlib.util.spec_from_file_location('_r203_root_producer_metadata_preflight',cp);common=importlib.util.module_from_spec(spec);exec(compile(source,str(cp),'exec'),common.__dict__)
    common.inspect_template_metadata(t,check_current=True)
    e.template(template_pin)
    return template_pin
def request_from_ready(template_pin,capture_pair_pin,output):
    t,q=e.template(template_pin);pair=m.linked(capture_pair_pin);o=e._pair_capture(pair,t,'SOURCE_PHYSICAL')
    # The initial capture request can be job-bound with template and actual READY,
    # before a postREADY request exists. No prejob future PID is invented.
    ready_pin=next(v for v in [dict(path=row['remote_path'],sha256=row['sha256']) for row in o['records']] if Path(v['path']).name=='ready.json')
    ready=e.resolve(ready_pin,o);now=time.time()
    m.require(ready['status']=='READY_R203_METADATA_ONLY_AWAIT_TWO_PEERS_AND_ROOT_RELEASE'
      and ready['template']==template_pin and ready['created_epoch']<=now<ready['expires_epoch']<=ready['created_epoch']+120,'actual original READY120')
    r=dict(schema='r203_control_stage_request_v1',template=template_pin,
      **{k:ready[k] for k in ('purpose','nonce','stage','job_id','node','uid','affinity','owner','root','permit_fd','permit_path',
        'source_capture','physical_witness','scope','ledger','quote','control_map_sha256','runtime_map_sha256')},
      ready=ready_pin,issued_epoch=now,expires_epoch=t['expires_epoch'])
    e._same(ready,t,('purpose','nonce','stage','node','control_map_sha256','runtime_map_sha256','scope','ledger','quote'))
    m.require(ready['job_id']==o['job_id'],'actual discovery allocation identity')
    e._job_observation(o,r)
    return m.write_new(output,r)
def release(request_pin,source_pin,owner_pin,proofs,output_root):
    r,t,q=e.request(request_pin);s=m.linked(source_pin);o=m.linked(owner_pin)
    e._same(s,r);e._same(o,r)
    now=time.time();ready_deadline=min(s['expires_epoch'],o['expires_epoch'])
    m.require(s['status']=='PASS_REVIEWED_R203_ACTUAL_SOURCE_PHYSICAL' and o['status']=='PASS_REVIEWED_R203_ACTUAL_OWNER_RELEASE'
      and s['request']==o['request']==request_pin and o['source_review']==source_pin
      and max(s['issued_epoch'],o['issued_epoch'])<=now<ready_deadline,'both real independent peers live at Root release')
    for record in (s,o):e.program(record['independent_program'],t)
    # Both actual native captures are checked again; first payload must still
    # enter before these original short leases. Later subjects never renew them.
    first=e.observation(s['observation'],r,t,'SOURCE_PHYSICAL',request_pin);second=e.observation(o['observation'],r,t,'OWNER_READY',request_pin)
    ready=e.resolve(r['ready'],second);e._job_observation(second,r)
    m.require(now<ready['expires_epoch'],'original READY still live')
    full_deadline=min(t['expires_epoch'],ready['owner_started_epoch']+q['owner_wall_seconds'])
    a=dict(schema='r203_control_stage_authority_v1',status='ROOT_ADMITTED_R203_ONE_CONTROL_STAGE',
      request=request_pin,source_review=source_pin,owner_review=owner_pin,
      **{k:r[k] for k in ('purpose','nonce','stage','job_id','node','uid','owner','root','permit_fd')},
      parameters_sha256=m.digest(t['parameters']),
      **{k:t[k] for k in ('control_publication','control_map_sha256','runtime_publication','runtime_map_sha256','scope','ledger','quote','admission')},
      maximum_owner_calls=1,maximum_traced_subjects=9 if r['stage']=='NATIVE_ABI_SUITE' else 1,
      optimizer_invocations=0,new_posterior_fits=0,scientific_target_data_read=False,issued_epoch=now,expires_epoch=full_deadline)
    root=m.physical(output_root);root.mkdir(mode=0o700);ap=_put(root,'authority.json',a)
    m.require(type(proofs) is list and len(proofs)<=512,'explicit postREADY proof closure')
    proofs=list(proofs)+[pin for pin in (request_pin,source_pin,owner_pin,ap,r['ready'],r['source_capture'],r['physical_witness']) if pin not in proofs]
    for phase in (s,o):
        for pin in phase['observation'].values():
            if pin not in proofs:proofs.append(pin)
    for pin in proofs:
        rows=[row for capture in (first,second) for row in capture['records'] if row['remote_path']==pin['path']]
        if rows:m.linked(rows[-1]['local_copy'])
        else:m.linked(pin)
    rel=dict(schema='r203_control_stage_root_release_v1',status='ROOT_RELEASED_R203_ONE_OWNED_CONTROL_STAGE',
      template=r['template'],ready=r['ready'],request=request_pin,source_review=source_pin,owner_review=owner_pin,
      authority=ap,issued_epoch=now,expires_epoch=min(ready_deadline,ready['expires_epoch']),canonical_input_proofs=proofs)
    return dict(authority=ap,release=_put(root,'RELEASE.json',rel),marker_created=False,
      install_required='Exact full canonical closure and six records; native fsync then zero-length RELEASE.ready last')
def terminal_accounting(raw_pin,capture_pair_pin,output):
    raw=m.linked(raw_pin);r,t,q=e.request(raw['request'],False);pair=m.linked(capture_pair_pin)
    o=e._pair_capture(pair,t,'TERMINAL',r);reply=e._native_rows(o,'accounting')
    rows=[v for v in reply['stdout'].splitlines() if v.strip()];m.require(len(rows)==1,'one native terminal allocation')
    f=rows[0].split('|')
    if f[-1]=='':f.pop()
    m.require(len(f)==14,'closed actual native terminal fields')
    value=dict(schema='r203_actual_terminal_control_stage_accounting_v1',status='CAPTURED_TERMINAL_R203_PRIMARY_STAGE_ACCOUNTING',
      job_id=r['job_id'],terminal=True,complete=True,primary_charge_counted_once=True,native_capture=pair,
      raw_stage_result=raw_pin,owner_whole_CPU_seconds=raw['usage']['inclusive_CPU_seconds'],
      whole_CPU_seconds=max(e._slurm_CPU(f[-1]),raw['usage']['inclusive_CPU_seconds']),whole_wall_seconds=int(f[6]),observed_epoch=time.time())
    pin=m.write_new(output,value);e._terminal(pin,r,t,q);return pin
def build_result(raw_pin,accounting_pin,raw_review_pin,output_root):
    raw,r,t,q,a,o,facts=e._build_facts(raw_pin,accounting_pin);review=m.linked(raw_review_pin)
    m.require(review['status']=='PASS_REVIEWED_R203_RAW_OWNED_NATIVE_BUILD'
      and review['raw_stage_result']==raw_pin and review['accounting']==accounting_pin,'actual independent raw build review')
    p=t['parameters']['stage'];root=m.physical(output_root);root.mkdir(mode=0o700)
    manifest=dict(schema='r201_native_build_manifest_v1',status='BUILD_EVIDENCE_ONLY_NOT_RUNTIME_QUALIFIED',
      source=p['source'],header=p['header'],abi=p['abi'],compiler=p['compiler'],argv=facts['compiler_argv'],
      output_library=facts['output_library'],dependencies=facts['dependencies'],build_guard=facts['build_guard'],
      build_accounting=accounting_pin,build_source_review=raw_review_pin,created_epoch=time.time())
    mp=_put(root,'NATIVE_BUILD_MANIFEST.json',manifest)
    v=dict(schema='r203_compatible_owned_native_build_result_v1',status='BOUND_BUILD_EVIDENCE_AWAIT_INDEPENDENT_REVIEW_H5',
      source_map_sha256=t['runtime_map_sha256'],job_id=r['job_id'],node=r['node'],raw_stage_result=raw_pin,
      native_build_manifest=mp,native_library=facts['output_library'],native_abi=p['abi'],accounting=accounting_pin,
      optimizer_invocations=0,scientific_target_data_read=False,control_source_publication=t['control_publication'],control_map_sha256=t['control_map_sha256'])
    return _put(root,'BOUND_BUILD_RESULT.json',v)
def deployment_result(raw_pin,accounting_pin,output_root):
    raw,r,t,q,a,o,facts=e.readonly_facts(raw_pin,accounting_pin);root=m.physical(output_root);root.mkdir(mode=0o700)
    ns=dict(schema='r203_actual_canonical_namespace_witness_v1',status='QUALIFIED_CANONICAL_METADATA_NAMESPACE',
      source_publication=t['runtime_publication'],same_bytes_without_old_JSON_rewrite=True,
      canonical_metadata_files=facts['canonical_metadata_files'],readonly_files=facts['readonly_files'],
      raw_stage_result=raw_pin,accounting=accounting_pin,node=r['node'])
    np=_put(root,'CANONICAL_NAMESPACE.json',ns)
    v=dict(schema='r203_compatible_readonly_namespace_result_v1',status='BOUND_NAMESPACE_EVIDENCE_AWAIT_INDEPENDENT_REVIEW_H5',
      source_map_sha256=t['runtime_map_sha256'],job_id=r['job_id'],node=r['node'],raw_stage_result=raw_pin,
      canonical_metadata_namespace=np,read_only_backing_verified=True,build_acceptance=facts['build_acceptance'],
      baseline_files=facts['baseline_files'],namespace_witnesses=[np],native_library=facts['native_library'],
      native_build_manifest=facts['native_build_manifest'],native_abi=facts['native_abi'],accounting=accounting_pin,
      optimizer_invocations=0,scientific_target_data_read=False,control_source_publication=t['control_publication'],control_map_sha256=t['control_map_sha256'])
    return _put(root,'BOUND_NAMESPACE_RESULT.json',v)

def facility_result(raw_pin,accounting_pin,output):
    raw,r,t,q,a,o,facts=e.facility_facts(raw_pin,accounting_pin)
    v=dict(schema='r203_compatible_facility_route_result_v1',status='BOUND_FACILITY_ROUTE_AWAIT_INDEPENDENT_REVIEW_H5',
      source_map_sha256=t['runtime_map_sha256'],job_id=r['job_id'],node=r['node'],raw_stage_result=raw_pin,
      same_path_facility_route_observed=True,canonical_output_library=facts['canonical_output_library'],
      accounting=accounting_pin,optimizer_invocations=0,scientific_target_data_read=False,
      control_source_publication=t['control_publication'],control_map_sha256=t['control_map_sha256'])
    return m.write_new(output,v)

def compatible_candidate(kind,result_pin,review_pin,accounting_pin,output):
    e.admin_before_records(5);v=m.linked(result_pin);review=m.linked(review_pin)
    status={'BUILD':'PASS_REVIEWED_R201_NATIVE_BUILD','DEPLOYMENT':'PASS_REVIEWED_R201_READONLY_NAMESPACE','FACILITY':'PASS_REVIEWED_R203_SAME_PATH_FACILITY_ROUTE'}
    m.require(kind in status and review['status']==status[kind] and review['result']==result_pin
      and review['accounting']==accounting_pin==v['accounting'],'actual independent compatible result review')
    # Reconstruct facts again; caller cannot provide a PASS boolean.
    if kind=='BUILD':e._build_facts(v['raw_stage_result'],accounting_pin)
    elif kind=='FACILITY':e.facility_facts(v['raw_stage_result'],accounting_pin)
    else:e.readonly_facts(v['raw_stage_result'],accounting_pin)
    fields=('native_build_manifest','native_library','native_abi') if kind=='BUILD' else () if kind=='FACILITY' else ('build_acceptance','baseline_files','namespace_witnesses')
    candidate=dict(schema='r201_owned_native_build_acceptance_v1' if kind=='BUILD' else 'r203_same_path_facility_acceptance_v1' if kind=='FACILITY' else 'r201_readonly_namespace_acceptance_v1',
      status='CANDIDATE_SOURCE_BUILD_ONLY_AWAIT_H5' if kind=='BUILD' else 'CANDIDATE_R203_FACILITY_ROUTE_AWAIT_H5' if kind=='FACILITY' else 'CANDIDATE_READONLY_NAMESPACE_ONLY_AWAIT_H5',
      source_map_sha256=v['source_map_sha256'],**{k:v[k] for k in fields},
      result=result_pin,independent_review=review_pin,accounting=accounting_pin,created_epoch=time.time(),
      command_pid=os.getpid(),command_birth_ticks=birth())
    m.write_new(output,candidate);return candidate
def abi_candidate(raw_pin,accounting_pin,output):
    e.admin_before_records(5);e.reconstruct_ABI(raw_pin,accounting_pin)
    v=dict(schema='r203_native_ABI_candidate_v1',status='CANDIDATE_R203_NATIVE_ABI_SUITE_AWAIT_H5',
      raw_stage_result=raw_pin,accounting=accounting_pin,command_pid=os.getpid(),command_birth_ticks=birth())
    m.write_new(output,v);return v
def abi_core(candidate_pin,guard_pin,output):
    c=m.linked(candidate_pin);g=m.linked(guard_pin);e._guard_value(g,c,5)
    m.require(c['status']=='CANDIDATE_R203_NATIVE_ABI_SUITE_AWAIT_H5','real native ABI candidate')
    core=e.reconstruct_ABI(c['raw_stage_result'],c['accounting']);core['status']='ACCEPTED_NATIVE_ABI_SUITE_NOT_PRODUCTION'
    core.update(actual_suite_accept_guard=guard_pin,command_pid=c['command_pid'],command_birth_ticks=c['command_birth_ticks'])
    return m.write_new(output,core)
def abi_finalize(core_pin,review_pin,output):
    core=m.linked(core_pin);review=m.linked(review_pin)
    m.require(review['status']=='PASS_REVIEWED_R201_NATIVE_ABI_SUITE' and review['suite_core_sha256']==m.digest(core),'actual independent full suite core review')
    return m.write_new(output,dict(core,independent_review=review_pin))
def main():
    e.admin_before_records(5)
    m.require(len(sys.argv)==3,'exact operator manifest path and SHA')
    manifest=_same_input_manifest(m.linked(dict(path=sys.argv[1],sha256=sys.argv[2])))
    op=manifest['operation'];args=manifest['inputs']
    admin=e._administrative_module();grant_operation=op+('_'+args['kind'] if 'kind' in args else '')
    if op=='PROMOTE':grant_operation+='_'+{'ADMITTED_R203_ONE_DIRECT_SLURM_STAGE':'ADMISSION','ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME':'BUILD','ACCEPTED_READONLY_NAMESPACE_ONLY_NOT_RUNTIME':'DEPLOYMENT','ACCEPTED_R203_SAME_PATH_FACILITY_ROUTE_NOT_DEPLOYMENT':'FACILITY'}.get(args.get('accepted_status'),'INVALID')
    g,root=admin.grant(manifest['administrative_grant'],'ISSUE_'+grant_operation,m.pin_file(__file__),5)
    m.require(str(root)==manifest['output_root'],'fixed delegated metadata namespace')
    m.require(root.parent==Path('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa')
      and re.fullmatch('R203_[A-Za-z0-9_]{1,120}',root.name),'new private Root metadata operation')
    root.mkdir(mode=0o700);m.write_new(root/'INTENT.json',dict(operation=op,manifest=m.pin_file(sys.argv[1]),started_epoch=time.time()))
    operations={'ATTACH_REVIEW':attach_review,'ADMISSION_CANDIDATE':admission_candidate,'ASSEMBLE_TEMPLATE':assemble_template,
      'REQUEST_FROM_READY':request_from_ready,'ROOT_RELEASE':release,'TERMINAL_ACCOUNTING':terminal_accounting,
      'FACILITY_RESULT':facility_result,'BUILD_RESULT':build_result,'DEPLOYMENT_RESULT':deployment_result,'COMPATIBLE_CANDIDATE':compatible_candidate,
      'ABI_CANDIDATE':abi_candidate,'ABI_CORE':abi_core,'ABI_FINALIZE':abi_finalize,'PROMOTE':promote}
    m.require(op in operations and type(args) is dict,'closed metadata operator')
    # Output paths are fixed by this operation's new private root; input cannot
    # redirect publication, overwrite historical files or touch a target.
    import inspect
    fn=operations[op];parameters=inspect.signature(fn).parameters
    output_name='output_root' if 'output_root' in parameters else 'output'
    m.require(set(args)==set(parameters)-{output_name},'exact typed operation arguments; no injected output/callback')
    result=fn(**args,**{output_name:str(root/'result') if output_name=='output_root' else str(root/'RESULT.json')})
    if op in {'ADMISSION_CANDIDATE','COMPATIBLE_CANDIDATE','ABI_CANDIDATE'}:print(json.dumps(result,sort_keys=True))
    else:print(json.dumps(dict(status='COMPLETED_ONE_R203_METADATA_OPERATION_NOT_SCIENTIFIC_ACCEPTANCE',operation=op,result=result,
      command_pid=os.getpid(),command_birth_ticks=birth()),sort_keys=True))
if __name__=='__main__':main()
