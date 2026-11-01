"""Create-only W191 node13 diagnostic issuer. No Slurm or scientific execution.

Each phase requires reviewed/published support, an exact ROOT request binding,
prospective whole funding and one-shot intent. Old W191 sources are read only.
"""
import argparse,hashlib,importlib.util,json,math,os,re,resource,signal,stat,sys,time
from pathlib import Path

BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_r165_headroom_execution_20261029_1526PDT')
OLD=BASE/'node15_qualification_implementation_20261031_2145PDT'
PROTO=OLD/'legacy_node13_diagnostic_preparation/LEGACY_NODE13_DIAGNOSTIC.py'
PROTO_SHA='a4e100613b7742f4c6ffdc2c952219d3b9ec6c45a2fd0d7f56833727d1afa53f'
HOME=Path('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa')
ROLE='ZERO_UPDATE_BRIDGE'
PHASES=['issue','cache','finalize','driver']
SETUP=dict(issue_original_H8=8,blind_hash_original_H8=8,finalize_original_H4=4,stage_authority_SELF2=2)
READSET={}

def require(value,message):
    if not value:raise ValueError(message)
def physical(path):
    p=Path(path).absolute()
    require('..' not in p.parts and not any(x.is_symlink() for x in (p,*p.parents)),'physical path only')
    return p
def bytes_meta(path):
    p=physical(path)
    require(p.suffix in {'.json','.py','.R','.stdout','.stderr'} and 'target_cache' not in p.parts,'bounded metadata/source only')
    with os.fdopen(os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK),'rb') as f:
        before=os.fstat(f.fileno());require(stat.S_ISREG(before.st_mode) and before.st_size<=32*2**20,'bounded regular metadata')
        data=f.read(32*2**20+1);after=os.fstat(f.fileno())
    fingerprint=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    require(len(data)==before.st_size and fingerprint(before)==fingerprint(after)==fingerprint(p.stat()),'stable complete metadata read')
    READSET[str(p)]=dict(path=str(p),sha256=hashlib.sha256(data).hexdigest(),bytes=len(data));return data
