CFG=__import__("json").loads('{"build_acceptance": {"actual_guard_CPU": 5, "actual_guard_stdout_PID_birth_binding_required": true, "candidate_status": "CANDIDATE_SOURCE_BUILD_ONLY_AWAIT_H5", "independent_review_status": "PASS_REVIEWED_R201_NATIVE_BUILD", "keys": ["schema", "status", "source_map_sha256", "native_build_manifest", "native_library", "native_abi", "result", "independent_review", "accounting", "actual_accept_guard", "created_epoch", "command_pid", "command_birth_ticks"], "schema": "r201_owned_native_build_acceptance_v1", "status": "ACCEPTED_SOURCE_BUILD_ONLY_NOT_RUNTIME"}, "deployment_acceptance": {"actual_guard_CPU": 5, "actual_guard_stdout_PID_birth_binding_required": true, "candidate_status": "CANDIDATE_READONLY_NAMESPACE_ONLY_AWAIT_H5", "current_actual_RO_mount_and_superblock_recheck_every_launch": true, "independent_review_status": "PASS_REVIEWED_R201_READONLY_NAMESPACE", "keys": ["schema", "status", "source_map_sha256", "build_acceptance", "baseline_files", "namespace_witnesses", "result", "independent_review", "accounting", "actual_accept_guard", "created_epoch", "command_pid", "command_birth_ticks"], "schema": "r201_readonly_namespace_acceptance_v1", "status": "ACCEPTED_READONLY_NAMESPACE_ONLY_NOT_RUNTIME"}, "initial_authority": {"keys": ["schema", "status", "spec", "purpose", "nonce", "role", "job_id", "node", "case_sha256", "source_map_sha256", "source_review", "owner_review", "source_publication", "scope", "ledger", "quote", "build_acceptance", "deployment_acceptance", "issued_epoch", "expires_epoch", "maximum_calls", "optimizer_invocations", "new_posterior_fits"], "maximum_calls": 1, "new_posterior_fits": 0, "optimizer_invocations": 0, "schema": "r201_qualification_authority_v1", "status": "ROOT_ADMITTED_R201_INITIAL_NATIVE_REFERENCE_QUALIFICATION"}, "initial_spec": {"case": {"families": ["diagonal", "rank_one", "paired_ill_conditioned"], "new_posterior_fits": 0, "optimizer_updates": 0, "schema": "r200_analytic_reference_fixture_request_v1", "sizes": [8, 16, 32]}, "keys": ["schema", "purpose", "nonce", "role", "job_id", "node", "uid", "affinity", "root", "owner", "case", "case_sha256", "source_map_sha256", "source_publication", "source_pins", "owner_launch", "scope", "ledger", "quote", "build_acceptance", "deployment_acceptance", "acknowledgement_path", "resource_lock_fd", "resource_lock_path", "attempt_claim_path", "issued_epoch", "expires_epoch"], "no_target_or_input_manifest": true, "schema": "r201_native_reference_qualification_spec_v1"}, "launch": {"keys": ["schema", "purpose", "nonce", "role", "job_id", "node", "bootstrap", "native_executable", "native_library", "native_build_manifest", "native_abi", "native_build_acceptance", "native_deployment_acceptance", "traced_guard", "baseline_files", "environment", "bootstrap_exec_allowlist", "stdout_path", "stderr_path", "owned_tree_path", "owned_guard_path", "output_root"], "schema": "r201_owned_reference_launch_v1"}, "prospective_quote": {"all_disjoint_compute_admin_remote_channels_required": true, "component_names": ["startup", "namespace", "import", "optimizer", "certification", "checkpoint", "return", "independent_peer", "closure"], "independent_review_status": "PASS_REVIEWED_R201_PROSPECTIVE_QUALIFICATION_QUOTE", "keys": ["schema", "status", "purpose", "nonce", "role", "source_publication", "source_map_sha256", "case_sha256", "components", "whole_CPU_seconds", "whole_wall_seconds", "compute_CPU_reservation", "administrative_CPU_reservation", "remote_unknown_CPU_reservation", "owner_CPU_seconds", "child_CPU_seconds", "owner_wall_seconds", "memory_MiB", "reserved_filesystem_bytes", "mandatory_headroom_bytes", "return_proof_reservation_bytes", "proof_storage_reservation_bytes", "independent_review"], "measurement_not_yet_earned": true, "minimum_proof_storage_reservation_bytes": 67108864, "minimum_return_proof_reservation_bytes": 16777216, "no_production_price_transfer": true, "optimizer_component_compute_CPU": 0, "schema": "r201_prospective_qualification_quote_v1", "status": "REVIEWED_PROSPECTIVE_R201_QUALIFICATION_QUOTE"}}')
"""Closed initial-only qualification metadata. No descriptor admits compute."""
import hashlib, importlib.util, json, os, re, time
from pathlib import Path
_MP=Path(__file__).absolute().parent.parent/'owner/metadata.py'
_RAW=_MP.read_bytes()
if hashlib.sha256(_RAW).hexdigest()!='6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':
    raise ValueError('exact unchanged metadata source')
