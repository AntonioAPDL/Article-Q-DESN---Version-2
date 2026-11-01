"""Native one-shot control for separately admitted frozen525 numerical stages.

Lifecycle primitives are mechanically copied from frozen r181 b42ba3e; their
source derivation is recorded. Numerical role/spec/release/core/return admission
is separate. Metadata grants cannot authorize these roles. No R runs on login.
"""
import argparse,contextlib,datetime,fcntl,hashlib,json,math,os,re,resource,shlex,signal,subprocess,sys,time
from pathlib import Path,PurePosixPath
from . import startup_helper as h
from . import numerical_stage_contract as contract
from . import numerical_stage_owner as owner
from . import scientific_batch as metadata
ROLES=contract.ROLES
NAMES=tuple(metadata.NAMES)+('numerical_batch.py','numerical_stage_owner.py','numerical_stage_contract.py','numerical_physical_admission.py','numerical_stage_worker.py','numerical_stage_bootstrap.R')
NATIVE=metadata.NATIVE
TERMINAL=metadata.TERMINAL
ACTION_ENVELOPE=metadata.ACTION_ENVELOPE
NATIVE_CONTROL_TOTAL=136


def load_config(path):
    h.require(os.sched_getaffinity(0)=={31},'metadata administrative CPU31 only')
    config=h.read(h.pin(path));scope=h.read(config['scope']);now=time.time()
    h.require(config.get('schema')=='r182_numerical_batch_config_v1' and config.get('role') in ROLES,
              'separate exact supported numerical batch config')
    h.require(scope.get('status')=='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE'
              and scope.get('roles')==[config['role']] and scope.get('maximum_jobs')==scope.get('max_concurrent_jobs')==1
              and scope.get('compute_CPU_reservation')==600 and scope.get('wall_seconds')==1200
              and scope.get('memory_MiB')==8192 and scope.get('threads')==scope.get('cpus_per_task')==1
              and scope.get('automatic_retry') is False and scope.get('requeue') is False
              and scope['issued_epoch']<=now<scope['expires_epoch'],'new whole numerical purpose reservation required')
    contract.validate_role(config['role'],config['role_limits'])
    root=h.physical(scope['allowed_metadata_output_root']);registry=h.physical(config['registry'])
    h.require(str(root).startswith('/home/jaguir26/.local/state/pricefm/') and registry.parent==root
              and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,'private persistent canonical root')
    placement=h.read(config['placement_proof']);rows=[r for r in placement.get('rows',[]) if r.get('label')=='home']
    h.require(placement.get('same_original_H4_caps_and_stopped_rules') is True
              and len(rows)==1 and rows[0]['root']==str(root.parent) and rows[0]['device']==root.stat().st_dev
              and rows[0]['returncode']==0 and rows[0]['files']==8,'actual unchanged-rule persistent-home placement proof')
    passing_guard(h.read(rows[0]['guard']),4,90)
    hashes={name:digest(Path(config['source_dir'])/name) for name in NAMES}
    pub=h.read(config['publication']);review=h.read(config['source_review'])
    admin_names=['numerical_stage_prepare.py','numerical_critical_driver.py','numerical_independent_peer.py']
    admin_hashes={name:digest(Path(config['source_dir'])/name) for name in admin_names}
    h.require(pub.get('status')=='PASS_FROZEN525_NUMERICAL_BATCH_SOURCE_PUBLICATION'
              and review.get('status')=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_SOURCE'
              and pub.get('source_files')==review.get('source_files')==hashes
              and pub.get('administrative_source_files')==review.get('administrative_source_files')==admin_hashes
              and re.fullmatch('[0-9a-f]{40}',pub['commit']),'new numerical source publication and independent review')
    authority=h.read(config['canonical_authority'])
    h.require(authority.get('status')=='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'
              and authority.get('binding')==canonical_identity(config) and authority.get('maximum_jobs')==1
              and scope['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=scope['expires_epoch'],
              'new exact whole numerical config authority')
    budget=h.read(config['native_control_budget'])
    h.require(budget.get('status')=='PROSPECTIVE_FRESH_NUMERICAL_NATIVE_CONTROL_BUDGET'
              and budget.get('combined_native_control_CPU_ceiling')==136 and budget.get('scope')==config['scope']
              and budget.get('expires_epoch')==scope['expires_epoch'],'separate complete native136 funding')
    h.require(config['node']=='node-13' and config['remote_namespace'].startswith('/mnt/beegfs/home/jaguir26/pricefm_r182_'),
              'new isolated numerical namespace on qualified node')
    h.require(set(config['scientific_sources'])==set(contract.SCIENCE_HASHES)
              and {name:v['sha256'] for name,v in config['scientific_sources'].items()}==contract.SCIENCE_HASHES,
              'exact unchanged mathematical and authority-only port sources')
    for key,sha in [('traced_guard',contract.TRACE_SHA),('boundary_library',contract.BOUNDARY_SHA)]:
        h.require(config[key]['sha256']==sha,'unchanged original native scientific ownership machinery')
    proof=h.read(config['prerequisite_bundle']);owner.validate_prerequisites(proof)
    known=h.read(config['known_jobs_registry']);rows=known.get('jobs',[])
    expected=[dict(job_id=row['job_id'],job_name=row['job_name'],terminal=row.get('state') in TERMINAL) for row in rows]
    h.require(config.get('known_prior_jobs')==expected and expected
              and all(row['terminal'] for row in expected)
              and any(row['job_id']==proof['accepted_boundary']['job_id'] and row['job_name']==proof['accepted_boundary']['scope_id'] for row in expected),
              'entire currently pinned known PriceFM registry and qualified parent must be terminal before new role')
    reuse=h.read(config['runtime_reuse'])
    owner.validate_runtime_reuse(reuse,proof)
    if config['role']=='ZERO_UPDATE_BRIDGE':
        delivery=h.read(config['opaque_delivery_authority'])
        contract.validate_opaque_delivery_authority(delivery,config['scope'],config['target_delivery'],config['original_manifest'])
    else:h.require(config['target_delivery']==[],'toy target delivery forbidden')
    return config,scope,site_config(config['site']),hashes


def prepare(config,scope,role,hashes,registry):
    h.require(role==config['role'] and role in ROLES,'exact singly funded numerical role')
    root=registry/role;root.mkdir(mode=0o700);out=root/'packet';out.mkdir(mode=0o700)
    (out/'package/pricefm_hb').mkdir(parents=True);(out/'science').mkdir()
    token=hashlib.sha256((str(root)+str(time.time_ns())).encode()).hexdigest()[:32]
    scope_id='r182-'+('toy-' if role=='TOY_PARITY' else 'bridge-')+token[:20]
    remote=config['remote_namespace']+'/'+scope_id;uploads=[]
    def add(pin,relative,copy=True):
        path=h.physical(pin['path']);h.require(digest(path)==pin['sha256'],'prepared source/input drift')
        if copy:
            target=out/relative;target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as stream:stream.write(path.read_bytes())
            path=target
        uploads.append(dict(local=str(path),relative=relative,sha256=pin['sha256'],bytes=path.stat().st_size))
        return dict(path=remote+'/'+relative,sha256=pin['sha256'])
    sources={name:add(dict(path=str(Path(config['source_dir'])/name),sha256=sha),'package/pricefm_hb/'+name)
             for name,sha in hashes.items()}
    science={name:add(pin,'science/'+name) for name,pin in config['scientific_sources'].items()}
    controls={key:add(config[key],'science/'+key+('.py' if key=='traced_guard' else '.so'))
              for key in ['traced_guard','boundary_library']}
    prerequisite=h.read(config['prerequisite_bundle'])
    for index,row in enumerate(prerequisite['artifacts']):
        source=row.get('local') or row['staged']
        row['staged']=add(source,'prerequisites/artifact_%04d'%index)
    h.write_new(out/'prerequisite_bundle.json',prerequisite)
    controls['prerequisite_bundle']=add(h.pin(out/'prerequisite_bundle.json'),'prerequisite_bundle.json',False)
    reuse=h.read(config['runtime_reuse'])
    for index,(name,pin) in enumerate(sorted(reuse['manifest_inputs'].items())):
        reuse['manifest_inputs'][name]=add(pin,'runtime_manifest_%02d.json'%index)
    h.write_new(out/'runtime_reuse.json',reuse)
    controls['runtime_reuse']=add(h.pin(out/'runtime_reuse.json'),'runtime_reuse.json',False)
    scope_pin=add(config['scope'],'Q_SCOPE.json')
    delivery=[]
    for row in config['target_delivery']:
        relative='target/'+str(safe_relative(row['relative']));remote_pin=add(row['source'],relative,False)
        delivery.append(dict(row,remote=remote_pin))
    contract.validate_delivery(role,delivery)
    execution_manifest=None
    if role=='ZERO_UPDATE_BRIDGE':
        h.require(config['original_manifest']['sha256']==contract.ORIGINAL_MANIFEST_SHA,'unchanged full original mathematical manifest')
        original=h.read(config['original_manifest']);target=next(v for v in original['targets'] if v['name']==contract.TARGET)
        original_pin=add(config['original_manifest'],'original_target_manifest.json')
        aliases={row['logical_path']:row['remote']['path'] for row in delivery}
        tc=target['contract']
        for key,relative in [('design_dir','design'),('output_dir','fit'),('parent_dir','parent')]:
            aliases[tc[key]]=remote+'/target/'+relative
        aliases[tc['cran_library']]=str(Path(reuse['native_R']['path']).parents[2]/'library')
        for binding in target['bindings']:
            h.require(any(row['logical_path']==binding['path'] and row['remote']['sha256']==binding['sha256'] for row in delivery),
                      'every exact original NO3 binding has a byte-identical remote alias')
        manifest=dict(schema='r182_exact_NO3_HB_alias_execution_manifest_v1',
            status='PREPARED_REMOTE_ALIASES_NOT_EXECUTION_AUTHORITY',original_manifest=original_pin,
            execution={contract.TARGET:dict(aliases=aliases,execution_host=config['node'],source_host='jerez.be.ucsc.edu')},
            original_mathematical_manifest_bytes_unchanged=True,optimizer_updates=0)
        h.write_new(out/'execution_manifest.json',manifest)
        execution_manifest=add(h.pin(out/'execution_manifest.json'),'execution_manifest.json',False)
    spec=dict(schema='r182_numerical_batch_spec_v1',role=role,role_limits=config['role_limits'],scope_id=scope_id,
        nonce=token,remote_root=remote,scope=scope_pin,sources=sources,science=science,controls=controls,target_delivery=delivery,
        node=config['node'],cached_python=config['cached_python'],cached_python_sha256=config['cached_python_sha256'],
        source_commit=h.read(config['publication'])['commit'],expires_epoch=scope['expires_epoch'],release_wait_seconds=120,
        aggregate_CPU_reservation=600,wall_seconds=1200,memory_MiB=8192,threads=1,
        maximum_return_bytes=contract.MAX_RETURN_TOTAL,maximum_return_files=contract.MAX_RETURN_FILES,
        production_fits=0,new_models=0,optimizer_invocations=config['role_limits']['optimizer_invocations'],
        known_prior_jobs=config['known_prior_jobs'])
    if execution_manifest:spec['execution_manifest']=execution_manifest
    h.write_new(out/'SPEC.json',spec);spec_sha=digest(out/'SPEC.json')
    body='#!/bin/bash\nset -euo pipefail\numask 077\nulimit -c 0\nulimit -t 600\nexport PATH=/usr/bin:/bin\nexport TZ=UTC\n'
    body+='\n'.join('export '+k+'=1' for k in sorted(h.THREAD_KEYS))+'\n'
    body+='exec '+shlex.join([config['cached_python'],'-I','-B',remote+'/package/pricefm_hb/numerical_stage_worker.py',
                             '--spec',remote+'/SPEC.json','--sha256',spec_sha])+'\n'
    with (out/'job.sbatch').open('x') as stream:stream.write(body)
    for name in ['SPEC.json','job.sbatch']:add(h.pin(out/name),name,False)
    result=dict(scope_id=scope_id,role=role,remote_root=remote,spec_sha256=spec_sha,uploads=uploads,sources=sources,
                source_publication=config['publication'],source_review=config['source_review'])
    h.write_new(root/'PACKET.json',result);append(root,'PREPARED',packet=h.pin(root/'PACKET.json'));return result


def validate_local_release(root,bundle):
    packet_value=packet(root);job=h.read(h.pin(root/'JOB.json'));ready_value=h.read(h.pin(root/'READY.json'))
    folder=h.physical(bundle);release=h.read(h.pin(folder/'RELEASE.json'))
    required={'owner_spec','owner_authority','owner_review','stage_grant','stage_source_review',
              'global_contract','bootstrap_spec','physical_core_proof','physical_core_review','independent_review'}
    h.require(release.get('status')=='ROOT_RELEASED_STARTUP_BATCH_ROLE' and release.get('role')==packet_value['role']
              and release.get('purpose')=='FROZEN525_NUMERICAL_STAGE_ONLY'
              and release.get('job_id')==job['job_id'] and release.get('ready_sha256')==digest(root/'READY.json')
              and release.get('spec_sha256')==packet_value['spec_sha256'] and release.get('sources')==packet_value['sources'],
              'exact current numerical root release')
    names=set()
    for row in release['files']:
        name=str(safe_relative(row['relative']));h.require('/' not in name and name not in names,'flat unique stage release files')
        names.add(name);h.require(digest(folder/name)==row['sha256'],'complete numerical release bytes')
    for key in required:
        pin=release[key];h.require(Path(pin['path']).parent==Path(packet_value['remote_root'])/'release'
                                 and Path(pin['path']).name in names,'every numerical grant/proof included before release')
        h.require(digest(folder/Path(pin['path']).name)==pin['sha256'],'exact stage release pin')
    peer=h.read(h.pin(folder/Path(release['independent_review']['path']).name))
    h.require(peer.get('status')=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE'
              and peer.get('role')==packet_value['role'] and peer.get('job_id')==job['job_id']
              and peer.get('ready_sha256')==digest(root/'READY.json')
              and peer.get('stage_pins')=={key:release[key] for key in required-{'independent_review'}},
              'independent exact numerical release review, not metadata authority')
    return release


def validate_manifest(manifest,spec,job_id):
    h.require(manifest.get('schema')=='r182_frozen525_numerical_return_manifest_v1'
              and manifest.get('scope_id')==spec['scope_id'] and manifest.get('job_id')==job_id,
              'exact numerical-purpose complete return manifest')
    rows=manifest.get('files');h.require(type(rows) is list and 1<=len(rows)<=contract.MAX_RETURN_FILES,'finite numerical return')
    seen=set();total=0;allowed,binary=contract.output_inventory(spec['role'])
    allowed|={'numerical/FAILED.json'}
    for row in rows:
        rel=str(safe_relative(row['relative']));h.require(rel not in seen,'unique returned paths')
        seen.add(rel);total+=row['bytes']
        h.require(type(row['bytes']) is int and 0<=row['bytes']<=contract.MAX_RETURN_FILE
                  and re.fullmatch('[0-9a-f]{64}',row['sha256']),'finite typed returned file')
        h.require(rel in allowed,'result outside exact frozen toy/bridge producer forbidden')
        if Path(rel).suffix.lower() in {'.rds','.bin'}:h.require(rel in binary,'unexpected binary output')
    h.require(total<=contract.MAX_RETURN_TOTAL and 'RESULT.json' in seen,'bounded complete numerical metadata/result return')
    if manifest.get('complete_success') is True:
        h.require(seen==contract.output_inventory(spec['role'])[0],'exact complete toy/bridge output inventory')
    return True


def accept(config,site,root,actual_review):
    p=packet(root);job=h.read(h.pin(root/'JOB.json'));past=records(root);one_shot(root,'accept')
    accounting=next(x['accounting'] for x in reversed(past) if x['state']=='OBSERVED');account=h.read(accounting)
    returned=next(x['manifest'] for x in reversed(past) if x['state']=='RETURNED');manifest=h.read(returned)
    h.require(account['terminal'] and account['complete'],'successful complete terminal primary accounting required')
    h.require(manifest.get('complete_success') is True,'PASS acceptance requires the exact full successful numerical return')
    validate_manifest(manifest,p,job['job_id'])
    for row in manifest['files']:
        path=root/'returned'/row['relative'];h.require(path.stat().st_size==row['bytes'] and digest(path)==row['sha256'],'returned bytes changed')
    result_pin=h.pin(root/'returned/RESULT.json');result=h.read(result_pin)
    h.require(result.get('status')=='PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER'
              and all(result.get(k)==p[k] for k in ['role','scope_id','sources','spec_sha256'])
              and result.get('job_id')==job['job_id'] and result.get('node')==config['node']
              and result.get('production_fits')==0 and result.get('pilot_fits')==0,
              'exact completed numerical worker proof, no production or pilot')
    outcome=result['outcome'];expected='PASS_HB_FROZEN525_SYNTHETIC_TOY' if p['role']=='TOY_PARITY' else 'PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE'
    h.require(outcome.get('status')==expected and outcome.get('job_id')==job['job_id']
              and outcome.get('node')==config['node'] and outcome.get('current_TSYNC_and_parent_ACK') is True,
              'actual current-run numerical and TSYNC proof required')
    validate_returned_proofs(root,p,result,manifest)
    review_pin=h.pin(actual_review);review=h.read(review_pin)
    h.require(review.get('status')=='PASS_REVIEWED_COMPLETE_FROZEN525_NUMERICAL_ROLE'
              and review.get('job_id')==job['job_id'] and review.get('role')==p['role']
              and review.get('result')==result_pin and review.get('return_manifest')==returned
              and review.get('accounting')==accounting,'independent actual complete numerical return review')
    queue=run_native(site,['squeue','--noheader','--user',site['user'],'--format','%i'])
    h.require(queue['returncode']==0 and job['job_id'] not in queue['stdout'].split(),'known job still queued/unknown')
    value=dict(status='ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD',role=p['role'],job_id=job['job_id'],scope_id=p['scope_id'],
        result=result_pin,full_return_manifest=returned,accounting=accounting,canonical_primary_CPU_seconds=account['canonical_primary_CPU_seconds'],
        primary_charge_counted_once=True,independent_review=review_pin,toy_parity_proved=p['role']=='TOY_PARITY',
        exact_NO3_zero_update_bridge_proved=p['role']=='ZERO_UPDATE_BRIDGE',production_admission=False,pilot_fits=0)
    h.write_new(root/'ACCEPTANCE_CANDIDATE.json',value);append(root,'ACCEPTANCE_VALIDATED',candidate=h.pin(root/'ACCEPTANCE_CANDIDATE.json'))
    lock=config['remote_namespace']+'/qualification.lock'
    for argv in [['test','-f',lock+'/OWNED_'+p['scope_id']],['rm','--',lock+'/OWNED_'+p['scope_id']],['rmdir',lock]]:
        h.require(run_native(site,argv)['returncode']==0,'accepted useful data but exact claim release incomplete')
    append(root,'ACCEPTANCE_PENDING_GUARD',candidate=h.pin(root/'ACCEPTANCE_CANDIDATE.json'),claim_released=True);return value


def validate_returned_proofs(root,packet_value,result,manifest):
    """Independent metadata/opaque-hash closure; no RDS deserialization or scoring."""
    remote=Path(packet_value['remote_root']);returned=root/'returned'
    rows={row['relative']:row for row in manifest['files']}
    release_record=next(row for row in reversed(records(root)) if row['state']=='RELEASED')
    release_path=Path(release_record['release']['path']);release=h.read(release_record['release']);bundle=release_path.parent
    release_rows={row['relative']:row for row in release['files']}
    def bytes_for(pin):
        path=Path(pin['path'])
        if path.is_relative_to(remote/'result'):
            relative=str(path.relative_to(remote/'result'));h.require(relative in rows,'exact returned proof membership')
            row=rows[relative];local=returned/relative
            h.require(row['sha256']==pin['sha256'],'returned proof logical SHA')
            raw=h.read_pin(h.pin(local),limit=contract.MAX_RETURN_FILE)
            h.require(digest(local)==pin['sha256'] and len(raw)==row['bytes'],'exact proof bytes/length')
            return raw
        h.require(path.parent==remote/'release' and path.name in release_rows,'exact flat released proof membership')
        row=release_rows[path.name];h.require(row['sha256']==pin['sha256'],'released proof logical SHA')
        return h.read_pin(dict(path=str(bundle/path.name),sha256=pin['sha256']),limit=contract.MAX_RETURN_FILE)
    read=lambda pin:h.strict_json(bytes_for(pin))
    outcome=result['outcome'];guard=read(outcome['owned_guard']);tree=read(outcome['owned_tree'])
    owner.accepted_guard(guard)
    h.require(guard.get('maximum_combined_CPU_seconds')==450
              and guard.get('parent_plus_all_reaped_child_CPU_seconds',float('inf'))<450
              and guard.get('wall_seconds',float('inf'))<300,'actual exact inclusive owner budget')
    ready=h.read(h.pin(root/'READY.json'));identity=ready['worker_identity']
    h.require(identity.get('uid')==ready['inventory']['scheduler']['uid']==os.getuid(),
              'current exact scheduler/READY worker kernel UID')
    h.require(tree.get('schema')=='r157_ptrace_owner_v1' and tree.get('state')=='CLOSED'
              and tree.get('scope')==packet_value['scope_id'] and tree.get('source')==dict(kind=owner.SOURCE_KIND)
              and tree.get('authority_pin')==release['owner_authority'],'exact current complete numerical owner')
    for actual in [guard['supervisor'],tree['supervisor']]:
        h.require(all(actual.get(key)==identity[key] for key in ['pid','start_ticks','boot_id','affinity']),
                  'actual READY worker lifetime owns this exact trace')
    spec=read(release['owner_spec']);grant=read(release['stage_grant']);core=read(outcome['core'])
    h.require(spec['role']==packet_value['role'] and spec['scope_id']==packet_value['scope_id']
              and spec['stage_grant']==release['stage_grant'] and spec['job_id']==result['job_id'],
              'actual released numerical owner/grant/core agreement')
    owner.validate_core(spec['role'],core,grant,release['stage_grant'],remote/'result/numerical',verify_bytes=bytes_for)
    gate=read(outcome['owner_validated_parse_before_kernel_ACK'])
    h.require(gate.get('status')=='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK'
              and gate.get('role')==spec['role'] and gate.get('scope_id')==spec['scope_id']
              and gate.get('job_id')==spec['job_id'] and gate.get('authority')==release['owner_authority']
              and gate.get('original_tracer_pre_ACK_capture_callback') is True,
              'actual owning parent parse gate before original kernel ACK')
    owner.parse_gate(spec,json.dumps(gate['frame'],sort_keys=True).encode(),'SCIENTIFIC_FORK_DENIED',
                     dict(state='LIVE',kernel_trace_owned=True,scientific_filter_accepted=True))
    owner.physical.validate_filesystem(gate['filesystem_before_ACK'],spec['remote_namespace'],now=gate['filesystem_before_ACK']['observed_epoch'])
    h.require(outcome.get('source_parse_pass_before_numerical_entrypoint')==gate['frame'],
              'same exact parent-gated parse frame and numerical result')
    return True


def safe_path(value):
    h.require(type(value) is str and re.fullmatch(r"/[A-Za-z0-9_./-]+", value)
              and ".." not in Path(value).parts, "safe absolute path required")
    return value


def canonical_identity(config):
    return {k:v for k,v in config.items() if k!='canonical_authority'}


def passing_guard(guard,CPU,wall):
    h.require(guard.get('returncode')==guard.get('command_returncode')==0 and guard.get('cap_reason') is None
              and guard.get('CPU_limit')==CPU and 0<=guard['aggregate_CPU_seconds']<CPU
              and 0<=guard['complete_lifecycle_wall_seconds']<=wall
              and all(guard.get(k) is True for k in ['all_owned_descendants_reaped','independent_guardian',
                    'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once'])
              and guard.get('guardian_forced_monitor_stop') is False,'complete original outer guard required')


def known_job(root):
    direct=root/'JOB.json';forensic=root/'RECONCILED_JOB.json'
    h.require(direct.exists() or forensic.exists(),'no exact known job; forensic reconciliation required before drain')
    return h.read(h.pin(direct if direct.exists() else forensic))


def reconcile(config,site,root):
    """One exact-nonce forensic observation; never grants release or retries."""
    p=packet(root);one_shot(root,'reconcile')
    h.require((root/'ROLE_FAILED_SPENT.json').is_file() and (root/'submit.intent.json').is_file(),
              'only an acknowledged failed submitted role can be reconciled')
    intents=[r for r in records(root) if r['state']=='SUBMISSION_INTENT']
    h.require(len(intents)==1 and '--job-name='+p['scope_id'] in intents[0]['argv']
              and intents[0]['argv'][-1]==p['remote_root']+'/job.sbatch','exact canonical submission intent/argv required')
    begin=datetime.datetime.fromtimestamp(intents[0]['epoch']-60,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
    raw=run_native(site,['sacct','--user',site['user'],'--name',p['scope_id'],'--starttime',begin,'--noheader','--parsable2',
                         '--format','JobIDRaw,JobName%128,User,UID,Account,Partition,State'])
    h.require(raw['returncode']==0,'forensic accounting transport failed; claim remains quarantined')
    rows=[line.split('|') for line in raw['stdout'].splitlines() if line.strip()]
    h.require(all(len(row)==7 for row in rows),'forensic accounting shape differs')
    primary=[r for r in rows if r[0].isdigit()]
    h.require(len(primary)==1,'missing/multiple exact submitted jobs; claim remains quarantined')
    row=primary[0];h.require(row[1]==p['scope_id'] and row[2]==site['user'] and row[3]==str(os.getuid())
        and row[4:6]==['128x24','128x24'],'foreign job name/owner/account cannot be reconciled')
    if (root/'JOB.json').exists():h.require(known_job(root)['job_id']==row[0],'durable job and scheduler disagree')
    value=dict(job_id=row[0],scope_id=p['scope_id'],status='FORENSIC_EXACT_JOB_DRAIN_ONLY_NOT_SUBMITTED_OR_RELEASE_AUTHORITY',
               observation=raw,submission_intent_epoch=intents[0]['epoch'],all_fees_retained=True)
    h.write_new(root/'RECONCILED_JOB.json',value);append(root,'FORENSIC_JOB_RECONCILED_DRAIN_ONLY',job=h.pin(root/'RECONCILED_JOB.json'))
    return value


def submit(config,scope,site,root):
    p=packet(root);h.require(records(root)[-1]['state']=='STAGED','exact completed stage required')
    one_shot(root,'submit');h.require(time.time()<scope['fixed_latest_submit_epoch'] and time.time()+1200<scope['expires_epoch'],
                                    'full job and return must fit fixed calendar')
    queue=run_native(site,['squeue','--noheader','--user',site['user'],'--format','%i'])
    h.require(queue['returncode']==0 and not queue['stdout'].strip(),'single-job queue must be empty')
    argv=['sbatch','--parsable','--export=NONE','--propagate=NONE','--mail-type=NONE','--account='+site['account'],
        '--partition='+site['partition'],'--qos='+site['qos'],'--nodelist='+config['node'],'--nodes=1','--ntasks=1',
        '--cpus-per-task=1','--hint=nomultithread','--mem=8192M','--time=00:20:00','--no-requeue','--job-name='+p['scope_id'],
        '--output='+p['remote_root']+'/slurm-%j.out','--error='+p['remote_root']+'/slurm-%j.err',p['remote_root']+'/job.sbatch']
    append(root,'SUBMISSION_INTENT',argv=argv,whole_compute_CPU_reservation=600,automatic_retry=False)
    result=run_native(site,argv)
    h.write_new(root/'SUBMISSION_REPLY.json',result)
    append(root,'SUBMISSION_REPLY_OBSERVED_NOT_ACCEPTED',reply=h.pin(root/'SUBMISSION_REPLY.json'))
    h.require(result['returncode']==0,'submission ambiguous/spent; retain exact diagnostic and never retry')
    job_id=parse_job_id(result['stdout'])
    h.write_new(root/'JOB.json',dict(job_id=job_id,scope_id=p['scope_id'],submission=result))
    append(root,'SUBMITTED',job_id=job_id,job=h.pin(root/'JOB.json'));return dict(job_id=job_id,scope_id=p['scope_id'])


def acknowledge_failed_previous(registry,role,guard_path):
    paths=[p for p in registry.glob('control_*.started.json') if not p.with_name(p.name.replace('.started.','.validated.')).exists()
           and not p.with_name(p.name.replace('.started.','.failed_ack.')).exists()]
    h.require(len(paths)==1,'one exact failed action required');p=paths[0];v=h.read(h.pin(p));g=h.read(h.pin(guard_path))
    h.require(v['role']==role and v['source_sha256']==digest(__file__) and g['returncode']!=0
              and g.get('all_owned_descendants_reaped') is True and g.get('independent_guardian') is True
              and g.get('session_id')==v['command_pid'] and g.get('leader_start_ticks')==v['command_birth_ticks'],
              'exact failed and drained action guard required')
    record=dict(status='FAILED_ROLE_SPENT_DRAIN_OR_DIAGNOSIS_ONLY',started=h.pin(p),failed_guard=h.pin(guard_path),old_fees_retained=True)
    root=registry/role
    if not (root/'ROLE_FAILED_SPENT.json').exists():h.write_new(root/'ROLE_FAILED_SPENT.json',record)
    h.write_new(p.with_name(p.name.replace('.started.','.failed_ack.')),record)
    return record


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','stage','submit','ready','release','observe','collect','accept','cancel','reconcile','retire_failed','finalize'])
    parser.add_argument('--config',required=True);parser.add_argument('--role',choices=ROLES,required=True)
    for name in ['bundle','actual-review','previous-guard','failed-guard']:parser.add_argument('--'+name)
    args=parser.parse_args();c,s,site,hashes=load_config(args.config);h.require(args.role==c['role'],'only the singly funded role is admitted')
    if args.action!='finalize':
        require_outer_context();h.require(resource.getrlimit(resource.RLIMIT_CPU)[1]==action_limits(args.action)['local_CPU'],'same original native action hard cap required')
    else:resource.setrlimit(resource.RLIMIT_CPU,(2,2));signal.alarm(15)
    with canonical(c) as registry:
        if args.failed_guard:
            h.require(args.action in ['cancel','reconcile','observe','collect','retire_failed','finalize'],'failed role permits drain/diagnosis only')
            acknowledge_failed_previous(registry,args.role,args.failed_guard)
        prior=finish_previous(registry,args.previous_guard)
        if args.action=='finalize':print(json.dumps(prior,sort_keys=True));return
        root=registry/args.role
        h.require(args.action not in ['prepare','stage','submit','release','accept'] or not (root/'ROLE_FAILED_SPENT.json').exists(),'failed role remains spent')
        started=started_action(registry,args.role,args.action)
        try:
            if args.action=='prepare':value=prepare(c,s,args.role,hashes,registry)
            elif args.action=='stage':value=stage(c,site,registry,root)
            elif args.action=='submit':value=submit(c,s,site,root)
            elif args.action=='ready':value=ready(site,root)
            elif args.action=='release':value=release(site,root,args.bundle)
            elif args.action=='observe':value=observe(site,root)
            elif args.action=='collect':value=collect(site,root)
            elif args.action=='accept':value=accept(c,site,root,args.actual_review)
            elif args.action=='cancel':value=cancel(site,root)
            elif args.action=='reconcile':value=reconcile(c,site,root)
            else:value=retire_failed(c,site,root,args.actual_review)
        except BaseException as error:
            if root.is_dir():append(root,'ACTION_FAILED_RETAINED',action=args.action,error=type(error).__name__+': '+str(error))
            raise
        pending_action(started,value)
    print(json.dumps(value,sort_keys=True))


def safe_relative(value):
    path = PurePosixPath(value)
    h.require(type(value) is str and re.fullmatch(r"[A-Za-z0-9_./-]+", value) and not path.is_absolute()
              and ".." not in path.parts and path.parts and not ({".ssh", ".git", ".codex"} & set(path.parts)),
              "safe metadata-relative path required")
    return path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def native_command(argv):
    h.require(argv and argv[0] in NATIVE and all(type(x) is str and "\x00" not in x for x in argv),
              "only native administrative commands may run on login")
    return shlex.join(argv)


def site_config(value):
    site = h.read(value)
    h.require((site["host"], site["user"], site["account"], site["partition"], site["qos"])
              == ("hb.ucsc.edu", "jaguir26", "128x24", "128x24", "normal"), "verified HB association required")
    for name in ("known_hosts_file", "ssh_identity_file"):
        h.require(h.physical(site[name]).is_file(), "configured trust/identity path required")
    return site


def ssh_options(site):
    options = {"BatchMode": "yes", "StrictHostKeyChecking": "yes", "UpdateHostKeys": "no",
        "CheckHostIP": "no", "ControlMaster": "no", "ControlPath": "none", "IdentitiesOnly": "yes",
        "IdentityAgent": "none", "ForwardAgent": "no", "ClearAllForwardings": "yes",
        "PreferredAuthentications": "publickey", "PasswordAuthentication": "no", "KbdInteractiveAuthentication": "no",
        "ConnectTimeout": "10", "ConnectionAttempts": "1", "UserKnownHostsFile": site["known_hosts_file"]}
    return [item for key, value in options.items() for item in ("-o", key + "=" + value)] + ["-i", site["ssh_identity_file"]]


def run_native(site, argv, *, runner=subprocess.run):
    command = ["/usr/bin/ssh", *ssh_options(site), site["user"] + "@" + site["host"], native_command(argv)]
    # Public preexec_fn forces the reviewed fork path. There is no inner kill
    # or timeout: the actual whole-action original guardian owns both.
    result = runner(command, capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded native command output required")
    return dict(argv=argv, returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)


def run_sftp(site, commands, batch_path, *, runner=subprocess.run):
    h.require(all("\n" not in x and "\x00" not in x for x in commands), "single-line SFTP requests required")
    with Path(batch_path).open("x") as handle:
        handle.write("\n".join(commands) + "\n"); handle.flush(); os.fsync(handle.fileno())
    result = runner(["/usr/bin/sftp", "-q", "-b", str(batch_path), *ssh_options(site),
                     site["user"] + "@" + site["host"]], capture_output=True, text=True, preexec_fn=lambda: None)
    h.require(len(result.stdout.encode()) + len(result.stderr.encode()) <= 2 * 1024**2, "bounded SFTP output required")
    return dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)


def append(root, state, **fields):
    records = sorted(root.glob("record_*.json"))
    value = dict(state=state, epoch=time.time(), previous=h.pin(records[-1]) if records else None, **fields)
    path = root / ("record_%04d.json" % len(records)); h.write_new(path, value)
    return value


def records(root):
    paths = sorted(root.glob("record_*.json")); result = []; previous = None
    for path in paths:
        value = h.read(h.pin(path)); h.require(value["previous"] == previous, "canonical journal chain differs")
        result.append(value); previous = h.pin(path)
    return result


def one_shot(root, name):
    path = root / (name + ".intent.json")
    h.write_new(path, dict(status="INTENT_NOT_SUCCESS", operation=name, epoch=time.time()))
    return path


def action_limits(action):
    if action == 'reconcile': return dict(local_CPU=3,wall=120)
    if action == "prepare": return dict(local_CPU=4, wall=120)
    if action == "retire_failed": return dict(local_CPU=3, wall=120)
    return ACTION_ENVELOPE[action]


def require_outer_context():
    values = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines() if ":" in line)
    h.require(os.getpid() == os.getsid(0) == os.getpgrp()
              and values["NoNewPrivs"].strip() == "1" and values["Seccomp"].strip() == "2",
              "each native action requires the actual original outer guardian")


def started_action(registry, role, action):
    index = len(list(registry.glob("control_*.started.json")))
    path = registry / ("control_%04d.started.json" % index)
    h.write_new(path, dict(status="ACTION_STARTED_NOT_SUCCESS", role=role, action=action,
        created_epoch=time.time(), command_pid=os.getpid(), command_birth_ticks=h.process_birth_ticks(),
        source_sha256=digest(Path(__file__).absolute()), limits=action_limits(action)))
    return path


def pending_action(started, value):
    value_start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.write_new(path, dict(status="INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS",
        **{key: item for key, item in value_start.items() if key != "status"}, result=value))


def finish_previous(registry, guard_path):
    pending = sorted(x for x in registry.glob("control_*.started.json")
                     if not x.with_name(x.name.replace(".started.json", ".validated.json")).exists()
                     and not x.with_name(x.name.replace(".started.json", ".failed_ack.json")).exists())
    if not pending:
        h.require(guard_path is None, "no pending action matches supplied guard")
        return None
    h.require(len(pending) == 1 and guard_path is not None, "actual prior outer guardian required before another action")
    started = pending[0]; start = h.read(h.pin(started))
    path = started.with_name(started.name.replace(".started.json", ".pending.json"))
    h.require(path.is_file(), "prior action did not complete internal publication; retain failed guard/claim and stop")
    value = h.read(h.pin(path)); guard_pin = h.pin(guard_path); guard = h.read(guard_pin)
    h.require(all(value[key] == item for key, item in start.items() if key != "status")
              and value["source_sha256"] == digest(Path(__file__).absolute()), "pending action source/identity changed")
    limit = value["limits"]
    h.require(type(guard["returncode"]) is type(guard["command_returncode"]) is int
              and guard["returncode"] == guard["command_returncode"] == 0
              and guard.get("cap_reason") is None and type(guard["CPU_limit"]) is int and guard["CPU_limit"] == limit["local_CPU"]
              and type(guard["aggregate_CPU_seconds"]) in (int, float) and math.isfinite(guard["aggregate_CPU_seconds"])
              and 0 <= guard["aggregate_CPU_seconds"] < limit["local_CPU"]
              and type(guard["complete_lifecycle_wall_seconds"]) in (int, float)
              and math.isfinite(guard["complete_lifecycle_wall_seconds"])
              and 0 <= guard["complete_lifecycle_wall_seconds"] <= limit["wall"]
              and guard.get("guardian_forced_monitor_stop") is False
              and all(guard.get(x) is True for x in ("all_owned_descendants_reaped", "independent_guardian", "kernel_escape_filter",
                  "orphan_subreaper", "guardian_included_in_CPU", "inherited_waited_history_included_once"))
              and guard["session_id"] == value["command_pid"] and guard["leader_start_ticks"] == value["command_birth_ticks"]
              and h.strict_json(guard["stdout"]) == value["result"], "actual prior whole-action guard failed or differs")
    h.write_new(started.with_name(started.name.replace(".started.json", ".validated.json")),
                dict(status="ACTUAL_ACTION_GUARD_PASSED", started=h.pin(started), pending=h.pin(path), guard=guard_pin))
    if value["action"] == "accept":
        root = registry / value["role"]; accepted = dict(value["result"], status="ACCEPTED_COMPLETE_FROZEN525_NUMERICAL_ROLE",
                                          actual_accept_action_guard=guard_pin)
        h.write_new(root / "ACCEPTED.json", accepted); append(root, "ACCEPTED", accepted=h.pin(root / "ACCEPTED.json"), claim_released=True)
    return dict(status="PRIOR_ACTION_GUARD_VALIDATED", action=value["action"], guard=guard_pin)


@contextlib.contextmanager
def canonical(config):
    parent = h.physical(config["registry"]); parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(parent / ".controller.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield parent
    finally:
        os.close(descriptor)


def packet(root):
    first = records(root)[0]
    h.require(first["state"] == "PREPARED" and first["packet"]["path"] == str(root / "PACKET.json"),
              "original immutable packet pin required")
    return h.read(first["packet"])


def stage(config, site, registry, root):
    p = packet(root); one_shot(root, "stage")
    h.require(not any(x["state"] in {"SUBMITTED", "AMBIGUOUS_SPENT", "RELEASED"}
                      for other in registry.iterdir() if other.is_dir() and other != root for x in records(other)[-1:]),
              "another canonical role may still own a job")
    lock = config["remote_namespace"] + "/qualification.lock"
    append(root, "STAGING_INTENT", remote_claim=lock)
    for argv in (["mkdir", "-p", "-m", "700", config["remote_namespace"]], ["mkdir", "-m", "700", lock]):
        result = run_native(site, argv); h.require(result["returncode"] == 0, "native exclusive staging/claim failed; claim retained")
    spent = run_native(site, ["mkdir", "-m", "700", config["remote_namespace"] + "/ROLE_" + p["role"] + "_SPENT"])
    if spent["returncode"] != 0:
        run_native(site, ["rmdir", lock])  # Our just-created, still-empty private claim only.
        raise ValueError("canonical remote role already spent; no cross-server replay")
    h.require(run_native(site, ["mkdir", "-m", "700", p["remote_root"]])["returncode"] == 0, "new remote role namespace required")
    commands = []
    directories={PurePosixPath(p) for p in ['package','package/pricefm_hb','release','result','tmp','science']}
    for row in p['uploads']:
        relative=safe_relative(row['relative'])
        directories.update(parent for parent in relative.parents if str(parent)!='.')
    for directory in sorted(directories,key=lambda value:(len(value.parts),str(value))):
        directory=str(directory)
        commands.append("mkdir " + safe_path(p["remote_root"] + "/" + directory))
    marker = root / "CLAIM_MARKER"; marker.write_bytes(b"")
    commands.append("put " + safe_path(str(marker)) + " " + lock + "/OWNED_" + p["scope_id"])
    for row in p["uploads"]:
        h.require(digest(row["local"]) == row["sha256"], "local upload bytes changed")
        commands.append("put " + safe_path(row["local"]) + " " + safe_path(p["remote_root"] + "/" + row["relative"]))
    transfer = run_sftp(site, commands, root / "stage.sftp")
    h.require(transfer["returncode"] == 0, "partial or failed SFTP stage; no retry/submission allowed")
    expected = {p["remote_root"] + "/" + x["relative"]: x["sha256"] for x in p["uploads"]}
    expected[config["cached_python"]] = config["cached_python_sha256"]
    hashes = run_native(site, ["sha256sum", *sorted(expected)])
    h.require(hashes["returncode"] == 0, "native complete stage hash observation failed")
    actual = {}
    for line in hashes["stdout"].splitlines():
        parts = line.split(None, 1)
        h.require(len(parts) == 2 and re.fullmatch("[0-9a-f]{64}", parts[0]) and parts[1] not in actual,
                  "complete unique native staged hash rows required")
        actual[parts[1]] = parts[0]
    h.require(actual == expected, "partial/changed stage or cached Python identity; no submission")
    h.write_new(root/'STAGE_CHECKSUM.json',hashes);checksum=h.pin(root/'STAGE_CHECKSUM.json')
    append(root, "STAGED", transfer=transfer,checksum=checksum)
    return dict(status="STAGED_NOT_SUBMITTED", scope_id=p["scope_id"],checksum=checksum)


def parse_job_id(raw):
    h.require(type(raw) is str and re.fullmatch(r"[1-9][0-9]*(?:;[A-Za-z0-9_.-]+)?\n?", raw), "ambiguous sbatch reply")
    return raw.strip().split(";", 1)[0]


def validate_ready(ready, p, job_id):
    h.require(ready["status"] == "READY_SOURCE_BOUND_COMPUTE_METADATA" and ready["scope_id"] == p["scope_id"]
              and ready["job_id"] == job_id and ready["spec_sha256"] == p["spec_sha256"]
              and ready["node"] == "node-13" and len(ready["affinity"]) == 1
              and ready["cpus_per_task"] == 1 and type(ready["models"]) is int and ready["models"] == 0
              and ready["sources"] == p["sources"] and ready["role"] == p["role"],
              "stale/foreign/malformed READY cannot release payload")


def ready(site, root):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); one_shot(root, "ready")
    # One paid observation only. Wait outside this guarded action, then fetch
    # once; protected sleeps consume guardian stop-window/accounting headroom.
    result = run_native(site, ["test", "-f", p["remote_root"] + "/READY.json"])
    if result["returncode"] == 1:
        prior = next((x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED"), None)
        diagnostic = h.read(prior) if prior is not None else None
        error = None
        if diagnostic is None or not diagnostic["terminal"]:
            try:
                # This diagnostic consumes one of the same three throttled
                # accounting intents, within this unchanged six-CPU action.
                diagnostic = observe(site, root)
            except BaseException as exc:
                error = type(exc).__name__ + ": " + str(exc)
        append(root, "READY_ABSENT_DIAGNOSTIC", accounting=diagnostic,
               accounting_error=error, ready_observations=1, automatic_retry=False)
        raise ValueError("READY absent after one observation; diagnostic retained; no automatic retry")
    h.require(result["returncode"] == 0, "READY observation transport failed; no automatic retry")
    one_shot(root, "ready_fetch")
    result = run_sftp(site, ["get " + p["remote_root"] + "/READY.json " + safe_path(str(root / "READY.json"))], root / "ready.sftp")
    h.require(result["returncode"] == 0, "READY transfer incomplete")
    value = h.read(h.pin(root / "READY.json")); validate_ready(value, p, job["job_id"])
    append(root, "READY_VALIDATED", ready=h.pin(root / "READY.json"))
    return value


def release(site, root, bundle):
    p = packet(root); job = h.read(h.pin(root / "JOB.json")); ready_value = h.read(h.pin(root / "READY.json"))
    validate_ready(ready_value, p, job["job_id"])
    validate_local_release(root,bundle)
    release_path = h.physical(bundle) / "RELEASE.json"; value = h.read(h.pin(release_path))
    h.require(value["status"] == "ROOT_RELEASED_STARTUP_BATCH_ROLE" and value["scope_id"] == p["scope_id"]
              and value["job_id"] == job["job_id"] and value["ready_sha256"] == digest(root / "READY.json")
              and value["spec_sha256"] == p["spec_sha256"] and value["role"] == p["role"], "actual root READY-bound release required")
    commands = []
    for row in value["files"]:
        relative = str(safe_relative(row["relative"])); local = h.physical(bundle) / relative
        h.require(local.parent == h.physical(bundle) and digest(local) == row["sha256"], "flat exact release metadata required")
        commands.append("put " + safe_path(str(local)) + " " + p["remote_root"] + "/release/" + relative)
    h.require(all(x["relative"] not in {"RELEASE.json", "RELEASE.json.partial"} for x in value["files"]), "reserved release publication filename")
    commands.append("put " + safe_path(str(release_path)) + " " + p["remote_root"] + "/release/RELEASE.json.partial")
    commands.append("rename " + p["remote_root"] + "/release/RELEASE.json.partial " + p["remote_root"] + "/release/RELEASE.json")
    one_shot(root, "release"); append(root, "RELEASE_INTENT", release=h.pin(release_path))
    result = run_sftp(site, commands, root / "release.sftp"); h.require(result["returncode"] == 0, "partial release retained; no retry")
    append(root, "RELEASED", release=h.pin(release_path), transfer=result)
    return dict(status="RELEASED", job_id=job["job_id"])


def CPU_seconds(text):
    match = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d\d):(\d\d(?:\.\d+)?)", text)
    h.require(match is not None, "complete Slurm TotalCPU required")
    days, hours, minutes, seconds = match.groups()
    value = int(days or 0) * 86400 + int(hours or 0) * 3600 + int(minutes) * 60 + float(seconds)
    h.require(math.isfinite(value) and value >= 0 and int(minutes) < 60 and float(seconds) < 60, "invalid Slurm CPU")
    return value


def parse_accounting(raw, job_id, scope_id):
    lines = [line.split("|") for line in raw.splitlines() if line.strip()]
    h.require(all(len(x) == 11 and x[0] in {job_id, job_id + ".batch", job_id + ".extern"} for x in lines)
              and len({x[0] for x in lines}) == len(lines), "foreign/duplicate/partial accounting row")
    rows = [x for x in lines if x[0] == job_id]
    h.require(len(rows) == 1, "one complete canonical primary Slurm row required")
    x = rows[0]; state = x[1].split()[0]
    h.require(x[6] == scope_id and x[7:9] == ["128x24", "128x24"] and x[5] == "1", "foreign job/account/allocation")
    memory = re.fullmatch(r"([0-9.]+)([KMG])([cn])?", x[9])
    h.require(memory is not None and float(memory[1]) * {"K": 1 / 1024, "M": 1, "G": 1024}[memory[2]] == 8192,
              "actual primary requested memory differs from8GiB")
    cpu = CPU_seconds(x[3]); elapsed = int(x[4]); h.require(cpu <= 600 and 0 <= elapsed <= 1200, "whole batch reservation exceeded")
    required = {job_id, job_id + ".batch"}; actual = {row[0] for row in lines}
    for row in lines:
        h.require(re.fullmatch(r"[0-9]+:[0-9]+", row[2]) and 0 <= int(row[4]) <= 1200
                  and int(row[5]) in (0, 1) and CPU_seconds(row[3]) <= 600, "invalid step/accounting bound")
    complete_rows = required <= actual
    primary_consistent = cpu + .01 >= max((CPU_seconds(row[3]) for row in lines), default=0.)
    complete = complete_rows and primary_consistent and all(row[1].split()[0] == "COMPLETED" and row[2] == "0:0" for row in lines)
    terminal = complete_rows and primary_consistent and all(row[1].split()[0] in TERMINAL for row in lines)
    return dict(job_id=job_id, state=state, exit_code=x[2], canonical_primary_CPU_seconds=cpu,
        elapsed_seconds=elapsed, complete=complete, terminal=terminal, missing_required_rows=sorted(required - actual),
        MaxRSS_raw={row[0]: row[10] or None for row in lines}, unknown_MaxRSS_is_not_zero=True,
        primary_CPU_consistent_with_each_step=primary_consistent,
        raw_sacct=raw, step_rows_diagnostic_not_added=True, primary_charge_counted_once=True)


def observe(site, root):
    p = packet(root); job = known_job(root); past = records(root)
    count = len(list(root.glob("observe_*.intent.json")))
    h.require(count < 3, "finite accounting polls exhausted")
    one_shot(root, "observe_%02d" % count)
    intents = sorted(root.glob("observe_*.intent.json"))
    if len(intents) > 1:
        h.require(h.read(h.pin(intents[-1]))["epoch"] - h.read(h.pin(intents[-2]))["epoch"] >= 300,
                  "minimum300seconds between paid Slurm accounting intents, including failures")
    result = run_native(site, ["sacct", "--jobs", job["job_id"], "--noheader", "--parsable2", "--format",
        "JobIDRaw,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,JobName%128,Account,Partition,ReqMem,MaxRSS"])
    h.require(result["returncode"] == 0, "accounting observation failed")
    value = parse_accounting(result["stdout"], job["job_id"], p["scope_id"])
    path = root / ("accounting_%04d.json" % sum(x["state"] == "OBSERVED" for x in past)); h.write_new(path, value)
    append(root, "OBSERVED", accounting=h.pin(path))
    return value


def collect(site, root):
    p = packet(root); job = known_job(root)
    account = next(h.read(x["accounting"]) for x in reversed(records(root)) if x["state"] == "OBSERVED")
    h.require(account["terminal"], "known terminal job required before one-shot return")
    one_shot(root, "collect")
    diagnostics = root / "diagnostics"; diagnostics.mkdir(mode=0o700)
    # Optional raw logs remain useful even if the worker failed before sealing.
    logs = run_sftp(site, ["-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".out "
                           + safe_path(str(diagnostics / "slurm.stdout")),
                         "-get " + p["remote_root"] + "/slurm-" + job["job_id"] + ".err "
                           + safe_path(str(diagnostics / "slurm.stderr"))], root / "diagnostics.sftp")
    append(root, "DIAGNOSTICS_FETCHED", transport=logs,
           files=[h.pin(x) for x in sorted(diagnostics.iterdir()) if x.is_file()])
    raw = root / "returned"; raw.mkdir(mode=0o700)
    transfer = run_sftp(site, ["get " + p["remote_root"] + "/result/RETURN_MANIFEST.json "
                              + safe_path(str(raw / "RETURN_MANIFEST.json"))], root / "manifest.sftp")
    h.require(transfer["returncode"] == 0, "manifest return failed; no retry")
    manifest = h.read(h.pin(raw / "RETURN_MANIFEST.json")); validate_manifest(manifest, p, job["job_id"])
    commands = []
    for row in manifest["files"]:
        path = raw / row["relative"]; path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        commands.append("get " + p["remote_root"] + "/result/" + row["relative"] + " " + safe_path(str(path)))
    transfer = run_sftp(site, commands, root / "return.sftp"); h.require(transfer["returncode"] == 0, "partial return retained; no retry")
    for row in manifest["files"]:
        path = raw / row["relative"]
        h.require(path.is_file() and not path.is_symlink() and path.stat().st_size == row["bytes"]
                  and digest(path) == row["sha256"], "returned metadata bytes/hash differ")
    append(root, "RETURNED", manifest=h.pin(raw / "RETURN_MANIFEST.json"), full_return_hash_verified=True)
    return dict(status="COMPLETE_HASH_VERIFIED_RETURN_NOT_YET_ACCEPTED", manifest=h.pin(raw / "RETURN_MANIFEST.json"))


def cancel(site, root):
    p = packet(root); job = known_job(root); one_shot(root, "cancel")
    append(root, "CANCEL_INTENT", job_id=job["job_id"], compute_fee_retained=600)
    value = run_native(site, ["scancel", "--user", site["user"], "--name", p["scope_id"], job["job_id"]])
    h.require(value["returncode"] == 0, "own exact-job cancellation unknown; claim remains")
    append(root, "CANCEL_REQUESTED", result=value)
    return dict(status="CANCEL_REQUESTED_NOT_TERMINAL_PROOF", job_id=job["job_id"])


def retire_failed(config, site, root, actual_review):
    p = packet(root); job = known_job(root); one_shot(root, "retire_failed")
    account_pin = next(x["accounting"] for x in reversed(records(root)) if x["state"] == "OBSERVED")
    account = h.read(account_pin)
    h.require(account["terminal"] and not account["complete"], "failed terminal primary accounting required")
    peer = h.read(h.pin(actual_review))
    h.require(peer["status"] == "PASS_REVIEWED_FROZEN525_FAILED_ROLE_RETIREMENT"
              and peer["job_id"] == job["job_id"] and peer["accounting"] == account_pin,
              "actual failed-role retirement review required")
    queue = run_native(site, ["squeue", "--noheader", "--user", site["user"], "--format", "%i"])
    h.require(queue["returncode"] == 0 and job["job_id"] not in queue["stdout"].split(), "failed job still queued/unknown")
    lock = config["remote_namespace"] + "/qualification.lock"
    for argv in (["test", "-f", lock + "/OWNED_" + p["scope_id"]], ["rm", "--", lock + "/OWNED_" + p["scope_id"]], ["rmdir", lock]):
        h.require(run_native(site, argv)["returncode"] == 0, "failed claim release unknown; no retry")
    append(root, "FAILED_RETIRED_NO_RETRY", accounting=account_pin, independent_review=h.pin(actual_review),
           all_fees_and_partial_artifacts_retained=True, same_role_resubmission_forbidden=True)
    return dict(status="FAILED_RETIRED_NO_RETRY", job_id=job["job_id"])


if __name__=='__main__':main()