def pin(path):return dict(path=str(physical(path)),sha256=hashlib.sha256(bytes_meta(path)).hexdigest())
def encode(value):return (json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def pairs(items):
    result={}
    for k,v in items:require(k not in result,'duplicate metadata key');result[k]=v
    return result
def linked(value):
    require(type(value) is dict and set(value)=={'path','sha256'} and re.fullmatch('[0-9a-f]{64}',value['sha256']),'strict metadata pin')
    raw=bytes_meta(value['path']);require(hashlib.sha256(raw).hexdigest()==value['sha256'],'metadata/source pin drift')
    def bad(x):raise ValueError('nonfinite metadata '+x)
    result=json.loads(raw,object_pairs_hook=pairs,parse_constant=bad)
    def finite(x):
        if isinstance(x,float):require(math.isfinite(x),'nonfinite metadata exponent')
        elif isinstance(x,dict):
            for v in x.values():finite(v)
        elif isinstance(x,list):
            for v in x:finite(v)
    finite(result);return result
def put(path,value):
    p=physical(path);raw=encode(value)
    require(p.suffix=='.json','JSON create-only output')
    fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
    return pin(p)
def module(path,sha,name):
    p=physical(path);require(p.suffix=='.py' and pin(p)['sha256']==sha,'reviewed exact source before import')
    spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def legacy():return module(PROTO,PROTO_SHA,'legacy_original_frozen_prototype')
def self_cpu():
    u=resource.getrusage(resource.RUSAGE_SELF);return u.ru_utime+u.ru_stime

def price(value):
    require(type(value) is dict,'complete price object')
    expected={'normal_administrative_CPU':234,'compute_CPU':600,'old_fee_credit':0,'separate_preparation_CPU':22,'compatible_failure_tail_CPU':28}
    for key,num in expected.items():require(type(value.get(key)) is int and value[key]==num,'exact typed price '+key)
    require(type(value.get('scheduler_evidence_CPU')) is int and value['scheduler_evidence_CPU']==16,'one final H8 plus remote8 scheduler price; initial proof separately funded')
    require(sum(SETUP.values())==22,'complete setup includes original cold H overhead')
    return 234+22+28+value['scheduler_evidence_CPU']

def support(r):
    review=linked(r['support_review']);pub=linked(r['support_publication'])
    require(review.get('status')=='PASS_REVIEWED_LEGACY_NODE13_SUPPORT_SOURCE' and pub.get('status')=='PASS_PUBLISHED_LEGACY_NODE13_SUPPORT_SOURCE','independent reviewed and published support')
    require(pub.get('independent_review')==r['support_review'] and pub.get('source_files')==review.get('source_files') and type(pub.get('source_files')) is dict,'exact support publication/review map')
    require(re.fullmatch('[0-9a-f]{40}',pub.get('commit','')) and pub.get('remote_readback')==pub['commit'] and type(pub.get('branch')) is str and pub['branch'] not in {'main','master','origin/main'},'feature branch exact remote readback')
    for key in ('issuer_source','cache_helper_source','scheduler_verifier'):
        item=r[key];require(pin(item['path'])==item and pub['source_files'].get(Path(item['path']).name)==item['sha256'],'exact published support source '+key)
    require(r['issuer_source']==pin(Path(__file__).absolute()),'actual executing issuer identity')
    tail=linked(r['compatible_H4_tail_approval']);original=legacy()
    require(tail.get('status')=='PASS_REVIEWED_W191_COMPATIBLE_SEPARATE_H4_FAILURE_PROTOCOL' and tail.get('source_publication')==original.PUB and tail.get('source_review')==original.REVIEW
        and tail.get('support_source_review')==r['support_review']
        and tail.get('role')==ROLE and tail.get('node')=='node-13' and tail.get('original_H3_unchanged') is True
        and tail.get('query_local_CPU')==tail.get('drain_local_CPU')==4 and tail.get('remote_CPU_uncertainty_included') is True
        and tail.get('automatic_retry') is False and type(tail.get('total_administrative_CPU')) is int and tail['total_administrative_CPU']==28,'compatible complete separate H4 failure protocol')
    for key in ('producer','independent_peer'):
        item=tail[key];require(pin(item['path'])==item and pub['source_files'].get(Path(item['path']).name)==item['sha256'],'published exact independent failure support')
    return original

def request_body(r):return {k:v for k,v in r.items() if k!='root_authority'}
def checked(request_pin,now=None,require_absent=False):
    now=time.time() if now is None else now;r=linked(request_pin)
    require(r.get('schema')=='legacy_node13_issue_request_v1' and re.fullmatch('[A-Za-z0-9_]{1,64}',r.get('purpose','')),'genuine new exact issue request')
    original=support(r);phase=linked(r['phase_scope']);root=physical(r['new_root']);parent=linked(r['prospective_parent'])
    require(phase.get('status')=='NEW_LEGACY_NODE13_COMPATIBLE_SUPPORT_IMPLEMENTATION_ONLY' and phase.get('maximum_proposed_compute_jobs')==1 and phase.get('proposed_node')=='node-13'
        and phase['issued_epoch']<=now<phase['expires_epoch'],'current new support purpose, never old expiry reuse')
    require(str(root).startswith(str(HOME)+'/Legacy_NODE13_') and root.parent==HOME and len(root.name)<=96 and root.parent.is_dir()
        and root.parent.stat().st_uid==os.getuid() and root.parent.stat().st_mode&0o077==0,'fresh private persistent HOME root descriptor')
    if require_absent:require(not root.exists(),'fresh root has no earlier issue or retry')
    authority=linked(r['root_authority'])
    require(authority.get('status')=='ROOT_AUTHORIZED_REVIEWED_LEGACY_NODE13_ISSUER'
        and authority.get('request_body_sha256')==hashlib.sha256(canonical(request_body(r))).hexdigest()
        and authority.get('phases')==PHASES and type(authority.get('maximum_calls_each')) is int and authority['maximum_calls_each']==1,'exact ROOT body, phases and one-shot calls')
    for key in ('phase_scope','new_root','ledger_after_output','support_review','support_publication','issuer_source','cache_helper_source'):
        require(authority.get(key)==r[key],'ROOT authority binding '+key)
    require(phase['issued_epoch']<=authority['issued_epoch']<=now<authority['expires_epoch']<=phase['expires_epoch'],'current authority inside new fixed purpose')
    verifier=module(r['scheduler_verifier']['path'],r['scheduler_verifier']['sha256'],'reviewed_legacy_production_scheduler')
    admitted=verifier.verify_root_admission(r['native_admission'],now=now)
    require(admitted.get('mode')=='initial','initial genuine resource-equivalent native admission before issuance')
    for key,value in dict(parent=r['prospective_parent'],purpose=r['purpose'],node='node-13',remote_namespace=r['remote_namespace'],known_jobs_registry=r['known_jobs_registry']).items():require(admitted.get(key)==value,'actual guarded native binding '+key)
    require(admitted['not_before_epoch']<=now<admitted['role_submit_cutoff_epoch']<=admitted['expires_epoch']<=phase['expires_epoch']
        and 0<=now-admitted['observed_epoch']<=60 and max(now,admitted['predicted_start_epoch'])<=now+255
        and max(now,admitted['predicted_start_epoch'])+7200+3600<=admitted['expires_epoch'],'genuine fresh forecast and complete conservative calendar')
    context,batch=original.historical();require(r['publication']==original.PUB and r['source_review']==original.REVIEW,'exact historical W191 source identity')
    require(re.fullmatch('/mnt/beegfs/home/jaguir26/pricefm_r182_LEGACY_[A-Za-z0-9_]{1,64}_[0-9a-f]{32}',r['remote_namespace']) and r['remote_namespace']!=context['config']['remote_namespace'],'new exact W191 namespace')
    known=linked(r['known_jobs_registry']);jobs=known.get('jobs')
    require(type(jobs) is list and len(jobs)==17 and len({x['job_id'] for x in jobs})==17 and all(x.get('state') in batch.TERMINAL for x in jobs)
        and set(context['matched_jobs']+['888523','888843'])<={x['job_id'] for x in jobs},'whole supplied current known17 all terminal before new one job')
    ns=linked(r['namespace_registry']);require(ns.get('known_jobs_registry')==r['known_jobs_registry'] and r['remote_namespace'] not in ns.get('namespaces',[]) and str(root) not in ns.get('canonical_roots',[]),'unique namespace and root against current supplied registry')
    total=price(r['proposed_price']);before=linked(r['ledger_before']);out=physical(r['ledger_after_output'])
    require(out.parent==physical(r['phase_scope']['path']).parent and out.suffix=='.json' and out!=Path(r['ledger_before']['path']),'new current-phase ledger file only')
    require(type(before.get('scopes')) is list and type(before.get('compute_roles')) is list and not any(x.get('purpose')==r['purpose'] for x in before['scopes']),'whole unchanged earlier ledger, new purpose only')
    for key in ('total_administrative_reservation','total_new_administrative_reservation','total_qualification_compute_reservation','total_new_qualification_compute_reservation'):require(type(before.get(key)) is int and before[key]>=0,'typed whole ledger counter')
    require(r['original_delivery_request']==original.ORIGINAL_REQUEST,'exact untouched15 request')
    target=linked(r['original_delivery_request']);contract=batch.contract;rows=[]
    require(set(r['opaque_cache_sources'])==set(contract.DELIVERY_HASHES),'closed15 opaque descriptors')
    for row in target['files']:
        source=r['opaque_cache_sources'][row['relative']]
        require(set(source)=={'path','sha256'} and source['sha256']==row['source']['sha256']==contract.DELIVERY_HASHES[row['relative']]
            and row['bytes']==contract.DELIVERY_BYTES[row['relative']] and str(physical(source['path'])).startswith(str(HOME)+'/'),'original exact opaque source alias/hash/length, no byte operation')
        rows.append(dict(relative=row['relative'],logical_path=row['logical_path'],source=source,bytes=row['bytes']))
    require(target['total_bytes']==163921491 and target['original_mathematical_manifest']['sha256']==contract.ORIGINAL_MANIFEST_SHA,'unchanged exact target recipe')
    contract.validate_delivery(ROLE,[dict(x,remote=x['source']) for x in rows]);contract.validate_role(ROLE,context['config']['role_limits'])
    return dict(request=r,root=root,original=original,batch=batch,context=context,rows=rows,total=total,admission=admitted,phase=phase,ledger_before=before)

def exact_funding(c,scope_pin,after_pin):
    r=c['request'];before=c['ledger_before'];after=linked(after_pin)
    expected_row=dict(purpose=r['purpose'],scope=scope_pin,administrative_CPU_reservation=c['total'],compute_CPU_reservation=600)
    expected_compute=dict(canonical_home_root=r['new_root'],reservation=600,scope=scope_pin)
    equal=lambda a,b:canonical(a)==canonical(b)
    require(after.get('previous')==r['ledger_before'] and equal(after.get('scopes'),before['scopes']+[expected_row]) and equal(after.get('compute_roles'),before['compute_roles']+[expected_compute]),'exact new typed funding append, no edited old rows')
    for key,delta in [('total_administrative_reservation',c['total']),('total_new_administrative_reservation',c['total']),('total_qualification_compute_reservation',600),('total_new_qualification_compute_reservation',600)]:require(type(after.get(key)) is int and after[key]==before[key]+delta,'whole exact funding counter '+key)
    for key in before:
        if key not in {'previous','created_epoch','scopes','compute_roles','total_administrative_reservation','total_new_administrative_reservation','total_qualification_compute_reservation','total_new_qualification_compute_reservation'}:require(equal(after.get(key),before[key]),'old ledger field preserved '+key)
    return after

def issue(request_pin):
    c=checked(request_pin,require_absent=True);r=c['request'];root=c['root'];now=time.time();a=c['admission'];batch=c['batch']
    verifier=module(r['scheduler_verifier']['path'],r['scheduler_verifier']['sha256'],'reviewed_legacy_final_issue_clock_check')
    current=verifier.verify_root_admission(r['native_admission'],now=now)
    for key in ('parent','purpose','node','remote_namespace','known_jobs_registry','observed_epoch','predicted_start_epoch','not_before_epoch','expires_epoch','role_submit_cutoff_epoch','mode'):
        require(current[key]==a[key],'native initial immutable binding at actual issue '+key)
    require(0<=now-current['observed_epoch']<=60 and now<current['role_submit_cutoff_epoch'] and max(now,current['predicted_start_epoch'])+10800<=current['expires_epoch'],'native freshness/calendar rechecked after metadata audit immediately before issue')
    require(not Path(r['ledger_after_output']).exists(),'create-only ledger destination')
    root.mkdir(mode=0o700);put(root/'issue.INTENT.json',dict(status='STARTED_NOT_SUCCESS_NO_RETRY',phase='issue',request=request_pin,issued_epoch=now))
    limits=c['context']['config']['role_limits']
    scope=dict(status='PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE',issued_epoch=now,expires_epoch=a['expires_epoch'],fixed_latest_submit_epoch=a['role_submit_cutoff_epoch'],
        allowed_metadata_output_root=str(root),roles=[ROLE],maximum_jobs=1,max_concurrent_jobs=1,compute_CPU_reservation=600,complete_remaining_calendar_seconds=7200,final_reserve_seconds=3600,
        wall_seconds=1200,memory_MiB=8192,cpus_per_task=1,threads=1,nodes_per_job=1,tasks_per_job=1,automatic_retry=False,requeue=False,
        new_separate_administrative_CPU_reservation=234,administrative_allocations=c['original'].NORMAL,complete_administrative_CPU_reservation=c['total'],additional_prices=r['proposed_price'],setup_allocations=SETUP,
        extra_setup_forecast_tail={k:r['proposed_price'][k] for k in ('separate_preparation_CPU','scheduler_evidence_CPU','compatible_failure_tail_CPU')},
        role_limits=limits,accepted_toy=c['context']['accepted_toy'],scientific_target_delivery=True,optimizer_updates=0,production_fits=0,pilot_fits=0,
        all_old_fees_roles_caps_and_clocks_retained=True,fresh_qualification_purpose=r['purpose'],support_scope=r['phase_scope'])
    scope_pin=put(root/'SCOPE.json',scope)
    after=dict(c['ledger_before']);after.update(previous=r['ledger_before'],created_epoch=now,
        scopes=c['ledger_before']['scopes']+[dict(purpose=r['purpose'],scope=scope_pin,administrative_CPU_reservation=c['total'],compute_CPU_reservation=600)],
        compute_roles=c['ledger_before']['compute_roles']+[dict(canonical_home_root=str(root),reservation=600,scope=scope_pin)])
    for key,delta in [('total_administrative_reservation',c['total']),('total_new_administrative_reservation',c['total']),('total_qualification_compute_reservation',600),('total_new_qualification_compute_reservation',600)]:after[key]+=delta
    ledger_pin=put(r['ledger_after_output'],after);exact_funding(c,scope_pin,ledger_pin)
    put(root/'REQUEST.json',r)
    put(root/'NATIVE_CONTROL_SCOPE.json',dict(status='PROSPECTIVE_FRESH_NUMERICAL_NATIVE_CONTROL_BUDGET',scope=scope_pin,combined_native_control_CPU_ceiling=136,issued_epoch=now,expires_epoch=scope['expires_epoch'],per_action_original_caps_unchanged=True,no_automatic_retry=True))
    put(root/'STARTUP_WATCH_BUDGET.json',dict(status='PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET',scope=scope_pin,profile=batch.STARTUP_WATCH_PROFILE,issued_epoch=now,expires_epoch=scope['expires_epoch']))
    delivery=dict(status='ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY',scope=scope_pin,target_name=batch.contract.TARGET,files=c['rows'],original_manifest=linked(r['original_delivery_request'])['original_mathematical_manifest'],
        no_optimizer_or_science_execution=True,allow_opaque_transport=True,maximum_files=15,maximum_file_bytes=batch.contract.MAX_TARGET_FILE,maximum_total_bytes=batch.contract.MAX_TARGET_TOTAL)
    batch.contract.validate_opaque_delivery_authority(delivery,scope_pin,c['rows'],delivery['original_manifest']);delivery_pin=put(root/'OPAQUE_DELIVERY_AUTHORITY.json',delivery)
    cache=dict(status='ROOT_AUTHORIZED_EXACT_NO3_OPAQUE_HOME_CACHE',scope=scope_pin,funding_ledger=ledger_pin,source_request=r['original_delivery_request'],files=c['rows'],allow_opaque_transport=True,
        no_deserialization_R_numpy_scores_models_losses_or_jobs=True,maximum_files=15,maximum_file_bytes=batch.contract.MAX_TARGET_FILE,maximum_total_bytes=batch.contract.MAX_TARGET_TOTAL,expected_total_bytes=163921491,
        issued_epoch=now,expires_epoch=scope['expires_epoch'],maximum_calls=1,blind_hash_existing_only=True,no_copy=True,cache_helper_source=r['cache_helper_source'])
    cache_pin=put(root/'OPAQUE_CACHE_AUTHORITY.json',cache)
    tail_pin=put(root/'FAILURE_TAIL_BUDGET.json',dict(status='PROSPECTIVE_W191_COMPATIBLE_SEPARATE_H4_FAILURE_TAIL_BUDGET',schema='legacy_w191_unallocated_failure_budget_v1',parent_scope=scope_pin,
        role=ROLE,funding_ledger=ledger_pin,source_approval=r['compatible_H4_tail_approval'],allocations=c['original'].TAIL,total_administrative_CPU=28,issued_epoch=now,expires_epoch=scope['expires_epoch'],maximum_calls_each=1,maximum_query_calls=1,maximum_drain_calls=1,maximum_peer_calls=1,automatic_retry=False))
    result=dict(status='ISSUED_FRESH_FUNDED_LEGACY_NODE13_PROFILE_NO_BYTES_OR_JOB',request=request_pin,scope=scope_pin,funding_ledger=ledger_pin,delivery=delivery_pin,cache_authority=cache_pin,failure_tail_budget=tail_pin,
        phase_source=pin(__file__),support_review=r['support_review'],support_publication=r['support_publication'],native_admission_at_issue=r['native_admission'],issued_epoch=now,normal_administrative_CPU=234,complete_administrative_CPU=c['total'],compute_CPU=600,opaque_bytes_opened=0)
    put(root/'issue.RECEIPT.json',result);return result

def live(request_pin,phase,actual_guards):
    r=linked(request_pin);root=physical(r['new_root']);receipt=linked(pin(root/'issue.RECEIPT.json'));scope=linked(receipt['scope'])
    require(receipt['request']==request_pin,'exact original issued request')
    c=checked(request_pin,now=scope['issued_epoch']);exact_funding(c,receipt['scope'],receipt['funding_ledger'])
    now=time.time();authority=linked(r['root_authority'])
    require(scope['issued_epoch']<=now<scope['fixed_latest_submit_epoch']<=scope['expires_epoch'],'live immutable scope/cutoff')
    require(c['phase']['issued_epoch']<=now<c['phase']['expires_epoch'] and authority['issued_epoch']<=now<authority['expires_epoch']<=c['phase']['expires_epoch'],'ROOT authority and support phase must remain current at actual operation time')
    require(root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,'private persistent root unchanged')
    c.update(receipt=receipt,scope=scope,scope_pin=receipt['scope'])
    required={'cache':['issue'],'finalize':['issue','cache'],'driver':['issue','cache','finalize']}[phase]
    require(type(actual_guards) is dict and set(actual_guards)==set(required),'exact prior phase outer guard set')
    for name in required:
        g=linked(actual_guards[name]);c['batch'].passing_guard(g,4 if name=='finalize' else 8,300)
        stdout=json.loads(g['stdout'],object_pairs_hook=pairs)
        require(stdout.get('result')==linked(pin(root/(name+'.RECEIPT.json'))),'actual passing outer guard binds exact internal receipt '+name)
    return c
def intent(c,phase):return put(c['root']/(phase+'.INTENT.json'),dict(status='STARTED_NOT_SUCCESS_NO_RETRY',phase=phase,request=c['receipt']['request'],issued_epoch=time.time()))

def finalize(request_pin,actual_guards):
    c=live(request_pin,'finalize',actual_guards);r=c['request'];root=c['root'];cache=linked(pin(root/'cache.RECEIPT.json'))
    require(cache.get('status')=='PASS_EXACT_FRESH_AUTHORIZED_OPAQUE_BLIND_HASH_NO_COPY' and cache.get('request')==request_pin and cache.get('scope')==c['scope_pin']
        and cache.get('funding_ledger')==c['receipt']['funding_ledger'] and cache.get('authority')==c['receipt']['cache_authority'] and cache.get('bytes')==163921491
        and len(cache.get('files',[]))==15 and cache.get('semantic_array_reads')==cache.get('R_executions')==cache.get('optimizer_invocations')==0,'actual scoped complete blind hash receipt')
    require(cache.get('cache_helper_source')==r['cache_helper_source'],'actual reviewed cache helper receipt')
    intent(c,'finalize');old=c['context']['config'];keep=['schema','cached_python','cached_python_sha256','site','placement_proof','prerequisite_bundle','runtime_reuse','scientific_sources','traced_guard','boundary_library','role_limits','original_manifest','accepted_toy','source_branch']
    cfg={key:old[key] for key in keep};cfg.update(role=ROLE,node='node-13',scope=c['scope_pin'],registry=str(root/'canonical_registry'),source_dir=str(c['original'].S),publication=r['publication'],source_review=r['source_review'],
        native_control_budget=pin(root/'NATIVE_CONTROL_SCOPE.json'),startup_watch_budget=pin(root/'STARTUP_WATCH_BUDGET.json'),remote_namespace=r['remote_namespace'],known_jobs_registry=r['known_jobs_registry'],
        known_prior_jobs=[dict(job_id=x['job_id'],job_name=x['job_name'],terminal=x['state'] in c['batch'].TERMINAL) for x in linked(r['known_jobs_registry'])['jobs']],
        target_delivery=c['rows'],opaque_delivery_authority=c['receipt']['delivery'],critical_driver=dict(path=str(c['original'].S/'numerical_critical_driver.py'),sha256=c['context']['publication']['administrative_source_files']['numerical_critical_driver.py']))
    auth_path=root/'CANONICAL_NUMERICAL_AUTHORITY.json';auth=dict(status='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG',binding=c['batch'].canonical_identity(cfg),maximum_jobs=1,issued_epoch=time.time(),expires_epoch=c['scope']['expires_epoch'])
    auth_pin=dict(path=str(auth_path),sha256=hashlib.sha256(encode(auth)).hexdigest());cfg['canonical_authority']=auth_pin
    config_pin=put(root/'CANONICAL_CONFIG.json',cfg)
    code='import sys;sys.path.insert(0,'+repr(str(c['original'].S.parent))+');from pricefm_hb import numerical_batch;numerical_batch.main()\n'
    with (root/'execute_controller.py').open('x') as f:f.write(code);f.flush();os.fsync(f.fileno())
    require(put(auth_path,auth)==auth_pin,'canonical authority written last exactly after config')
    loaded=c['batch'].load_config(str(root/'CANONICAL_CONFIG.json'));require(loaded[0]==cfg,'actual original W191 ABI preflight')
    result=dict(status='PASS_FRESH_LEGACY_NODE13_CANONICAL_CONFIG_NO_JOB',request=request_pin,config=config_pin,scope=c['scope_pin'],funding_ledger=c['receipt']['funding_ledger'],cache_receipt=pin(root/'cache.RECEIPT.json'),canonical_authority_written_last=True,old_source_and_math_unchanged=True)
    put(root/'finalize.RECEIPT.json',result);return result

def driver(request_pin,stage_guard_pin,actual_guards):
    c=live(request_pin,'driver',actual_guards);root=c['root'];cfg,scope,_,_=c['batch'].load_config(str(root/'CANONICAL_CONFIG.json'))
    require(linked(pin(root/'finalize.RECEIPT.json')).get('status')=='PASS_FRESH_LEGACY_NODE13_CANONICAL_CONFIG_NO_JOB','completed original loader preflight')
    verify_stage_journal(c,cfg,stage_guard_pin)
    role_root=Path(cfg['registry'])/ROLE;require(c['batch'].records(role_root)[-1]['state']=='STAGED' and not (role_root/'JOB.json').exists(),'actual successfully staged fresh unsubmitted role')
    intent(c,'driver');now=time.time()
    value=dict(status='ROOT_AUTHORIZED_FROZEN525_NUMERICAL_CRITICAL_LIFECYCLE',config=pin(root/'CANONICAL_CONFIG.json'),scope=cfg['scope'],driver_source=cfg['critical_driver'],role=ROLE,role_limits=cfg['role_limits'],
        max_calls=1,automatic_retry=False,driver_SELF_CPU_reservation=10,driver_SELF_soft_CPU=8,peer_CPU_each=8,peer_phases=['source_physical','owner_release'],startup_watch_profile=c['batch'].STARTUP_WATCH_PROFILE,startup_watch_budget=cfg['startup_watch_budget'],driver_maximum_wall_seconds=1200,
        original_supervisor=pin(c['original'].S/'profile_supervisor.py'),peer_program=pin(c['original'].S/'numerical_independent_peer.py'),peer_program_independently_authored_and_reviewed=True,actual_stage_guard=stage_guard_pin,issued_epoch=now,expires_epoch=scope['expires_epoch'])
    require(value['original_supervisor']['sha256']=='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1','unchanged originalH')
    result=put(root/'DRIVER_AUTHORITY.json',value);put(root/'driver.RECEIPT.json',dict(status='PASS_STAGE_BOUND_W191_AUTHORITY_NOT_EXECUTED',authority=result,request=request_pin));return result

def verify_stage_journal(c,cfg,stage_guard_pin):
    """Read-only binding of this stage to its outstanding original W191 action.

    Original submit still owns journal validation; this never finalizes it.
    """
    batch=c['batch'];registry=physical(cfg['registry']);role_root=registry/ROLE
    outstanding=[p for p in registry.glob('control_*.started.json')
        if not p.with_name(p.name.replace('.started.json','.validated.json')).exists()
        and not p.with_name(p.name.replace('.started.json','.failed_ack.json')).exists()]
    require(len(outstanding)==1,'one unique outstanding original stage journal')
    started_path=outstanding[0];started=linked(pin(started_path));pending_path=started_path.with_name(started_path.name.replace('.started.json','.pending.json'))
    pending=linked(pin(pending_path));g=linked(stage_guard_pin);limits=batch.action_limits('stage')
    require(started.get('status')=='ACTION_STARTED_NOT_SUCCESS' and started.get('role')==ROLE and started.get('action')=='stage'
        and started.get('limits')==limits and started.get('source_sha256')==c['context']['publication']['source_files']['numerical_batch.py']
        and started['source_sha256']==pin(c['original'].S/'numerical_batch.py')['sha256'],'this canonical original W191 stage/source/caps')
    require(pending.get('status')=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
        and all(pending.get(k)==v for k,v in started.items() if k!='status'),'exact original started/pending action identity')
    batch.passing_guard(g,18,300)
    require(type(started.get('command_pid')) is int and type(started.get('command_birth_ticks')) is int
        and g.get('session_id')==started['command_pid'] and g.get('leader_start_ticks')==started['command_birth_ticks']
        and json.loads(g['stdout'],object_pairs_hook=pairs)==pending['result'],'actual stage outer guard PID/birth/stdout binding')
    packet=batch.packet(role_root);records=batch.records(role_root);result=pending['result']
    require(packet.get('role')==ROLE and packet.get('remote_root')==cfg['remote_namespace']+'/'+packet['scope_id']
        and result.get('status')=='STAGED_NOT_SUBMITTED' and result.get('scope_id')==packet['scope_id']
        and records[-1].get('state')=='STAGED' and records[-1].get('checksum')==result.get('checksum'),'this packet scope and actual staged journal result')
    linked(result['checksum'])
    return dict(started=pin(started_path),pending=pin(pending_path),guard=stage_guard_pin,original_submit_keeps_journal_ownership=True)

def main():
    require(os.sched_getaffinity(0)=={31},'administrative CPU31 only');os.umask(0o077);resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(300)
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('phase',choices=['issue','finalize','driver']);p.add_argument('--request',required=True);p.add_argument('--request-sha256',required=True);p.add_argument('--root-reviewed-source-sha256',required=True);p.add_argument('--stage-guard');p.add_argument('--stage-guard-sha256')
    for name in ('issue','cache','finalize'):p.add_argument('--'+name+'-guard');p.add_argument('--'+name+'-guard-sha256')
    a=p.parse_args()
    require(pin(__file__)['sha256']==a.root_reviewed_source_sha256,'exact reviewed issuer bytes')
    limit={'issue':8,'finalize':4,'driver':2}[a.phase];resource.setrlimit(resource.RLIMIT_CPU,(limit,limit));rp=dict(path=a.request,sha256=a.request_sha256)
    guards={name:dict(path=getattr(a,name+'_guard'),sha256=getattr(a,name+'_guard_sha256')) for name in ('issue','cache','finalize') if getattr(a,name+'_guard') is not None}
    if a.phase=='issue':require(not guards,'issue has no prior phase guards');result=issue(rp)
    elif a.phase=='finalize':result=finalize(rp,guards)
    else:result=driver(rp,dict(path=a.stage_guard,sha256=a.stage_guard_sha256),guards)
    print(json.dumps(dict(result=result,SELF_CPU_seconds=self_cpu()),sort_keys=True))
if __name__=='__main__':main()