_SP=importlib.util.spec_from_file_location('_r201_qualification_metadata',_MP)
m=importlib.util.module_from_spec(_SP);exec(compile(_RAW,str(_MP),'exec'),m.__dict__)
ROLE='INITIAL_NATIVE_REFERENCE_QUALIFICATION'
SPEC_KEYS=set(CFG['initial_spec']['keys'])
AUTHORITY_KEYS=set(CFG['initial_authority']['keys'])
LAUNCH_KEYS=set(CFG['launch']['keys'])
CASE=CFG['initial_spec']['case']
COMPONENTS=set(CFG['prospective_quote']['component_names'])
MAX_RETURN=64*1024**2
def exact(a,b,label):
    m.require(type(a) is type(b),label+' exact type')
    if type(b) is dict:
        m.closed(a,b,label)
        for k in b:exact(a[k],b[k],label+'.'+k)
    elif type(b) is list:
        m.require(len(a)==len(b),label+' length')
        for i,(x,y) in enumerate(zip(a,b)):exact(x,y,label+str(i))
    else:m.require(a==b,label+' fixed value')
def same(v,s):
    for k in ('purpose','nonce','role','job_id','node'):
        m.require(v.get(k)==s[k],'same current '+k)
def inspect_spec_metadata(s):
    m.closed(s,SPEC_KEYS,'initial qualification spec')
    m.require(s['schema']=='r201_native_reference_qualification_spec_v1'
      and s['role']==ROLE and re.fullmatch('[0-9a-f]{32}',s['nonce'] or '')
      and type(s['purpose']) is str and 1<=len(s['purpose'])<=128,'initial-only role/nonce')
    exact(s['case'],CASE,'fixed synthetic case')
    m.require(s['case_sha256']==m.digest(CASE),'fixed synthetic case digest')
    m.integer(s['uid'],'UID')
    m.require(type(s['job_id']) is str and re.fullmatch('[1-9][0-9]{0,11}',s['job_id'])
      and type(s['node']) is str and re.fullmatch('node-[0-9]{2}',s['node']),'actual-shaped job/node')
    m.require(type(s['affinity']) is list and len(s['affinity'])==1,'one CPU')
    m.integer(s['affinity'][0],'CPU',0)
    m.closed(s['owner'],{'pid','start_ticks','boot_id'},'owner')
    m.integer(s['owner']['pid'],'owner PID',1);m.integer(s['owner']['start_ticks'],'owner birth',1)
    m.require(type(s['owner']['boot_id']) is str and re.fullmatch('[0-9a-f-]{36}',s['owner']['boot_id']),'boot id')
    for k in ('source_publication','owner_launch','scope','ledger','quote','build_acceptance','deployment_acceptance'):
        m.descriptor(s[k])
    m.require(type(s['source_pins']) is dict and 1<=len(s['source_pins'])<=128,'source closure')
    for name,pin in s['source_pins'].items():
        m.require(type(name) is str and not Path(name).is_absolute() and '..' not in Path(name).parts,'source name')
        m.descriptor(pin)
    m.require(m.digest({k:v['sha256'] for k,v in s['source_pins'].items()})==s['source_map_sha256'],'source digest')
    root=m.absolute(s['root']);m.integer(s['resource_lock_fd'],'permit fd',3,2**20)
    m.absolute(s['resource_lock_path'])
    for k in ('acknowledgement_path','attempt_claim_path'):
        m.require(m.absolute(s[k]).is_relative_to(root),'private '+k)
    for k in ('issued_epoch','expires_epoch'):m.finite(s[k],k)
    m.require(0<s['expires_epoch']-s['issued_epoch']<=28800,'fixed <=8h source-independent runtime interval')
    return dict(status='CONSISTENT_INITIAL_QUALIFICATION_DESCRIPTOR_ONLY',runtime_admitted=False,
                can_release=False,can_optimize=False)
