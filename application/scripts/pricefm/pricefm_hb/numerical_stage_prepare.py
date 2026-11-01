"""Actual-READY metadata builders; none issue a root grant or peer PASS.

Three steps preserve an acyclic authorization graph: prepare exact source and
grant requests; bind an actually issued grant/physical proof to owner specs;
then prepare a release proposal after the real independent owner review.
"""
from pathlib import Path
import datetime as dt
import json
from . import startup_helper as h
from . import numerical_batch as batch
from . import numerical_stage_contract as c
from . import numerical_stage_owner as owner


def delivery_request(original_pin,alias_pin,output):
    """Exact NO3 transport request from frozen metadata; no array is opened."""
    h.require(original_pin['sha256']==c.ORIGINAL_MANIFEST_SHA,'unchanged full mathematical source manifest')
    original=h.read(original_pin);aliases=h.read(alias_pin)['aliases']
    selected=[value for value in original['targets'] if value['name']==c.TARGET]
    h.require(len(selected)==1,'one exact NO3 target')
    target=selected[0];tc=target['contract']
    h.require(target['n']==48576 and target['p']==417 and target['tau']==.75
              and tc['certificate_limits']==c.LIMITS,'exact original target dimensions and seven limits')
    by_hash={row['sha256']:row for row in target['bindings']}
    design=tc['design_dir'];known_sizes={'design/X.bin':162049536,'design/y.bin':388608,'fit/beta_cov.bin':1391112,'fit/beta_mean.bin':3336}
    files=[]
    for relative,sha in c.DELIVERY_HASHES.items():
        if sha in by_hash:
            binding=by_hash[sha];logical=binding['path'];size=binding.get('bytes')
        else:
            logical=design+'/'+Path(relative).name;size=None
        local=aliases.get(logical,logical)
        h.physical(local)
        size=known_sizes.get(relative,size)
        if size is None:size=Path(local).stat().st_size  # Filesystem metadata, not array bytes.
        files.append(dict(relative=relative,logical_path=logical,source=dict(path=local,sha256=sha),bytes=size))
    # Validate the closed identities/size envelope with future logical aliases;
    # these paths are proposal labels only, not a staged or issued capability.
    c.validate_delivery('ZERO_UPDATE_BRIDGE',[dict(row,remote=dict(path='/UNISSUED/'+row['relative'],sha256=row['source']['sha256'])) for row in files])
    value=dict(status='PREPARED_EXACT_NO3_OPAQUE_DELIVERY_REQUEST_NOT_AUTHORITY',target_name=c.TARGET,
        original_mathematical_manifest=original_pin,original_source_alias_manifest=alias_pin,
        required_future_authority_status='ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY',files=files,
        total_bytes=sum(row['bytes'] for row in files),array_bytes_opened=False,current_blob_hashes_recomputed=False,
        expected_hashes_from_original_sealed_metadata=True,future_transfer_must_verify_all_exact_bytes=True,
        no_optimizer_or_science_execution=True,scope_and_host_target_delivery_authority_still_required=True)
    path=h.physical(output);h.write_new(path,value);return value


