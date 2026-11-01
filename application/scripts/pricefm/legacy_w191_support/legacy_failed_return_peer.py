"""Independent bounded review of a collected W191 zero-update diagnostic.

No native commands, R, array interpretation, input-state access, fit or score is
performed. Exact returned binary files are streamed only under the fresh
manifest/config/job/collection-bound ROOT hash-only grant. Scientific success
and failed diagnostic evidence use distinct results; neither grants a pilot.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import signal
import stat
import sys
import time

MAX_FILE=16*1024**2
MAX_TOTAL=64*1024**2
MAX_FILES=256
ROLE='ZERO_UPDATE_BRIDGE'
SOURCE_KIND='UNCHANGED_R157_TRACER_R182_FROZEN525_NUMERICAL_OWNER'
LIMITS=dict(beta_posterior_sd_rms=1e-4,covariance_whitened_rms=1e-4,elbo_relative=1e-8,
            predictor_rms=1e-6,rhs_joint_log_rates=1e-6,rhs_start_log_precision=1e-6,sigma_relative=1e-6)
RHS_NUMBERS={'unit_iterations','dispersed_iterations','unit_residual','dispersed_residual'}
RHS_BOOLEANS={'unit_converged','dispersed_converged'}
ACCOUNT_FIELDS='JobIDRaw,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,JobName%128,Account,Partition,ReqMem,MaxRSS'
TERMINAL={'COMPLETED','FAILED','CANCELLED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','PREEMPTED','BOOT_FAIL'}
READS={}


def check(ok,message):
    if not ok:raise ValueError(message)


def integer(x,want=None):
    return type(x) is int and (want is None or x==want)


def number(x):
    return type(x) in (int,float) and math.isfinite(x)


def strict(raw):
    def pairs(items):
        out={}
        for k,v in items:
            check(k not in out,'duplicate metadata key');out[k]=v
        return out
    def bad(x):raise ValueError('nonfinite metadata '+x)
    def real(x):
        value=float(x);check(math.isfinite(value),'nonfinite metadata exponent');return value
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=bad,parse_float=real)


def physical(path):
    p=Path(path)
    check(p.is_absolute() and '..' not in p.parts and not any(x.is_symlink() for x in (p,*p.parents)),
          'absolute physical non-symlink path')
    return p


def stable(path,sha=None,size=None,*,return_bytes=True,limit=MAX_FILE):
    p=physical(path);fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    digest=hashlib.sha256();parts=[];count=0
    with os.fdopen(fd,'rb') as f:
        a=os.fstat(f.fileno())
        check(stat.S_ISREG(a.st_mode) and a.st_uid in {0,os.getuid()} and a.st_nlink==1 and a.st_size<=limit,
              'bounded owned single-link regular bytes')
        while True:
            chunk=f.read(65536)
            if not chunk:break
            count+=len(chunk);check(count<=limit,'bounded streamed return')
            digest.update(chunk)
            if return_bytes:parts.append(chunk)
        b=os.fstat(f.fileno())
    fingerprint=lambda x:(x.st_dev,x.st_ino,x.st_uid,x.st_mode,x.st_nlink,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
    check(fingerprint(a)==fingerprint(b)==fingerprint(p.stat()) and count==a.st_size
          and (size is None or integer(size) and count==size) and (sha is None or digest.hexdigest()==sha),
          'stable current exact returned bytes/hash/length')
    READS[str(p)]=dict(path=str(p),sha256=digest.hexdigest(),bytes=count,device=a.st_dev,inode=a.st_ino,uid=a.st_uid)
    return b''.join(parts) if return_bytes else None


def pin(path):
    p=physical(path);stable(p,return_bytes=False)
    return dict(path=str(p),sha256=READS[str(p)]['sha256'])


def linked(value):
    check(type(value) is dict and set(value)=={'path','sha256'} and type(value['sha256']) is str
          and re.fullmatch('[0-9a-f]{64}',value['sha256']) and Path(value['path']).suffix=='.json', 'strict metadata pin')
    return strict(stable(value['path'],value['sha256']))


def local(path):
    check(Path(path).suffix=='.json','metadata JSON only')
    return strict(stable(path))


def write_new(path,value):
    p=physical(path);check(p.parent.resolve(strict=True)==p.parent,'existing physical output parent')
    with os.fdopen(os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),'w') as f:
        json.dump(value,f,indent=2,sort_keys=True,allow_nan=False);f.write('\n');f.flush();os.fsync(f.fileno())


def source_support(publication_pin,review_pin):
    pub=linked(publication_pin);review=linked(review_pin)
    check(pub.get('status')=='PASS_PUBLISHED_LEGACY_NODE13_SUPPORT_SOURCE'
          and review.get('status')=='PASS_REVIEWED_LEGACY_NODE13_SUPPORT_SOURCE'
          and pub['independent_review']==review_pin and pub['source_files']==review['source_files']
          and re.fullmatch('[0-9a-f]{40}',pub['commit']) and pub['remote_readback']==pub['commit']
          and pub['branch']!='main','actual independently reviewed separate feature publication')
    own=pin(Path(__file__).absolute())
    check(pub['source_files'].get('legacy_failed_return_peer.py')==own['sha256'],'this exact independent return peer source')
    dependency=Path(__file__).absolute().with_name('legacy_tail_peer.py')
    stable(dependency,pub['source_files']['legacy_tail_peer.py'])
    spec=importlib.util.spec_from_file_location('_published_legacy_metadata_peer',dependency)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    return m,pub,review,own


def seconds(text):
    check(type(text) is str and re.fullmatch(r'(?:(\d+)-)?(?:\d+:)?\d{2}:\d{2}(?:\.\d+)?',text),'typed SACCT CPU clock')
    days=0
    if '-' in text:
        day,text=text.split('-',1);days=int(day)
    parts=text.split(':');h,m,s=(parts if len(parts)==3 else ['0',*parts])
    check(int(m)<60 and float(s)<60,'valid SACCT minute/second fields')
    return days*86400+int(h)*3600+int(m)*60+float(s)


def parse_accounting(raw,job_id,scope_id):
    rows=[line.split('|') for line in raw.splitlines() if line.strip()]
    check(rows and all(len(x)==11 and x[0] in {job_id,job_id+'.batch',job_id+'.extern'} for x in rows)
          and len({x[0] for x in rows})==len(rows),'exact complete unique primary/batch/optional extern accounting')
    primary=[x for x in rows if x[0]==job_id];check(len(primary)==1,'one canonical primary')
    x=primary[0];state=x[1].split()[0]
    check(x[6]==scope_id and x[7:9]==['128x24','128x24'] and x[5]=='1','exact allocated role/account/partition')
    memory=re.fullmatch(r'([0-9.]+)([KMG])([cn])?',x[9])
    check(memory and float(memory[1])*{'K':1/1024,'M':1,'G':1024}[memory[2]]==8192,'exact8GiB request')
    cpu=seconds(x[3]);check(cpu<=600 and re.fullmatch('[0-9]+',x[4]) and 0<=int(x[4])<=1200,'whole primary reservation')
    for row in rows:
        check(re.fullmatch('[0-9]+:[0-9]+',row[2]) and re.fullmatch('[0-9]+',row[4]) and 0<=int(row[4])<=1200
              and row[5] in {'0','1'} and seconds(row[3])<=600,'bounded typed step accounting')
    present={row[0] for row in rows};complete_rows={job_id,job_id+'.batch'}<=present
    consistent=cpu+.01>=max(seconds(row[3]) for row in rows)
    complete=complete_rows and consistent and all(row[1].split()[0]=='COMPLETED' and row[2]=='0:0' for row in rows)
    terminal=complete_rows and consistent and all(row[1].split()[0] in TERMINAL for row in rows)
    return dict(job_id=job_id,state=state,exit_code=x[2],canonical_primary_CPU_seconds=cpu,elapsed_seconds=int(x[4]),
                complete=complete,terminal=terminal,missing_required_rows=sorted({job_id,job_id+'.batch'}-present),
                MaxRSS_raw={row[0]:row[10] or None for row in rows},unknown_MaxRSS_is_not_zero=True,
                primary_CPU_consistent_with_each_step=consistent,raw_sacct=raw,step_rows_diagnostic_not_added=True,
                primary_charge_counted_once=True)


def journal(root):
    files=sorted(root.glob('record_*.json'));check(len(files)<=256,'bounded canonical journal')
    result=[];previous=None
    for path in files:
        row=local(path);check(row['previous']==previous,'canonical journal link conservation')
        result.append(row);previous=pin(path)
    return result


def context(config_path,collect_guard_path,publication_pin,review_pin):
    m,pub,review,own=source_support(publication_pin,review_pin)
    cfg=local(config_path);parent=linked(cfg['scope']);now=time.time()
    check(cfg['schema']=='r182_numerical_batch_config_v1' and cfg['role']==ROLE and cfg['node']=='node-13'
          and parent['status']=='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE' and parent['roles']==[ROLE]
          and parent['issued_epoch']<=now<parent['expires_epoch'] and integer(parent['compute_CPU_reservation'],600)
          and parent['automatic_retry'] is False and parent['requeue'] is False,'fresh exact W191 zero-update role')
    check(integer(parent.get('administrative_allocations',{}).get('independent_complete_return6'),6),
          'the original normal234 retains this one paid independent complete/failure return6')
    m.published_w191(cfg)
    # Imports only the exact source closure just rehashed by the independent peer.
    sys.path.insert(0,str(m.SOURCE.parent))
    from pricefm_hb import numerical_stage_contract as contract
    check(Path(contract.__file__).absolute()==m.SOURCE/'numerical_stage_contract.py',
          'exact rehashed W191 contract import path')
    for name,value in sys.modules.copy().items():
        if name.startswith('pricefm_hb') and getattr(value,'__file__',None):
            check(Path(value.__file__).absolute().is_relative_to(m.SOURCE),'no foreign scientific/control package import')
    contract.validate_role(ROLE,cfg['role_limits'])
    check(contract.LIMITS==LIMITS and contract.MAX_RETURN_FILE==MAX_FILE and contract.MAX_RETURN_TOTAL==MAX_TOTAL
          and contract.MAX_RETURN_FILES==MAX_FILES,'unchanged exact mathematical and return bounds')
    canonical=linked(cfg['canonical_authority'])
    check(canonical['status']=='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG'
          and canonical['binding']=={k:v for k,v in cfg.items() if k!='canonical_authority'},'whole exact current config binding')
    base=physical(parent['allowed_metadata_output_root']);root=physical(cfg['registry'])/ROLE
    check(str(base).startswith('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa/Legacy_NODE13_')
          and root==base/'canonical_registry'/ROLE and base.resolve(strict=True)==base
          and base.stat().st_uid==os.getuid() and base.stat().st_mode&0o077==0,'one private canonical legacy root')
    packet=local(root/'PACKET.json');job=local(root/'JOB.json');past=journal(root)
    check(packet['role']==ROLE and re.fullmatch('r182-bridge-[0-9a-f]{20}',packet['scope_id'])
          and job['scope_id']==packet['scope_id'] and re.fullmatch('[1-9][0-9]*',job['job_id'])
          and packet['remote_root']==cfg['remote_namespace']+'/'+packet['scope_id']
          and packet['source_publication']==cfg['publication'] and packet['source_review']==cfg['source_review'],
          'actual same unique W191 job/packet/namespace')
    known=linked(cfg['known_jobs_registry']);known_rows=known.get('jobs');check(type(known_rows) is list,'typed complete registry')
    expected_prior=[dict(job_id=x['job_id'],job_name=x['job_name'],terminal=x.get('state') in TERMINAL) for x in known_rows]
    check(type(known_rows) is list and len(known_rows)>=17 and len({x['job_id'] for x in known_rows})==len(known_rows)
          and cfg['known_prior_jobs']==expected_prior and all(x['terminal'] for x in expected_prior)
          and job['job_id'] not in {x['job_id'] for x in known_rows},'entire original current terminal registry and genuinely new job')
    source_pub=linked(cfg['publication'])
    check(packet['sources']=={name:dict(path=packet['remote_root']+'/package/pricefm_hb/'+name,sha256=sha)
          for name,sha in source_pub['source_files'].items()},'exact staged W191 compute-source map')
    specs=local(root/'packet/SPEC.json')
    check(pin(root/'packet/SPEC.json')['sha256']==packet['spec_sha256'] and specs['sources']==packet['sources']
          and specs['role']==ROLE and specs['scope_id']==packet['scope_id'] and specs['node']=='node-13'
          and specs['source_commit']==m.COMMIT and re.fullmatch('[0-9a-f]{32}',specs['nonce'])
          and specs['scope_id']=='r182-bridge-'+specs['nonce'][:20] and specs['known_prior_jobs']==cfg['known_prior_jobs']
          and specs['science']=={name:dict(path=packet['remote_root']+'/science/'+name,sha256=ref['sha256'])
              for name,ref in cfg['scientific_sources'].items()},'exact current staged source/spec/science closure')
    returned=[x for x in past if x['state']=='RETURNED'];observed=[x for x in past if x['state']=='OBSERVED']
    check(returned and observed and returned[-1].get('full_return_hash_verified') is True,'actual terminal observation and complete collected return journal')
    manifest_pin=returned[-1]['manifest'];account_pin=observed[-1]['accounting'];account=linked(account_pin)
    check(manifest_pin==pin(root/'returned/RETURN_MANIFEST.json'),'actual canonical returned manifest')
    raw=linked(account['raw_observation'])
    check(raw==dict(argv=['sacct','--jobs',job['job_id'],'--noheader','--parsable2','--format',ACCOUNT_FIELDS],
          returncode=0,stdout=account['raw_sacct'],stderr=''),'exact actual native primary accounting observation')
    parsed=parse_accounting(raw['stdout'],job['job_id'],packet['scope_id'])
    check(all(account.get(k)==v for k,v in parsed.items()) and parsed['terminal'],'independent terminal/accounting/count-once validation')
    guard_value=local(collect_guard_path);m.guard(guard_value,6,300)
    expected=dict(status='COMPLETE_HASH_VERIFIED_RETURN_NOT_YET_ACCEPTED',manifest=manifest_pin)
    check(strict(guard_value['stdout'])==expected,'actual successful complete collect outerH6 stdout')
    candidates=[]
    for started in Path(cfg['registry']).glob('control_*.started.json'):
        start=local(started)
        if start.get('action')=='collect' and start.get('command_pid')==guard_value['session_id']:
            candidates.append((started,start))
    check(len(candidates)==1,'one exact collection action journal')
    started,start=candidates[0];pending=local(started.with_name(started.name.replace('.started.json','.pending.json')))
    check(start['status']=='ACTION_STARTED_NOT_SUCCESS' and start['role']==ROLE
          and start['source_sha256']==source_pub['source_files']['numerical_batch.py']
          and start['limits']==dict(local_CPU=6,remote_unknown_fee=6,wall=300,maximum_calls=1)
          and start['command_birth_ticks']==guard_value['leader_start_ticks']
          and pending['status']=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
          and all(pending.get(k)==v for k,v in start.items() if k!='status') and pending['result']==expected,
          'actual exact-source collect PID/birth/pending/guard chain')
    return dict(m=m,publication=pub,source_review=review,own=own,cfg=cfg,parent=parent,base=base,root=root,packet=packet,
                job=job,past=past,spec=specs,contract=contract,manifest_pin=manifest_pin,account_pin=account_pin,account=parsed,
                collect_guard=pin(collect_guard_path),config=pin(config_path))


def verify_manifest_and_bytes(c,opaque_grant_pin,publication_pin,review_pin):
    manifest=linked(c['manifest_pin']);packet=c['packet'];job=c['job'];root=c['root']/'returned';now=time.time()
    check(manifest.get('schema')=='r182_frozen525_numerical_return_manifest_v1'
          and manifest['scope_id']==packet['scope_id'] and manifest['job_id']==job['job_id']
          and type(manifest.get('complete_success')) is bool and integer(manifest.get('production_fits'),0)
          and integer(manifest.get('pilot_fits'),0),'exact sealed worker manifest identity and nonproduction purpose')
    allowed,binary=c['contract'].output_inventory(ROLE);allowed=set(allowed)|{'numerical/FAILED.json'}
    rows=manifest.get('files');check(type(rows) is list and 1<=len(rows)<=MAX_FILES,'finite exact return rows')
    mapping={};total=0
    for row in rows:
        check(type(row) is dict and set(row)=={'relative','bytes','sha256'},'closed return row')
        rel=row['relative'];p=PurePosixPath(rel)
        check(type(rel) is str and rel in allowed and not p.is_absolute() and '..' not in p.parts and str(p)==rel
              and rel not in mapping and integer(row['bytes']) and 0<=row['bytes']<=MAX_FILE
              and type(row['sha256']) is str and re.fullmatch('[0-9a-f]{64}',row['sha256']),'closed unique producer return allowlist/hash/size')
        mapping[rel]=row;total+=row['bytes']
        if Path(rel).suffix.lower() in {'.rds','.bin'}:check(rel in binary,'only exact original whitelisted output binaries')
    check(total<=MAX_TOTAL and 'RESULT.json' in mapping,'complete finite return envelope')
    if manifest['complete_success']:
        check(set(mapping)==c['contract'].output_inventory(ROLE)[0],'successful return requires original complete inventory')
    opaque=[row for row in rows if row['relative'] in binary]
    grant=linked(opaque_grant_pin)
    check(grant.get('status')=='ROOT_AUTHORIZED_W191_EXACT_RETURN_OPAQUE_BYTE_HASH_ONLY'
          and grant.get('config')==c['config'] and grant.get('scope')==c['cfg']['scope']
          and grant.get('job')==pin(c['root']/'JOB.json') and grant.get('packet')==pin(c['root']/'PACKET.json')
          and grant.get('return_manifest')==c['manifest_pin'] and grant.get('actual_collect_guard')==c['collect_guard']
          and grant.get('support_publication')==publication_pin and grant.get('support_source_review')==review_pin
          and grant.get('peer_source')==c['own'] and grant.get('return_root')==str(root)
          and grant.get('files')==opaque and integer(grant.get('maximum_files'),MAX_FILES)
          and integer(grant.get('maximum_file_bytes'),MAX_FILE) and integer(grant.get('maximum_total_bytes'),MAX_TOTAL)
          and integer(grant.get('expected_total_bytes'),sum(x['bytes'] for x in opaque)) and integer(grant.get('maximum_calls'),1)
          and grant.get('no_deserialization_R_numpy_scoring_array_load_or_model_promotion') is True
          and c['parent']['issued_epoch']<=grant['issued_epoch']<=now<grant['expires_epoch']<=c['parent']['expires_epoch'],
          'fresh exact-source/config/job/manifest/collect-bound opaque-return hash-only ROOT grant before binary access')
    check(root.resolve(strict=True)==root and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,'private actual return directory')
    actual=set();count=0
    for directory,dirs,files in os.walk(root,followlinks=False):
        for name in dirs+files:
            count+=1;check(count<=MAX_FILES+32,'bounded exact returned tree')
            check(not (Path(directory)/name).is_symlink(),'no returned symlink')
        for name in files:actual.add(str((Path(directory)/name).relative_to(root)))
    check(actual==set(mapping)|{'RETURN_MANIFEST.json'},'actual complete return file closure, no hidden or unlisted files')
    # The grant was validated above. Only exact listed paths can be opened here.
    for rel,row in mapping.items():
        check((root/rel).stat().st_uid==os.getuid(),'every actual SFTP-returned file is owned by the current operator')
        stable(root/rel,row['sha256'],row['bytes'],return_bytes=False)
    c.update(manifest=manifest,rows=mapping,returned=root,opaque_grant=opaque_grant_pin,
             returned_binary_files_blind_hashed=len(opaque),returned_total_bytes=total)
    return manifest


def metadata_return(c,rel):
    check(rel in c['rows'] and Path(rel).suffix=='.json','exact returned metadata JSON membership')
    row=c['rows'][rel];return strict(stable(c['returned']/rel,row['sha256'],row['bytes']))


def released_context(c):
    candidates=[x for x in c['past'] if x['state']=='RELEASED']
    check(candidates,'actual RELEASED canonical record')
    release_pin=candidates[-1]['release'];release=linked(release_pin);bundle=physical(release_pin['path']).parent
    check(bundle==c['base']/'critical_driver/release','actual canonical critical-driver release bundle')
    check(release.get('status')=='ROOT_RELEASED_STARTUP_BATCH_ROLE' and release.get('purpose')=='FROZEN525_NUMERICAL_STAGE_ONLY'
          and release['role']==ROLE and release['job_id']==c['job']['job_id'] and release['node']=='node-13'
          and release['scope_id']==c['packet']['scope_id'] and release['spec_sha256']==c['packet']['spec_sha256']
          and release['sources']==c['packet']['sources'] and release['scope_sha256']==c['spec']['scope']['sha256'],
          'exact current numerical-only release identity')
    files=release['files'];check(type(files) is list and 1<=len(files)<=16,'bounded exact flat release')
    rm={}
    for row in files:
        rel=row['relative'];check(type(rel) is str and '/' not in rel and rel not in rm and rel!='RELEASE.json'
              and Path(rel).suffix=='.json','unique exact released metadata only')
        rm[rel]=row
        check(pin(bundle/rel)['sha256']==row['sha256'],'released metadata bytes bound to actual release')
    def remote_bytes(ref):
        check(type(ref) is dict and set(ref)=={'path','sha256'},'exact logical returned/released pin')
        p=PurePosixPath(ref['path']);remote=PurePosixPath(c['packet']['remote_root'])
        if p.is_relative_to(remote/'result'):
            rel=str(p.relative_to(remote/'result'));check(rel in c['rows'] and c['rows'][rel]['sha256']==ref['sha256'],'logical returned proof exact hash')
            if rel in c['contract'].output_inventory(ROLE)[1]:
                return None  # Already independently blind-hashed; never interpret binary bytes.
            return stable(c['returned']/rel,ref['sha256'],c['rows'][rel]['bytes'])
        check(p.parent==remote/'release' and p.name in rm and rm[p.name]['sha256']==ref['sha256'],
              'closed flat logical release proof mapping; no external following')
        return stable(bundle/p.name,ref['sha256'])
    def remote_json(ref):
        check(PurePosixPath(ref['path']).suffix=='.json','metadata logical pin only')
        return strict(remote_bytes(ref))
    keys={'owner_spec','owner_authority','owner_review','stage_grant','stage_source_review','global_contract','bootstrap_spec',
          'physical_core_proof','physical_core_review','independent_review'}
    for key in keys:remote_json(release[key])
    independent=remote_json(release['independent_review'])
    check(independent.get('status')=='PASS_REVIEWED_FROZEN525_NUMERICAL_BATCH_RELEASE'
          and all(independent.get(k)==release[k] for k in ('role','job_id','node','ready_sha256','spec_sha256','sources'))
          and independent.get('stage_pins')=={key:release[key] for key in keys-{'independent_review'}},
          'actual complete original independent numerical release review')
    owner=remote_json(release['owner_spec']);authority=remote_json(release['owner_authority']);bootstrap=remote_json(release['bootstrap_spec'])
    check(all(owner[k]==v for k,v in dict(role=ROLE,job_id=c['job']['job_id'],node='node-13',scope_id=c['packet']['scope_id'],
          scientific_sources=c['spec']['science'],source_commit=c['spec']['source_commit'],stage_grant=release['stage_grant'],
          bootstrap_spec=release['bootstrap_spec']).items()) and owner['nonce']==c['spec']['nonce'], 'exact current owner/spec/grant/science/nonce')
    owner_names={'numerical_stage_owner.py','numerical_stage_contract.py','numerical_stage_bootstrap.R','startup_helper.py',
                 'scientific_allocation.py','profile_admission.py','environment.py','numerical_physical_admission.py',
                 'scientific_namespace_contract.py'}
    expected_owner_sources={name:c['packet']['sources'][name] for name in owner_names}
    owner_review=remote_json(release['owner_review'])
    check(authority.get('status')=='ROOT_ADMITTED_R182_FROZEN525_NUMERICAL_STAGE'
          and authority.get('spec')==release['owner_spec'] and authority.get('sources')==expected_owner_sources
          and authority.get('role')==ROLE and integer(authority.get('max_calls'),1)
          and all(integer(authority.get(k),v) for k,v in dict(memory_MiB=8192,whole_CPU_seconds=600,whole_wall_seconds=1200,
              owner_CPU_seconds=450,owner_wall_seconds=300,R_child_CPU_seconds=300).items())
          and owner_review.get('status')=='PASS_REVIEWED_R182_FROZEN525_NUMERICAL_OWNER_AND_SPEC'
          and owner_review.get('spec')==release['owner_spec'] and owner_review.get('authority')==release['owner_authority']
          and owner_review.get('sources')==expected_owner_sources and owner_review.get('role')==ROLE,
          'same independently reviewed current owner source map, root funding and exact limits')
    ordered=[owner['scientific_sources'][name] for name in sorted(owner['scientific_sources'])]
    check(bootstrap['schema']=='r182_hb_numerical_bootstrap_v1' and all(bootstrap[k]==owner[k] for k in ('role','job_id','node','nonce'))
          and bootstrap['scientific_entrypoint']==owner['entrypoint'] and bootstrap['source_parse_files']==ordered
          and bootstrap['boundary_library']==owner['boundary_library'] and bootstrap['expected_stock_body_sha256']==c['contract'].STOCK_BODY_SHA,
          'exact original five-source bootstrap/current nonce and entrypoint')
    c.update(release=release,owner_spec=owner,owner_authority=authority,bootstrap=bootstrap,
             remote_json=remote_json,remote_bytes=remote_bytes,ordered_science=ordered)
    return release


def current_closed_owner(c,success):
    required={'numerical/INTENT.json','numerical/owned_guard.json','numerical/owned_tree.json','numerical/PARSE_PARENT_GATE.json','EXECUTION_CONTEXT.json'}
    check(required<=set(c['rows']),'complete current owner/parse/ACK closure metadata')
    release=released_context(c);ready=local(c['root']/'READY.json');identity=ready['worker_identity']
    check(ready['job_id']==c['job']['job_id'] and ready['scope_id']==c['packet']['scope_id'] and ready['node']=='node-13'
          and ready['spec_sha256']==c['packet']['spec_sha256'] and ready['sources']==c['packet']['sources']
          and ready['inventory']['scheduler']['uid']==identity['uid']==os.getuid()
          and release['ready_sha256']==pin(c['root']/'READY.json')['sha256'],'actual current READY kernel worker identity')
    check(metadata_return(c,'INVENTORY.json')==ready['inventory'],'returned inventory equals actual current READY inventory')
    snapshot=metadata_return(c,'PHYSICAL_SNAPSHOT.json')
    check(snapshot==ready['physical_snapshot_value'] and ready['physical_snapshot']==dict(
          path=c['packet']['remote_root']+'/result/PHYSICAL_SNAPSHOT.json',sha256=c['rows']['PHYSICAL_SNAPSHOT.json']['sha256']),
          'returned physical snapshot equals actual current READY pin and value')
    context=metadata_return(c,'EXECUTION_CONTEXT.json')
    check(context['spec']==dict(path=c['packet']['remote_root']+'/SPEC.json',sha256=c['packet']['spec_sha256'])
          and context['ready']==dict(path=c['packet']['remote_root']+'/READY.json',sha256=release['ready_sha256'])
          and context['release']==dict(path=c['packet']['remote_root']+'/release/RELEASE.json',sha256=pin(c['base']/'critical_driver/release/RELEASE.json')['sha256']),
          'actual sealed worker execution context')
    intent=metadata_return(c,'numerical/INTENT.json')
    check(intent['status']=='STARTED_NUMERICAL_STAGE_NOT_PASS' and intent['spec']==release['owner_spec']
          and intent['authority']==release['owner_authority'] and intent['review']==release['owner_review'] and intent['role']==ROLE,
          'actual current numerical owner start intent')
    check(intent.get('sources')==c['owner_authority']['sources'],'current owner start uses the exact reviewed compute-source map')
    g=metadata_return(c,'numerical/owned_guard.json');tree=metadata_return(c,'numerical/owned_tree.json');gate=metadata_return(c,'numerical/PARSE_PARENT_GATE.json')
    flags=('reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution',
           'tracer_death_kernel_EXITKILL_enabled','postbootstrap_TSYNC_scientific_fork_denial','scientific_target_access_handshake')
    att=g.get('scientific_filter_kernel_attestation') or {}
    check(g.get('schema')=='r157_traced_bootstrap_guard_receipt_v1' and g.get('status')=='EXITED'
          and integer(g.get('returncode')) and (g['returncode']==0 if success else g['returncode']!=0)
          and all(g.get(k) is True for k in flags) and g.get('remaining_owned_lifetimes')==[]
          and g.get('unexpected_untraced_child_waits')==[] and g.get('abort_reason') is None
          and att.get('operation')=='SECCOMP_SET_MODE_FILTER' and att.get('flags')=='TSYNC' and att.get('kernel_return')==0,
          'current failed/successful child exit with complete kernel TSYNC/ACK and reaping, no failed receipt relabel')
    check(integer(g.get('maximum_combined_CPU_seconds'),450) and number(g.get('parent_plus_all_reaped_child_CPU_seconds'))
          and 0<=g['parent_plus_all_reaped_child_CPU_seconds']<450 and number(g.get('wall_seconds')) and 0<=g['wall_seconds']<300,
          'actual inclusive owner CPU/wall limits')
    check(tree.get('schema')=='r157_ptrace_owner_v1' and tree.get('state')=='CLOSED'
          and tree.get('scope')==c['packet']['scope_id'] and tree.get('source')==dict(kind=SOURCE_KIND)
          and tree.get('authority_pin')==release['owner_authority'] and tree.get('traced_live_lifetimes')==[],
          'actual current completely closed owner tree')
    for actual in (g['supervisor'],tree['supervisor']):
        check(all(actual.get(k)==identity[k] for k in ('pid','start_ticks','boot_id','affinity')),'same READY worker lifetime owns trace')
    check(g.get('owned_root')==tree.get('root') and type(g.get('owned_root')) is dict
          and integer(g['owned_root'].get('pid')) and integer(g['owned_root'].get('start_ticks'))
          and g['owned_root']['pid']>0 and g['owned_root']['start_ticks']>0
          and g['owned_root'].get('ppid')==identity['pid'] and g['owned_root'].get('affinity')==identity['affinity'],
          'same current owned R root lifetime and affinity')
    attestations=[event for event in g.get('events',[]) if event.get('event')=='SCIENTIFIC_FILTER_KERNEL_ATTESTED']
    check(att.get('pid')==g['owned_root']['pid'] and len(attestations)==1 and attestations[0].get('proof')==att,
          'current owned R PID has exactly the recorded kernel TSYNC attestation')
    check(gate.get('status')=='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK'
          and all(gate.get(k)==c['owner_spec'][k] for k in ('role','job_id','node','scope_id'))
          and gate.get('authority')==release['owner_authority'] and gate.get('original_tracer_pre_ACK_capture_callback') is True
          and gate.get('kernel_ACK_still_requires_original_guard_completion') is True,'current owning parent parse gate plus completed ACK proof')
    frame=gate['frame'];expected=dict(status='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT',role=ROLE,
          job_id=c['job']['job_id'],node='node-13',nonce=c['owner_spec']['nonce'],source_files=c['ordered_science'],
          optimizer_invocations=0,scientific_target_data_read=False)
    check(frame==expected,'exact five-source parse frame before current kernel ACK')
    check(integer(frame['optimizer_invocations'],0) and frame['scientific_target_data_read'] is False,
          'typed zero invocation and false preACK target-access frame')
    fs=gate['filesystem_before_ACK'];fskeys=('device','fragment_bytes','available_blocks','available_bytes','free_bytes','minimum_available_bytes')
    check(fs.get('status')=='OBSERVED_NUMERICAL_FILESYSTEM_STAT_NOT_USER_QUOTA'
          and fs.get('path')==c['owner_spec']['remote_namespace'] and all(integer(fs.get(k)) and fs[k]>=0 for k in fskeys)
          and fs['fragment_bytes']>0 and fs['available_bytes']==fs['available_blocks']*fs['fragment_bytes']
          and fs['free_bytes']>=fs['available_bytes']>=fs['minimum_available_bytes']==80*1024**3
          and fs.get('quota_status')=='UNKNOWN' and number(fs.get('observed_epoch')),
          'actual source-defined beforeACK filesystem proof retains original80GiB floor and unknown quota')
    c.update(guard=g,tree=tree,parse_frame=frame,parent_gate=gate,current_ACK_proved=True)
    return True


def scalar(value,kind='number'):
    check(type(value) is dict and type(value.get('available')) is bool,'typed bounded scalar wrapper')
    if not value['available']:
        check(set(value)=={'available','label'} and value['label'] in {'UNAVAILABLE','REDACTED_NONSCALAR','REDACTED_TYPE'},'closed unavailable/redacted scalar')
        return None
    check(value.get('kind') in {kind,'nonfinite'},'expected scalar kind')
    if value['kind']=='nonfinite':
        check(set(value)=={'available','kind','label'} and value['label'] in {'NA','NaN','Inf','-Inf'},'literal nonfinite label, never JSONnonfinite')
        return None
    check(set(value)=={'available','kind','value'} and (type(value['value']) is bool if kind=='boolean' else number(value['value'])),
          'finite number or exact boolean scalar only')
    return value['value']


def certificate(value,fallback=False):
    if fallback and type(value) is dict and set(value)=={'available'} and value['available'] is False:return None
    check(type(value) is dict and set(value)=={'available','measures','limits','certified','raw_reconstructed_elbo','raw_next_elbo','rhs_reconstruction'}
          and type(value['available']) is bool and set(value['measures'])==set(LIMITS) and set(value['limits'])==set(LIMITS)
          and set(value['rhs_reconstruction'])==RHS_NUMBERS|RHS_BOOLEANS,'closed original seven-measure/RHS certificate whitelist')
    measures={k:scalar(v) for k,v in value['measures'].items()}
    for k,v in value['limits'].items():
        x=scalar(v);check(x is None or x==LIMITS[k],'unchanged original individual certificate limits')
    scalar(value['certified'],'boolean');scalar(value['raw_reconstructed_elbo']);scalar(value['raw_next_elbo'])
    for k,v in value['rhs_reconstruction'].items():scalar(v,'boolean' if k in RHS_BOOLEANS else 'number')
    return measures


def scalar_diagnostic(c):
    if 'numerical/child.stdout' not in c['rows']:
        return dict(status='UNAVAILABLE_NO_STDOUT',diagnostic_available=False)
    row=c['rows']['numerical/child.stdout'];check(row['bytes']<=1024**2,'unchanged bounded child stdout')
    raw=stable(c['returned']/'numerical/child.stdout',row['sha256'],row['bytes'],limit=1024**2)
    frames=[]
    for line in raw.splitlines():
        if not line.lstrip().startswith(b'{'):continue
        value=strict(line)
        check(type(value) is dict,'JSON line object only')
        frames.append((line,value))
    parse=[x for _,x in frames if x.get('status')=='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT']
    candidates=[(line,x) for line,x in frames if x.get('schema')=='r188_post_ACK_bridge_scalar_diagnostic_v1']
    check(len(parse)==1 and parse[0]==c['parse_frame'] and len(candidates)<=1 and len(frames)==1+len(candidates),
          'one exact parse frame and at most one closed postACK scalar frame, no foreign JSON payload')
    if not candidates:return dict(status='UNAVAILABLE_NO_POST_ACK_LOGGER_FRAME',diagnostic_available=False)
    raw_frame,value=candidates[0]
    keys={'schema','status','role','job_id','node','nonce','source_files','entrypoint','bootstrap_spec','context_complete',
          'diagnostic_available','logging','original_limits','current_cert','old_cert','terminal_sigma','R_exit_status','numerical_acceptance'}
    check(len(raw_frame)<=16384 and set(value)==keys and value['status']=='R188_BRIDGE_SCALARS_AFTER_ACK_FAILED_NOT_ACCEPTANCE'
          and value['role']==ROLE and value['job_id']==c['job']['job_id'] and value['node']=='node-13'
          and value['nonce']==c['owner_spec']['nonce'] and type(value['context_complete']) is bool
          and type(value['diagnostic_available']) is bool and value['original_limits']==LIMITS
          and integer(value['R_exit_status'],1) and value['numerical_acceptance'] is False,
          'bounded exact original postACK scalar schema/identity/limits, never acceptance')
    check(c['guard']['returncode']==1,'source-defined scalar logger R exit1 agrees current owned guard')
    if value['context_complete']:
        check(value['source_files']==c['ordered_science'] and value['entrypoint']==c['owner_spec']['entrypoint']
              and value['bootstrap_spec']==c['owner_spec']['bootstrap_spec'],'same exact current source and bootstrap identity')
    else:
        check(value['source_files']==[] and value['entrypoint'] is None and value['bootstrap_spec'] is None
              and value['diagnostic_available'] is False,'closed unavailable incomplete source context')
    fallback=value['logging']=='UNAVAILABLE'
    check((fallback and value['diagnostic_available'] is False) or
          (value['logging']=='SCALAR_WHITELIST_ONLY' and value['diagnostic_available']==value['context_complete']),
          'source-defined scalar whitelist or truthful fallback only')
    current=certificate(value['current_cert'],fallback);old=certificate(value['old_cert'],fallback);scalar(value['terminal_sigma'])
    finite_both=current is not None and old is not None and all(current[k] is not None and old[k] is not None for k in LIMITS)
    comparisons={}
    if finite_both:
        for k in LIMITS:
            delta=current[k]-old[k]
            comparisons[k]=dict(current=current[k],saved=old[k],equal=current[k]==old[k],difference=delta if math.isfinite(delta) else None)
    return dict(status='REVIEWED_POST_ACK_SCALAR_FRAME_NOT_NUMERICAL_ACCEPTANCE',diagnostic_available=value['diagnostic_available'],
                frame_bytes=len(raw_frame),frame_sha256=hashlib.sha256(raw_frame).hexdigest(),frame=value,
                all_seven_current_and_saved_finite=finite_both,measure_comparisons=comparisons,
                current_parse_and_kernel_TSYNC_parent_ACK_proved=True,numerical_acceptance=False)


def successful_core(c,result):
    outcome=result['outcome'];release=c['release'];read=c['remote_json']
    check(outcome.get('status')=='PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE' and outcome.get('job_id')==c['job']['job_id']
          and outcome.get('node')=='node-13' and outcome.get('current_TSYNC_and_parent_ACK') is True
          and outcome.get('production_admission') is False and integer(outcome.get('production_fits'),0)
          and integer(outcome.get('pilot_fits'),0),'complete successful zero-update outcome, no production/pilot')
    check(read(outcome['owned_guard'])==c['guard'] and read(outcome['owned_tree'])==c['tree']
          and read(outcome['owner_validated_parse_before_kernel_ACK'])==c['parent_gate']
          and outcome['source_parse_pass_before_numerical_entrypoint']==c['parse_frame'], 'outcome pins bind actual complete current owner/ACK')
    grant=read(release['stage_grant']);core=read(outcome['core'])
    c['contract'].validate_grant(c['owner_spec'],grant,now=c['parent_gate']['filesystem_before_ACK']['observed_epoch'])
    check(core.get('schema')=='r154_conditional_state_bridge_v1' and core.get('status')=='VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE'
          and core.get('target_name')==c['contract'].TARGET and integer(core.get('optimizer_updates'),0)
          and core.get('source')==grant['source'] and core.get('production_acceptance_authority') is False
          and core.get('exact_optimizer_resume') is False and core.get('original_failed_state_modified') is False,
          'exact unchanged zero-update bridge core and mathematical source')
    for key in ('full_state_factors_verified','explicit_factor_elbo_verified','original_seven_certificate_computed',
                'rhs_unit_and_dispersed_verified','source_recipe_reproduced'):
        check(core.get(key) is True,'original full-state/seven-gate/both-RHS proof '+key)
    for key in ('factor_state','baseline_certificate_pin'):
        ref=core[key];check(PurePosixPath(ref['path']).is_relative_to(PurePosixPath(c['packet']['remote_root'])/'result/numerical'),
                            'exact private returned bridge proof')
        c['remote_bytes'](ref)
    baseline=read(core['baseline_certificate_pin'])
    check(type(baseline.get('measures')) is dict and set(baseline['measures'])==set(LIMITS)
          and all(number(x) for x in baseline['measures'].values()) and baseline.get('limits')==LIMITS,
          'all original seven finite baseline measures and individual unchanged limits')
    rhs=baseline.get('rhs_reconstruction') or {}
    check(rhs.get('unit_converged') is True and rhs.get('dispersed_converged') is True,
          'both original RHS starts reconstructed and converged')
    check(number(core.get('objective_difference')) and number(core.get('verification_bound_not_a_production_gate'))
          and abs(core['objective_difference'])<=core['verification_bound_not_a_production_gate'],
          'original explicit factor objective reconstruction within recorded nonproduction verification bound')


def review_return(config_path,collect_guard_path,publication_pin,review_pin,opaque_grant_pin,output_root):
    c=context(config_path,collect_guard_path,publication_pin,review_pin);out=physical(output_root)
    check(out==c['base']/'return_review' and out.resolve(strict=True)==out and out.stat().st_uid==os.getuid()
          and out.stat().st_mode&0o077==0,'one private bounded review output directory')
    write_new(out/'INTENT.json',dict(status='STARTED_ONE_SHOT_EXACT_W191_RETURN_REVIEW_NO_ACCEPTANCE',config=c['config'],
              source=c['own'],actual_collect_guard=c['collect_guard'],issued_epoch=time.time()))
    manifest=verify_manifest_and_bytes(c,opaque_grant_pin,publication_pin,review_pin)
    result=metadata_return(c,'RESULT.json');success=manifest['complete_success']
    check(result.get('status')==('PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER' if success else 'FAILED_FROZEN525_NUMERICAL_WORKER')
          and all(result.get(k)==c['packet'][k] for k in ('role','scope_id','sources','spec_sha256'))
          and result.get('job_id')==c['job']['job_id'] and result.get('node')=='node-13'
          and integer(result.get('production_fits'),0) and integer(result.get('pilot_fits'),0)
          and number(result.get('whole_self_plus_waited_CPU')) and 0<=result['whole_self_plus_waited_CPU']<600
          and number(result.get('wall_seconds')) and 0<=result['wall_seconds']<1200
          and result.get('canonical_primary_accounting_still_required') is True,
          'exact worker result identity, actual resource totals and zero production/pilot fits')
    check(c['account']['complete']==success,'manifest/worker outcome agrees independent terminal primary accounting')
    check((result.get('error') is None and type(result.get('outcome')) is dict) if success else
          (type(result.get('error')) is str and 0<len(result['error'])<=65536 and result.get('outcome') is None),
          'actual source-defined complete outcome or failed owner exception, never a fabricated worker PASS')
    closure_error=None;diag=dict(status='UNAVAILABLE_CURRENT_OWNER_ACK_CLOSURE_NOT_PROVED',diagnostic_available=False)
    try:
        current_closed_owner(c,success)
    except (ValueError,KeyError,TypeError) as exc:
        if success:raise
        closure_error=type(exc).__name__+': '+str(exc)
    if closure_error is None:
        diag=scalar_diagnostic(c)
        if success:successful_core(c,result)
    common=dict(schema='legacy_w191_complete_or_failed_return_review_v1',config=c['config'],scope=c['cfg']['scope'],role=ROLE,
          job_id=c['job']['job_id'],job=pin(c['root']/'JOB.json'),packet=pin(c['root']/'PACKET.json'),
          result=pin(c['returned']/'RESULT.json'),return_manifest=c['manifest_pin'],accounting=c['account_pin'],
          actual_collect_guard=c['collect_guard'],source=c['own'],source_publication=publication_pin,source_review=review_pin,
          opaque_hash_grant=opaque_grant_pin,whole_return_files=len(c['rows']),whole_return_bytes=c['returned_total_bytes'],
          exact_returned_binary_files_blind_hashed=c['returned_binary_files_blind_hashed'],
          source_and_manifest_hashes_independently_rechecked=True,primary_accounting_counted_once=True,
          diagnostic=diag,current_owner_parse_TSYNC_ACK_and_drain_proved=closure_error is None,
          closure_error=closure_error,production_acceptance=False,pilot_authority=False,
          no_R_numpy_array_load_models_scoring_or_new_losses=True,issued_epoch=time.time(),
          read_set=list(READS.values())+list(c['m'].READS.values()))
    if success:
        value=dict(common,status='PASS_REVIEWED_COMPLETE_FROZEN525_NUMERICAL_ROLE')
        path=out/'COMPLETE_RETURN_REVIEW.json';write_new(path,value)
    else:
        value=dict(common,status=('PASS_REVIEWED_W191_FAILED_DIAGNOSTIC_RETURN_NO_NUMERICAL_ACCEPTANCE'
                   if closure_error is None else 'QUARANTINED_W191_FAILED_RETURN_OWNER_ACK_UNAVAILABLE'),numerical_acceptance=False)
        path=out/'FAILED_RETURN_REVIEW.json';write_new(path,value)
        if closure_error is None:
            write_new(out/'FAILED_RETIREMENT_REVIEW.json',dict(common,status='PASS_REVIEWED_FROZEN525_FAILED_ROLE_RETIREMENT',
                      failed_diagnostic_review=pin(path),numerical_acceptance=False,actual_queue_and_exact_claim_cleanup_still_required=True,
                      no_Alloc0_tail_substitution=True))
    u=resource.getrusage(resource.RUSAGE_SELF)
    write_new(out/'RECEIPT.json',dict(status='COMPLETED_ONE_PAID_W191_RETURN_REVIEW_NOT_ROOT_ACCEPTANCE',output=pin(path),
              source=c['own'],SELF_CPU_seconds=u.ru_utime+u.ru_stime,SELF_CPU_cap=6,wall_cap=120,
              full_original_independent_complete_return6_retained=True,no_native_commands_or_jobs=True))
    return value


def main():
    check(os.sched_getaffinity(0)=={31},'administrative CPU31 only')
    resource.setrlimit(resource.RLIMIT_CPU,(6,6));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(120)
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('config','collect-guard','support-publication','source-review','opaque-grant','output-root'):
        parser.add_argument('--'+key,required=True)
    args=parser.parse_args()
    value=review_return(args.config,args.collect_guard,pin(args.support_publication),pin(args.source_review),pin(args.opaque_grant),args.output_root)
    print(json.dumps(dict(status=value['status'],job_id=value['job_id'],numerical_acceptance=False,
          diagnostic_available=value['diagnostic']['diagnostic_available']),sort_keys=True))


if __name__=='__main__':main()