def inspect_quote_metadata(q):
    m.closed(q,CFG['prospective_quote']['keys'],'prospective initial quote')
    m.require(q['schema']=='r201_prospective_qualification_quote_v1'
      and q['status']=='REVIEWED_PROSPECTIVE_R201_QUALIFICATION_QUOTE' and q['role']==ROLE,'separate prospective quote')
    m.descriptor(q['source_publication']);m.descriptor(q['independent_review'])
    m.closed(q['components'],COMPONENTS,'all nine quote components')
    channels=('compute_CPU_upper_seconds','administrative_CPU_upper_seconds','remote_unknown_CPU_reservation')
    for name,c in q['components'].items():
        m.require(type(c) is dict and c.get('covered') is True,'covered '+name)
        for k in ('CPU_upper_seconds','wall_upper_seconds',*channels):m.integer(c.get(k),k,0)
        m.require(c['CPU_upper_seconds']==sum(c[k] for k in channels),'disjoint channels')
    m.require(q['components']['optimizer']['compute_CPU_upper_seconds']==0,'no optimizer in qualification')
    for k in ('whole_CPU_seconds','whole_wall_seconds','compute_CPU_reservation','administrative_CPU_reservation',
              'owner_CPU_seconds','child_CPU_seconds','owner_wall_seconds','memory_MiB',
              'reserved_filesystem_bytes','mandatory_headroom_bytes','return_proof_reservation_bytes',
              'proof_storage_reservation_bytes'):m.integer(q[k],k,1)
    m.integer(q['remote_unknown_CPU_reservation'],'remote fee',0)
    for channel,total in zip(channels,('compute_CPU_reservation','administrative_CPU_reservation','remote_unknown_CPU_reservation')):
        m.require(sum(c[channel] for c in q['components'].values())<=q[total],'full distinct '+total)
    m.require(q['whole_CPU_seconds']>=q['compute_CPU_reservation']+q['administrative_CPU_reservation']+q['remote_unknown_CPU_reservation']
      and sum(c['wall_upper_seconds'] for c in q['components'].values())<=q['whole_wall_seconds']
      and q['child_CPU_seconds']<=q['owner_CPU_seconds']<=q['compute_CPU_reservation']
      and q['owner_wall_seconds']<=q['whole_wall_seconds']<=28800
      and q['components']['startup']['wall_upper_seconds']>=120,'inclusive finite whole quote withREADY120')
    m.require(16*1024**2<=q['return_proof_reservation_bytes']<MAX_RETURN
      and q['proof_storage_reservation_bytes']>=64*1024**2
      and q['reserved_filesystem_bytes']>=MAX_RETURN+q['proof_storage_reservation_bytes'],
      'complete return and retained proof storage are separately reserved')
    return dict(status='CONSISTENT_PROSPECTIVE_QUOTE_ONLY',runtime_admitted=False,measurement_earned=False)
def guard(g,cpu):
    m.require(type(g.get('returncode')) is int and type(g.get('command_returncode')) is int
      and g['returncode']==g['command_returncode']==0 and type(g.get('CPU_limit')) is int
      and g['CPU_limit']==cpu and g.get('cap_reason') is None
      and g.get('guardian_forced_monitor_stop') is False,'healthy whole actual H guard')
    for k in ('aggregate_CPU_seconds','complete_lifecycle_wall_seconds'):m.finite(g.get(k),k)
    m.require(0<=g['aggregate_CPU_seconds']<cpu and 0<=g['complete_lifecycle_wall_seconds']<=180
      and all(g.get(k) is True for k in ('all_owned_descendants_reaped','independent_guardian',
      'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once')),
      'actual complete H lifecycle')
def accepted_record(pin,kind,source_map):
    v=m.linked(pin);policy=CFG[kind];m.closed(v,policy['keys'],kind)
    m.require(v['schema']==policy['schema'] and v['status']==policy['status']
      and v['source_map_sha256']==source_map,'applicable '+kind)
    g=m.linked(v['actual_accept_guard']);guard(g,5)
    candidate=m.strict_json(g['stdout']);expected=dict(candidate,status=policy['status'],actual_accept_guard=v['actual_accept_guard'])
    m.require(expected==v and candidate.get('status')==policy['candidate_status']
      and g['session_id']==v['command_pid'] and g['leader_start_ticks']==v['command_birth_ticks'],
      'actual H5 stdout/PID/birth, no source fixture')
    result=m.linked(v['result']);review=m.linked(v['independent_review']);account=m.linked(v['accounting'])
    m.require(result.get('source_map_sha256')==source_map and review.get('status')==policy['independent_review_status']
      and review.get('result')==v['result'] and review.get('accounting')==v['accounting']
      and account.get('terminal') is True and account.get('complete') is True
      and account.get('primary_charge_counted_once') is True
      and result.get('job_id')==account.get('job_id'),'independent owned stage/accounting')
    m.require(type(result.get('optimizer_invocations')) is int and result['optimizer_invocations']==0
      and result.get('scientific_target_data_read') is False,'source-only stage did not read targets or optimize')
    return v,result