def prerequisite_inputs(accepted_pin,manifest_inputs,output):
    """Build actual-proof aliases/reuse metadata; no old execution grant reused.

    Reads only the completed zero-target boundary's returned metadata and the
    exact three code manifests. It never opens a runtime member or target array.
    """
    accepted=h.read(accepted_pin)
    h.require(accepted.get('status')=='ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
              and accepted.get('role')=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'
              and accepted.get('namespace_proved') is True and accepted.get('scientific_boundary_proved') is True,
              'actual outer accepted boundary prerequisite, never a failed or worker-only result')
    returned=h.read(accepted['full_return_manifest']);result=h.read(accepted['result'])
    guard_path=Path(result['outcome']['owned_guard']['path'])
    h.require(guard_path.name=='owned_guard.json' and guard_path.parent.name=='owner' and guard_path.parents[1].name=='result',
              'exact prior metadata owner return path')
    remote_root=guard_path.parents[1];local_root=Path(accepted['full_return_manifest']['path']).parent
    artifacts={}
    def add(logical,local,expected_size=None):
        raw=h.read_pin(local,limit=32*1024**2)
        h.require(logical['sha256']==local['sha256'] and (expected_size is None or len(raw)==expected_size),
                  'actual exact old proof bytes and length')
        value=dict(logical=logical,local=local,bytes=len(raw))
        if logical['path'] in artifacts:h.require(artifacts[logical['path']]==value,'logical proof alias collision')
        else:artifacts[logical['path']]=value
    for key in ['actual_accept_action_guard','full_return_manifest','result','accounting','independent_review']:
        add(accepted[key],accepted[key])
    rows={}
    for row in returned['files']:
        relative=batch.safe_relative(row['relative']);h.require(str(relative) not in rows,'unique qualified metadata member')
        h.require(relative.suffix.lower() in {'.json','.stdout','.stderr','.lock'},'only zero-target metadata prerequisite may be read administratively')
        rows[str(relative)]=row
        local=dict(path=str(local_root/relative),sha256=row['sha256'])
        add(dict(path=str(remote_root/relative),sha256=row['sha256']),local,row['bytes'])
    h.require('INVENTORY.json' in rows and 'owner/RESULT.json' in rows,'actual qualified inventory and standalone boundary result')
    inventory_pin=dict(path=str(remote_root/'INVENTORY.json'),sha256=rows['INVENTORY.json']['sha256'])
    bundle=dict(status='PREPARED_ACTUAL_ACCEPTED_BOUNDARY_EVIDENCE_NOT_EXECUTION_AUTHORITY',accepted_boundary=accepted,
        original_accepted_record=accepted_pin,artifacts=list(artifacts.values()),return_remote_root=str(remote_root),inventory=inventory_pin,
        old_execution_authority_reused=False,new_root_peer_scope_and_current_kernel_proof_still_required=True)
    qualified=owner.validate_prerequisites(bundle);installation=qualified['installation'];code_root=str(Path(installation['R_HOME']).parent)
    files=[]
    for label in ['base_manifest.json','addon01_manifest.json','addon02_manifest.json']:
        manifest=h.read(manifest_inputs[label])
        for row in manifest['files']:files.append(dict(path=code_root+'/'+row['relative'],sha256=row['sha256']))
    reuse=dict(status='PREPARED_ACCEPTED_NAMESPACE_RUNTIME_REUSE_NOT_EXECUTION_AUTHORITY',accepted_boundary=accepted,
        native_R=dict(path=installation['R_HOME']+'/bin/exec/R',sha256=c.NATIVE_SHA),inventory=qualified['inventory'],
        runtime_files=files,manifest_inputs=manifest_inputs,
        boundary_qualification=dict(path=str(remote_root/'owner/RESULT.json'),sha256=rows['owner/RESULT.json']['sha256']),
        no_runtime_or_target_bytes_opened_administratively=True,current_compute_must_rehash_all2279_code_files=True,
        old_execution_authority_reused=False)
    owner.validate_runtime_reuse(reuse,bundle)
    out=h.physical(output);out.mkdir(mode=0o700);h.write_new(out/'BOUNDARY_PREREQUISITES.json',bundle);h.write_new(out/'RUNTIME_REUSE.json',reuse)
    receipt=dict(status='PREPARED_ACTUAL_PROOF_AND_CODE_REUSE_INPUTS_NO_EXECUTION_AUTHORITY',accepted_boundary=accepted_pin,
        bundle=h.pin(out/'BOUNDARY_PREREQUISITES.json'),runtime_reuse=h.pin(out/'RUNTIME_REUSE.json'),
        metadata_artifact_aliases=len(artifacts),runtime_code_members=2279,old_authorities_or_fees_reused=False,
        target_arrays_opened=False,R_executions=0,optimizer_invocations=0)
    h.write_new(out/'PREPARATION_RECEIPT.json',receipt);return receipt