def validate_native_prerequisites(spec,launch,review):
    """Metadata-only. Actual RO/ELF checks remain required in parent and child."""
    m.closed(launch,LAUNCH_KEYS,'closed r201 launch');same(launch,spec)
    m.require(launch['schema']=='r201_owned_reference_launch_v1','new reference launch')
    m.require(review.get('source_pins')==spec['source_pins']
      and review.get('source_map_sha256')==spec['source_map_sha256'],'same reviewed source closure')
    pub=m.linked(spec['source_publication'])
    m.require(pub.get('schema')=='r200_source_publication_v1'
      and pub.get('status')=='PASS_PUBLISHED_R200_SOURCE_PREPARATION'
      and pub.get('commit')==pub.get('remote_readback')
      and pub.get('files')=={k:v['sha256'] for k,v in spec['source_pins'].items()},
      'actual published exact source, no old runtime transfer')
    for k in ('native_library','native_build_manifest','native_abi','native_build_acceptance','native_deployment_acceptance'):
        m.descriptor(launch[k])
    build,br=accepted_record(launch['native_build_acceptance'],'build_acceptance',spec['source_map_sha256'])
    m.require(all(build[k]==launch[k] for k in ('native_library','native_build_manifest','native_abi'))
      and br.get('native_build_manifest')==launch['native_build_manifest']
      and br.get('native_library')==launch['native_library'],'same owned build artifact and ABI')
    deploy,dr=accepted_record(launch['native_deployment_acceptance'],'deployment_acceptance',spec['source_map_sha256'])
    m.require(deploy['build_acceptance']==launch['native_build_acceptance']
      and deploy['baseline_files']==launch['baseline_files']
      and type(deploy['namespace_witnesses']) is list and len(deploy['namespace_witnesses'])>=1
      and dr.get('node')==spec['node'] and dr.get('read_only_backing_verified') is True,
      'accepted deployment is not current mount proof')
    for pin in deploy['namespace_witnesses']:m.linked(pin)
    namespace=m.linked(dr['canonical_metadata_namespace'])
    m.require(namespace.get('status')=='QUALIFIED_CANONICAL_METADATA_NAMESPACE'
      and namespace.get('source_publication')==spec['source_publication']
      and namespace.get('same_bytes_without_old_JSON_rewrite') is True,'actual canonical metadata baseline qualification')
    if spec['role']==ROLE:
        m.require(spec['build_acceptance']==launch['native_build_acceptance']
          and spec['deployment_acceptance']==launch['native_deployment_acceptance'],'same initial stage prerequisites')
    else:
        m.require(spec['role']=='LT_NO4_REFERENCE','two closed Python roles')
        qual=m.linked(spec['runtime_qualification']);qr=m.linked(qual['result'])
        m.require(qr.get('native_build_acceptance')==launch['native_build_acceptance']
          and qr.get('native_deployment_acceptance')==launch['native_deployment_acceptance'],
          'production uses the actual qualified build/deployment')
def runtime_scope_clock_metadata(scope,context,now=None):
    """Fund before context issuance; the whole original runtime window stays finite."""
    now=time.time() if now is None else now
    for value,label in ((scope.get('issued_epoch'),'scope issuance'),
                        (scope.get('expires_epoch'),'scope expiry'),
                        (context.get('issued_epoch'),'context issuance'),(now,'current clock')):
        m.finite(value,label)
    m.require(scope['issued_epoch']<=context['issued_epoch']<=now<scope['expires_epoch'],
      'funded runtime scope precedes context and is currently live')
    return dict(status='CONSISTENT_RUNTIME_SCOPE_CLOCK_METADATA_ONLY',runtime_admitted=False)