def context(config_path):
    config,scope,site,hashes=batch.load_config(config_path);root=Path(config['registry'])/config['role']
    packet=batch.packet(root);spec=h.read(h.pin(root/'packet/SPEC.json'));ready=h.read(h.pin(root/'READY.json'))
    job=h.read(h.pin(root/'JOB.json'));batch.validate_ready(ready,packet,job['job_id'])
    return config,scope,root,packet,spec,ready


def prepare(config_path,output):
    config,scope,root,packet,spec,ready=context(config_path);out=h.physical(output);out.mkdir(mode=0o700)
    remote=packet['remote_root'];folder=remote+'/release';reuse=h.read(config['runtime_reuse'])
    def put(name,value):
        h.write_new(out/name,value);return dict(path=folder+'/'+name,sha256=batch.digest(out/name))
    source=dict(kind='R154_project_fullstate_consumer_pinned_CRAN111',head=h.read(config['publication'])['commit'],
                branch=config['source_branch'])
    global_pin=put('GLOBAL_CONTRACT.json',dict(schema='r179_hb_scientific_job_contract_v1',job_id=ready['job_id'],node=config['node'],
        resource_lock=remote+'/numerical.lock',max_new_numerical=1,expires_epoch=scope['expires_epoch']))
    native=reuse['native_R'];rhome=str(Path(native['path']).parents[2]);library=rhome+'/library'
    runtime_files={row['path']:row['sha256'] for row in reuse['runtime_files']}
    rscript=rhome+'/bin/Rscript';h.require(rscript in runtime_files,'exact qualified Rscript bytes for unchanged frozen checks')
    runtime_pin=put('ACTUAL_RUNTIME_BINDING.json',dict(actual_executable=native['path'],actual_executable_sha256=native['sha256'],
        Rscript=rscript,Rscript_sha256=runtime_files[rscript],R_home=rhome,package_path=library+'/exdqlm',
        kind='EXACT_ACCEPTED_NAMESPACE_BYTES_REHASHED_IN_CURRENT_JOB',accepted_boundary=reuse['accepted_boundary']))
    entry=spec['science']['application/tests/r179_hb_toy.R' if config['role']=='TOY_PARITY' else 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R']
    bindings=c.ordered_science_pins(spec['science'])+[spec['sources']['numerical_stage_bootstrap.R']]
    adapter=spec['sources']['numerical_stage_owner.py']
    source_request=dict(status='REQUEST_NOT_PEER_PASS',required_status='PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE',
        execution_adapter_source=adapter,job_id=ready['job_id'],node=config['node'],role=config['role'],scope_id=spec['scope_id'],
        source_bindings=bindings,source_publication=config['publication'],role_limits=config['role_limits'],
        scientific_suffixes_byte_identical_required=True)
    put('STAGE_SOURCE_REVIEW_REQUEST.json',source_request)
    grant=dict(schema='pricefm_hb_scientific_stage_grant_v1',status='PROPOSED_UNISSUED',
        required_status='ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY' if config['role']=='TOY_PARITY' else 'ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY',
        role=config['role'],job_id=ready['job_id'],node=config['node'],affinity=ready['affinity'],scope_id=spec['scope_id'],
        memory_MiB=8192,memory_GiB=8,cores=1,max_new_numerical=1,attempt_index=1,new_attempt_index=1,
        old_claims_reused=False,old_costs_refunded=False,authorizes_production_acceptance=False,authorizes_production_fits=False,
        expires_UTC=dt.datetime.fromtimestamp(scope['expires_epoch'],dt.timezone.utc).isoformat(),stage_deadline_epoch=scope['expires_epoch'],
        global_contract=global_pin,source_review=None,source=source,source_bindings=bindings,execution_adapter_source=adapter,
        actual_R_runtime_binding=runtime_pin,cran_library=library,entrypoint=entry,expected_stock_body_sha256=c.STOCK_BODY_SHA,
        scientific_boundary_qualification=reuse['boundary_qualification'],maximum_CPU_seconds=300,
        maximum_optimizer_invocations=8 if config['role']=='TOY_PARITY' else 0,maximum_total_optimizer_iterations=30 if config['role']=='TOY_PARITY' else 0,
        maximum_n=128 if config['role']=='TOY_PARITY' else 48576,maximum_p=32 if config['role']=='TOY_PARITY' else 417,
        authorizes_toy_optimizer=config['role']=='TOY_PARITY',disk_GiB=2)
    grant['conditional_parse_and_current_kernel_ACK_required']=True
    if config['role']=='ZERO_UPDATE_BRIDGE':
        grant.update(mode='bridge',target_name=c.TARGET,max_iter=0,manifest_sha256=spec['execution_manifest']['sha256'])
    put('STAGE_GRANT_TEMPLATE.json',grant)
    physical=ready['physical_snapshot_value']
    physical_template=dict(status='PROPOSED_UNISSUED',required_status='ROOT_ADMITTED_EXACT_SLURM_NUMERICAL_PHYSICAL_CORE',
        job_id=ready['job_id'],node=config['node'],uid=physical['uid'],affinity=ready['affinity'],topology=physical['topology'],
        Slurm_core_policy=physical['Slurm_core_policy'],actual_snapshot=ready['physical_snapshot'],
        all_SMT_siblings_reserved_to_this_job=None,unreviewed_numerical_peer_intersections=None,
        priority_drain_complete=None,old_processes_signalled_or_peer_allowlist_broadened=False,
        issued_epoch=None,expires_epoch=min(scope['expires_epoch'],physical['scheduler']['end_epoch']),**physical['witness_pins'])
    put('PHYSICAL_CORE_PROOF_TEMPLATE.json',physical_template)
    put('PHYSICAL_CORE_REVIEW_REQUEST.json',dict(status='REQUEST_NOT_PEER_PASS',
        required_status='PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN',job_id=ready['job_id'],node=config['node'],
        topology=physical['topology'],actual_snapshot=ready['physical_snapshot'],
        all_peer_and_drain_witnesses_bound=None,**physical['witness_pins']))
    required=['STAGE_SOURCE_REVIEW.json','STAGE_GRANT.json','PHYSICAL_CORE_PROOF.json','PHYSICAL_CORE_REVIEW.json']
    receipt=dict(status='PREPARED_ACTUAL_READY_SOURCE_AND_GRANT_REQUESTS_NOT_AUTHORITY',config=h.pin(config_path),
        actual_ready=h.pin(root/'READY.json'),packet=h.pin(root/'PACKET.json'),spec=h.pin(root/'packet/SPEC.json'),
        remote_root=remote,remote_release=folder,required_actual_files_before_bind=required,
        no_R_optimizer_target_delivery_or_execution=True)
    h.write_new(out/'PREPARATION.json',receipt);return receipt


def bind_owner(config_path,output):
    config,scope,root,packet,spec,ready=context(config_path);out=h.physical(output);folder=packet['remote_root']+'/release'
    def remote_pin(name):return dict(path=folder+'/'+name,sha256=batch.digest(out/name))
    grant=h.read(h.pin(out/'STAGE_GRANT.json'));source_review=h.read(h.pin(out/'STAGE_SOURCE_REVIEW.json'))
    h.require(source_review.get('status')=='PASS_REVIEWED_HB_SCIENTIFIC_STAGE_SOURCE'
              and grant.get('source_review')==remote_pin('STAGE_SOURCE_REVIEW.json')
              and grant.get('role')==config['role'] and grant.get('job_id')==ready['job_id']
              and all(source_review.get(k)==grant[k] for k in ['role','job_id','node','scope_id','execution_adapter_source','source_bindings']),
              'actual exact independently reviewed root grant')
    reuse=h.read(config['runtime_reuse']);native=reuse['native_R'];remote=packet['remote_root'];rhome=str(Path(native['path']).parents[2])
    library=rhome+'/library';outdir=remote+'/result/numerical';stage_pin=remote_pin('STAGE_GRANT.json')
    entry=grant['entrypoint'];science_root=remote+'/science'
    args=[science_root,stage_pin['path'],stage_pin['sha256'],outdir+'/toy']
    if config['role']=='ZERO_UPDATE_BRIDGE':args=['bridge',science_root,spec['execution_manifest']['path'],stage_pin['path'],stage_pin['sha256'],outdir+'/bridge']
    bspec=dict(schema='r182_hb_numerical_bootstrap_v1',role=config['role'],job_id=ready['job_id'],node=config['node'],nonce=spec['nonce'],
        library=library,fixedpoint_helper=spec['science']['application/R/pricefm_r129_al_fixedpoint_certificate.R'],
        boundary_library=spec['controls']['boundary_library'],scientific_entrypoint=entry,entrypoint_args=args,expected_stock_body_sha256=c.STOCK_BODY_SHA)
    bspec['source_parse_files']=c.ordered_science_pins(spec['science'])
    h.write_new(out/'BOOTSTRAP_SPEC.json',bspec)
    env={key:'1' for key in h.THREAD_KEYS};env.update(PATH='/usr/bin:/bin',LANG='C',LC_ALL='C',TZ='UTC',HOME=remote,TMPDIR=remote+'/tmp',
        R_HOME=rhome,R_ARCH='',R_DOC_DIR=rhome+'/doc',R_INCLUDE_DIR=rhome+'/include',R_SHARE_DIR=rhome+'/share',R_LIBS_USER=library,R_LIBS_SITE=library,
        LD_LIBRARY_PATH=rhome+'/lib:'+str(Path(rhome).parent/'lib'),SLURM_JOB_ID=ready['job_id'],SLURMD_NODENAME=config['node'],SLURM_CPUS_PER_TASK='1',
        R154_PROJECT_PROJECTION_TOY_ROOT_ADMITTED='1' if config['role']=='TOY_PARITY' else '0',
        R154_PROJECT_ROOT_ADMITTED='0' if config['role']=='TOY_PARITY' else '1',R154_PROJECT_MODE='toy' if config['role']=='TOY_PARITY' else 'bridge',
        R154_PROJECT_ADMISSION_PATH=stage_pin['path'],R154_PROJECT_ADMISSION_SHA256=stage_pin['sha256'],
        R154_PROJECT_RUNTIME_PATH=grant['actual_R_runtime_binding']['path'],R154_PROJECT_RUNTIME_SHA256=grant['actual_R_runtime_binding']['sha256'])
    allowed={row['resolved_file']['path']:row['resolved_file']['sha256'] for row in ready['inventory']['helpers'].values()};allowed[native['path']]=native['sha256']
    ospec=dict(schema='r182_frozen525_numerical_owner_spec_v1',role=config['role'],role_limits=config['role_limits'],
        job_id=ready['job_id'],node=config['node'],affinity=ready['affinity'],scope_id=spec['scope_id'],nonce=spec['nonce'],expires_epoch=scope['expires_epoch'],
        source_commit=spec['source_commit'],
        remote_namespace=remote,science_root=science_root,output=outdir,resource_lock=remote+'/numerical.lock',
        traced_guard=spec['controls']['traced_guard'],boundary_library=spec['controls']['boundary_library'],R_native=native,
        bootstrap=spec['sources']['numerical_stage_bootstrap.R'],bootstrap_spec=remote_pin('BOOTSTRAP_SPEC.json'),stage_grant=stage_pin,
        boundary_qualification=reuse['boundary_qualification'],accepted_boundary=reuse['accepted_boundary'],
        prerequisite_bundle=spec['controls']['prerequisite_bundle'],entrypoint=entry,scientific_sources=spec['science'],
        scientific_source_bindings=grant['source_bindings'],execution_adapter_source=grant['execution_adapter_source'],
        environment=env,bootstrap_exec_allowlist=allowed,target_delivery=spec['target_delivery'],
        physical_snapshot=ready['physical_snapshot'],physical_core_proof=remote_pin('PHYSICAL_CORE_PROOF.json'),physical_core_review=remote_pin('PHYSICAL_CORE_REVIEW.json'))
    ospec['known_prior_jobs']=spec['known_prior_jobs']
    if config['role']=='ZERO_UPDATE_BRIDGE':ospec['execution_manifest']=spec['execution_manifest']
    c.validate_grant(ospec,grant,now=__import__('time').time());h.write_new(out/'OWNER_SPEC.json',ospec)
    owner_sources={name:spec['sources'][name] for name in owner.sources()}
    auth=dict(status='PROPOSED_UNISSUED',required_status='ROOT_ADMITTED_R182_FROZEN525_NUMERICAL_STAGE',spec=remote_pin('OWNER_SPEC.json'),
        sources=owner_sources,role=config['role'],max_calls=1,memory_MiB=8192,whole_CPU_seconds=600,whole_wall_seconds=1200,
        owner_CPU_seconds=450,owner_wall_seconds=300,R_child_CPU_seconds=300,issued_epoch=None,expires_epoch=scope['expires_epoch'])
    h.write_new(out/'OWNER_AUTHORITY_TEMPLATE.json',auth)
    return dict(status='PREPARED_BOUND_OWNER_SPEC_NOT_ROOT_AUTHORITY_OR_PEER_PASS',owner_spec=remote_pin('OWNER_SPEC.json'),
                owner_authority_required=True,independent_owner_review_required=True,independent_outer_release_required=True)


def release_proposal(config_path,output):
    config,scope,root,packet,spec,ready=context(config_path);out=h.physical(output);folder=packet['remote_root']+'/release'
    labels=dict(owner_spec='OWNER_SPEC.json',owner_authority='OWNER_AUTHORITY.json',owner_review='OWNER_REVIEW.json',stage_grant='STAGE_GRANT.json',
        stage_source_review='STAGE_SOURCE_REVIEW.json',global_contract='GLOBAL_CONTRACT.json',bootstrap_spec='BOOTSTRAP_SPEC.json',
        physical_core_proof='PHYSICAL_CORE_PROOF.json',physical_core_review='PHYSICAL_CORE_REVIEW.json',independent_review='PEER_RELEASE.json')
    extra=['ACTUAL_RUNTIME_BINDING.json']
    pins={key:dict(path=folder+'/'+name,sha256=batch.digest(out/name)) for key,name in labels.items()}
    peer=h.read(h.pin(out/'PEER_RELEASE.json'))
    h.require(peer.get('status')=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE'
              and peer.get('stage_pins')=={key:value for key,value in pins.items() if key!='independent_review'},
              'actual exact independent release review before proposal')
    value=dict(status='PROPOSED_UNISSUED',required_status='ROOT_RELEASED_STARTUP_BATCH_ROLE',purpose='FROZEN525_NUMERICAL_STAGE_ONLY',
        role=config['role'],scope_id=spec['scope_id'],job_id=ready['job_id'],node=config['node'],ready_sha256=batch.digest(root/'READY.json'),
        spec_sha256=packet['spec_sha256'],scope_sha256=config['scope']['sha256'],sources=spec['sources'],issued_epoch=None,expires_epoch=scope['expires_epoch'],
        files=[dict(relative=name,sha256=batch.digest(out/name)) for name in sorted(set(labels.values())|set(extra))],**pins)
    h.write_new(out/'RELEASE_PROPOSAL.json',value);return value