def quote_and_funding(spec):
    q=m.linked(spec['quote']);inspect_quote_metadata(q)
    for k in ('purpose','nonce','role','source_publication','source_map_sha256','case_sha256'):
        m.require(q[k]==spec[k],'quote binds '+k)
    core=dict(q);core.pop('independent_review');review=m.linked(q['independent_review'])
    m.require(review.get('status')=='PASS_REVIEWED_R201_PROSPECTIVE_QUALIFICATION_QUOTE'
      and review.get('quote_core_sha256')==m.digest(core),'acyclic independently reviewed prospective quote')
    scope=m.linked(spec['scope']);ledger=m.linked(spec['ledger'])
    runtime_scope_clock_metadata(scope,spec)
    m.require(scope.get('schema')=='r201_initial_reference_qualification_runtime_scope_v1'
      and scope.get('status')=='ROOT_FUNDED_INITIAL_REFERENCE_QUALIFICATION_ONLY','source448 never qualifies')
    for k in ('purpose','nonce','role','quote','source_publication','source_map_sha256','expires_epoch'):
        m.require(scope.get(k)==spec[k],'runtime scope binds '+k)
    m.require(scope.get('remote_namespace')==spec['root'] and scope.get('target_input_manifest') is None
      and type(scope.get('maximum_jobs')) is int and scope['maximum_jobs']==1
      and scope.get('automatic_retry') is False and scope.get('requeue') is False
      and type(scope.get('optimizer_invocations')) is int and scope['optimizer_invocations']==0
      and type(scope.get('new_posterior_fits')) is int and scope['new_posterior_fits']==0,'synthetic-only one funded job')
    m.require(type(scope.get('compute_CPU_reservation')) is int
      and scope['compute_CPU_reservation']==q['compute_CPU_reservation']
      and type(scope.get('new_administrative_CPU_reservation')) is int
      and scope['new_administrative_CPU_reservation']>=q['administrative_CPU_reservation']+q['remote_unknown_CPU_reservation'],
      'full prospective compute/admin/remote funds')
    rows=[r for r in ledger.get('scopes',[]) if r.get('scope')==spec['scope']]
    roles=[r for r in ledger.get('compute_roles',[]) if r.get('scope')==spec['scope']]
    m.require(len(rows)==len(roles)==1
      and rows[0].get('administrative_CPU_reservation')==scope['new_administrative_CPU_reservation']
      and rows[0].get('compute_CPU_reservation')==roles[0].get('compute_CPU_reservation')==q['compute_CPU_reservation'],
      'one current primary charge and full administrative fee')
    return q

def validate_bootstrap_metadata(context,launch_template,source_pins):
    """Job-independent metadata gate before spending a Slurm startup. Grants nothing."""
    m.require(context.get('role')==ROLE,'initial bootstrap context only')
    exact(context.get('case'),CASE,'fixed initial context')
    m.require(context.get('case_sha256')==m.digest(CASE),'fixed context case digest')
    q=quote_and_funding(context)
    pub=m.linked(context['source_publication'])
    m.require(pub.get('schema')=='r200_source_publication_v1'
      and pub.get('status')=='PASS_PUBLISHED_R200_SOURCE_PREPARATION'
      and pub.get('commit')==pub.get('remote_readback')
      and pub.get('files')=={k:v['sha256'] for k,v in source_pins.items()}
      and context['source_map_sha256']==m.digest(pub['files']),'published complete bootstrap source')
    bp=Path(__file__).absolute().parent.parent/'owner/compute_boundary.py'
    raw=m.source_bytes(dict(path=str(bp),sha256='f1a5a13f887f60579664d716ff349fdcf86b9dc27cfd1d7fdad6eab3148a04ae'))
    sp=importlib.util.spec_from_file_location('_r201_old_pure_whole_ledger',bp)
    base=importlib.util.module_from_spec(sp);exec(compile(raw,str(bp),'exec'),base.__dict__)
    base._whole_ledger_provenance(context)
    build,br=accepted_record(context['build_acceptance'],'build_acceptance',context['source_map_sha256'])
    deploy,dr=accepted_record(context['deployment_acceptance'],'deployment_acceptance',context['source_map_sha256'])
    for k in ('native_library','native_build_manifest','native_abi'):
        m.require(launch_template.get(k)==build[k],'prepared launch binds accepted '+k)
    m.require(launch_template.get('native_build_acceptance')==context['build_acceptance']
      and launch_template.get('native_deployment_acceptance')==context['deployment_acceptance']
      and deploy['build_acceptance']==context['build_acceptance']
      and deploy['baseline_files']==launch_template.get('baseline_files')
      and dr.get('node')==context['node'] and dr.get('read_only_backing_verified') is True,
      'prepared launch binds actual accepted build/deployment, no job invented')
    namespace=m.linked(dr['canonical_metadata_namespace'])
    m.require(namespace.get('status')=='QUALIFIED_CANONICAL_METADATA_NAMESPACE'
      and namespace.get('source_publication')==context['source_publication']
      and namespace.get('same_bytes_without_old_JSON_rewrite') is True,'qualified canonical metadata baseline')
    return q
