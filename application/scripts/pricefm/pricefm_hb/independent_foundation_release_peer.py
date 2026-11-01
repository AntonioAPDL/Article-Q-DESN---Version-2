"""Independent metadata peer for a fresh exact-node qualification route.

No network, R, scientific array interpretation, or root execution grant occurs.
Code is imported only after exact published/reviewed source hashes are checked.
"""
import argparse
import hashlib
import importlib
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

READS = {}
H_SHA = '7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
NATIVE_R_SHA = '9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
THREADS = ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','MKL_NUM_THREADS',
           'VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS','BLIS_NUM_THREADS')


def check(ok, message):
    if not ok:
        raise ValueError(message)


def strict(raw):
    def pairs(items):
        out = {}
        for key, value in items:
            check(key not in out, 'duplicate JSON key'); out[key] = value
        return out
    def bad(value): raise ValueError('nonfinite JSON: ' + value)
    def real(value):
        x = float(value); check(math.isfinite(x), 'nonfinite JSON exponent'); return x
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=bad, parse_float=real)


def raw(path, sha=None, *, code=False):
    p = Path(path)
    check(p.is_absolute() and '..' not in p.parts
          and not any(q.is_symlink() for q in (p,*p.parents)), 'physical absolute metadata/source path')
    check(code or p.suffix in {'.json','.stdout','.stderr','.sftp'}, 'metadata-only input')
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd,'rb') as f:
        before = os.fstat(f.fileno())
        check(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
              and before.st_uid in (0,os.getuid()) and before.st_size <= 32*1024**2,
              'bounded owned single-link input')
        data = f.read(32*1024**2+1); after = os.fstat(f.fileno())
    key = lambda x:(x.st_dev,x.st_ino,x.st_size,x.st_mtime_ns,x.st_ctime_ns)
    digest = hashlib.sha256(data).hexdigest()
    check(key(before)==key(after)==key(p.stat()) and len(data)==before.st_size
          and (sha is None or sha==digest), 'stable pinned bytes')
    READS[str(p)] = dict(path=str(p),sha256=digest,bytes=len(data))
    return data


def pin(path, *, code=False):
    return dict(path=str(path),sha256=hashlib.sha256(raw(path,code=code)).hexdigest())


def check_pin(value):
    check(type(value) is dict and set(value)=={'path','sha256'}
          and type(value['path']) is str and value['path'].startswith('/')
          and '..' not in PurePosixPath(value['path']).parts
          and type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}',value['sha256']),
          'strict absolute SHA pin')
    return value


def linked(value):
    check_pin(value); return strict(raw(value['path'],value['sha256']))


def local(path): return strict(raw(path))


def encoded(value): return (json.dumps(value,indent=2,sort_keys=True,allow_nan=False)+'\n').encode()


def write_new(path,value):
    p = Path(path)
    check(p.parent.resolve(strict=True)==p.parent and not p.is_symlink(), 'physical new output parent')
    with os.fdopen(os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),'wb') as f:
        f.write(encoded(value)); f.flush(); os.fsync(f.fileno())


def exact_int(value, wanted): return type(value) is int and value==wanted


def guard(value,cpu,wall):
    check(exact_int(value.get('returncode'),0) and exact_int(value.get('command_returncode'),0)
          and value.get('cap_reason') is None and exact_int(value.get('CPU_limit'),cpu)
          and type(value.get('aggregate_CPU_seconds')) in (int,float)
          and math.isfinite(value['aggregate_CPU_seconds']) and 0<=value['aggregate_CPU_seconds']<cpu
          and type(value.get('complete_lifecycle_wall_seconds')) in (int,float)
          and math.isfinite(value['complete_lifecycle_wall_seconds'])
          and 0<=value['complete_lifecycle_wall_seconds']<=wall
          and value.get('guardian_forced_monitor_stop') is False
          and all(value.get(k) is True for k in ('all_owned_descendants_reaped','independent_guardian',
              'kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU',
              'inherited_waited_history_included_once')), 'actual complete original guard')


def route_fields(config,scope,spec=None):
    node = scope.get('execution_node'); route = scope.get('qualification_route_id')
    check(type(node) is str and node in {'node-%02d'%i for i in range(15,22)}
          and scope.get('qualification_node')==node and config.get('node')==node
          and type(route) is str and re.fullmatch('[0-9a-f]{32}',route)
          and scope.get('cached_artifact_origin_node')=='node-13',
          'exact selected fresh node/route; historical cache origin is not execution proof')
    if spec is not None:
        check(spec.get('node')==node and spec.get('qualification_route_id')==route,
              'same selected node and route in current spec')
    return node,route




FOUNDATION_FILES={'__init__.py','profile_supervisor.py','startup_helper.py','startup_helper_fixture.py',
    'startup_helper_kernel_tests.py','startup_helper_metadata_fixture.R','startup_batch.py',
    'startup_batch_worker.py','startup_batch_kernel.py','startup_stop_candidate.py','startup_stop_helper.py',
    'startup_batch_stop.py','startup_batch_stop_worker.py','startup_batch_stop_kernel.py'}
SCIENTIFIC_FILES={'__init__.py','startup_helper.py','startup_batch_worker.py','profile_admission.py',
    'environment.py','runtime_archive.py','scientific_namespace_plan.py','scientific_namespace_contract.py',
    'scientific_allocation.py','scientific_code_install.py','scientific_metadata_owner.py',
    'scientific_namespace_fixture.R','scientific_boundary_fixture.R','scientific_batch.py','scientific_batch_worker.py'}
NUMERICAL_FILES=SCIENTIFIC_FILES|{'numerical_batch.py','numerical_stage_owner.py','numerical_stage_contract.py',
    'numerical_physical_admission.py','numerical_stage_worker.py','numerical_stage_bootstrap.R'}
NUMERICAL_ADMIN_FILES={'numerical_stage_prepare.py','numerical_critical_driver.py','numerical_independent_peer.py'}
INDEPENDENT_FILES={'independent_foundation_release_peer.py','independent_scientific_ready_peer.py',
    'independent_unallocated_drain_review.py','independent_complete_return_peer.py'}
EXTRA_ADMIN_FILES={'node_startup_watch.py','unallocated_tail.py'}
FIXED_SCIENCE={
    'application/R/pricefm_r129_al_fixedpoint_certificate.R':'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571',
    'application/R/524_toy_fullstate_consumer.R':'0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a',
    'application/R/525_project_fullstate_consumer.R':'57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2',
    'application/tests/r179_hb_toy.R':'662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190',
    'application/scripts/pricefm/r179_hb_bridge_or_pilot.R':'1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3'}


def closed_source_maps(publication,review,family,config):
    expected={'foundation':FOUNDATION_FILES,'scientific':SCIENTIFIC_FILES,'numerical':NUMERICAL_FILES}[family]
    for key,names in [('source_files',expected),('independent_source_files',INDEPENDENT_FILES),
                      ('extra_administrative_source_files',EXTRA_ADMIN_FILES)]:
        mapping=publication.get(key)
        check(type(mapping) is dict and set(mapping)==names and mapping==review.get(key)
              and all(type(sha) is str and re.fullmatch('[0-9a-f]{64}',sha) for sha in mapping.values()),
              'closed exact reviewed '+key+' filename/hash map before import')
    if family=='numerical':
        mapping=publication.get('administrative_source_files')
        check(type(mapping) is dict and set(mapping)==NUMERICAL_ADMIN_FILES
              and mapping==review.get('administrative_source_files')
              and all(type(sha) is str and re.fullmatch('[0-9a-f]{64}',sha) for sha in mapping.values()),
              'closed exact reviewed numerical administrative3 before import')
        science=config.get('scientific_sources')
        check(type(science) is dict and set(science)==set(FIXED_SCIENCE)
              and all(check_pin(ref) and ref['sha256']==FIXED_SCIENCE[name] for name,ref in science.items()),
              'closed unchanged canonical mathematical5 source pins before import')

    core=publication.get('core_source_maps')
    check(type(core) is dict and core==review.get('core_source_maps')
          and set(core)=={'source_family_files','administrative_source_files','scientific_source_files',
              'extra_administrative_source_files','independent_source_files'},
          'one closed actual frozen core map shared by all family reviews')
    families=core['source_family_files']
    check(type(families) is dict and set(families)=={'startup','scientific','numerical'},'closed three-family core closure')
    combined={}
    for key,names in [('startup',FOUNDATION_FILES),('scientific',SCIENTIFIC_FILES),('numerical',NUMERICAL_FILES)]:
        mapping=families[key]
        check(type(mapping) is dict and set(mapping)==names
              and all(type(sha) is str and re.fullmatch('[0-9a-f]{64}',sha) for sha in mapping.values()),
              'closed actual core family names and hashes')
        for name,sha in mapping.items():
            check(name not in combined or combined[name]==sha,'shared core source cannot differ between families')
            combined[name]=sha
    check(publication['source_files']==families['startup' if family=='foundation' else family]
          and core['independent_source_files']==publication['independent_source_files']
          and core['extra_administrative_source_files']==publication['extra_administrative_source_files']
          and type(core['administrative_source_files']) is dict and set(core['administrative_source_files'])==NUMERICAL_ADMIN_FILES
          and all(type(sha) is str and re.fullmatch('[0-9a-f]{64}',sha) for sha in core['administrative_source_files'].values())
          and core['scientific_source_files']==FIXED_SCIENCE,
          'exact current family/admin3/science5/extra2/independent4 core identity')
    if family=='numerical':
        check(publication['administrative_source_files']==core['administrative_source_files']
              and publication.get('scientific_source_files')==review.get('scientific_source_files')==FIXED_SCIENCE,
              'current numerical administration and unchanged published mathematical5 map')
    return expected


def validate_family_scope(c,s,family):
    roles={'foundation':['COMPUTE_RUNTIME_INVENTORY','EXACT_R46_STARTUP_METADATA'],
        'scientific':['SCIENTIFIC_NAMESPACE_NO_OPTIMIZER','SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'],
        'numerical':['TOY_PARITY','ZERO_UPDATE_BRIDGE']}
    if family=='foundation':funded=roles[family]
    else:
        check(c.get('role') in roles[family],'one closed funded role');funded=[c['role']]
    count=len(funded)
    check(c['schema']=={'foundation':'pricefm_startup_batch_config_v1','scientific':'pricefm_scientific_batch_config_v1',
              'numerical':'r182_numerical_batch_config_v1'}[family]
          and s['status']=={'foundation':'PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE',
              'scientific':'PROSPECTIVE_FRESH_SCIENTIFIC_METADATA_JOB_SCOPE',
              'numerical':'PROSPECTIVE_FRESH_FROZEN525_NUMERICAL_JOB_SCOPE'}[family]
          and all(exact_int(s[k],v) for k,v in dict(maximum_jobs=count,max_concurrent_jobs=1,
              compute_CPU_reservation=600*count,wall_seconds=1200,memory_MiB=8192,threads=1,cpus_per_task=1).items())
          and (family=='foundation' or s['roles']==funded)
          and s.get('automatic_retry') is False and s.get('requeue') is False,
          'whole exact family/role/CPU/wall/memory/one-thread purpose, no requeue/retry')
    root=Path(s['allowed_metadata_output_root']);registry=Path(c['registry'])
    check(str(root).startswith('/home/jaguir26/.local/state/pricefm/') and root.resolve(strict=True)==root
          and registry.parent==root and root.stat().st_uid==os.getuid() and root.stat().st_mode&0o077==0,
          'actual private persistent canonical root')
    budget=linked(c['native_control_budget'])
    check(budget['status']=={'foundation':'PROSPECTIVE_TWO_JOB_NATIVE_CONTROL_BUDGET',
              'scientific':'PROSPECTIVE_FRESH_SCIENTIFIC_METADATA_NATIVE_CONTROL_BUDGET',
              'numerical':'PROSPECTIVE_FRESH_NUMERICAL_NATIVE_CONTROL_BUDGET'}[family]
          and exact_int(budget['combined_native_control_CPU_ceiling'],240 if count==2 else 136)
          and budget['expires_epoch']==s['expires_epoch']
          and (family=='foundation' or budget['scope']==c['scope']),
          'ordinary native240/136 retained separately without failure-tail credit')
    allocations=dict(query_local4=4,query_remote4=4,independent_review4=4,drain_local4=4,
        drain_remote4=4,preparation4=4,closeout4=4)
    check(type(c['failure_tail_budgets']) is dict and set(c['failure_tail_budgets'])==set(funded),
          'one distinct prospective failure28 budget for every funded role')
    for role,ref in c['failure_tail_budgets'].items():
        b=linked(ref)
        check(b['schema']=='node_unallocated_failure_budget_v1'
              and b['status']=='PROSPECTIVE_DISTINCT_NODE_UNALLOCATED_FAILURE_TAIL_BUDGET'
              and b['parent_scope']==c['scope'] and b['role']==role
              and b['allocations']==allocations and all(type(x) is int for x in b['allocations'].values())
              and exact_int(b['total_administrative_CPU'],28)
              and all(exact_int(b[k],1) for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
              and b['expires_epoch']==s['expires_epoch'],'separate complete28 tail, original H3 unchanged')
    check(type(c['startup_watch_roots']) is dict and set(c['startup_watch_roots'])==set(funded),
          'one canonical paid watch root per funded role')
    if family!='foundation':
        placement=linked(c['placement_proof'])
        rows=[r for r in placement['rows'] if r.get('label')=='home']
        check(placement['same_original_H4_caps_and_stopped_rules'] is True
              and len(rows)==1 and rows[0]['root']==str(root.parent) and rows[0]['device']==root.stat().st_dev
              and exact_int(rows[0]['returncode'],0) and exact_int(rows[0]['files'],8),
              'actual independently retained original-H4 persistent-home placement')
        pg=linked(rows[0]['guard']);guard(pg,4,90);pv=strict(pg['stdout'])
        check(pv['status']=='OBSERVED_OWNED_METADATA_FSYNC_READBACK_NOT_LATENCY_GUARANTEE'
              and pv['root']==str(root.parent) and len(pv['rows'])==8,'actual eight-file fsync/readback proof')


def checked_core(config_path,family):
    check(family in {'foundation','scientific'},'supported metadata family')
    c=local(config_path);s=linked(c['scope']);now=time.time()
    node,route=route_fields(c,s)
    validate_family_scope(c,s,family)
    check(s['issued_epoch']<=now<s['expires_epoch'],'fresh role scope')
    auth=linked(c['canonical_authority'])
    check(auth['status']==dict(foundation='ROOT_AUTHORIZED_CANONICAL_STARTUP_BATCH_CONFIG',
              scientific='ROOT_AUTHORIZED_CANONICAL_SCIENTIFIC_METADATA_CONFIG',
              numerical='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG')[family]
          and auth['binding']=={k:v for k,v in c.items() if k!='canonical_authority'}
          and s['issued_epoch']<=auth['issued_epoch']<=now<auth['expires_epoch']<=s['expires_epoch'],
          'actual canonical complete configuration binding')
    pub=linked(c['publication']);review=linked(c['source_review'])
    check(pub['status'].startswith('PASS_') and 'PUBLICATION' in pub['status']
          and review['status'].startswith('PASS_REVIEWED_')
          and re.fullmatch('[0-9a-f]{40}',pub['commit'])
          and review['source_commit']==pub['commit']
          and pub['source_files']==review['source_files'],
          'actual published independently reviewed core source')
    closed_source_maps(pub,review,family,c)
    hashes=pub['source_files'];source=Path(c['source_dir'])
    check(len(hashes)==(14 if family=='foundation' else 15),'exact family compute source count')
    for name,sha in hashes.items():
        check(type(name) is str and '/' not in name and name.endswith(('.py','.R')),
              'closed source filename')
        raw(source/name,sha,code=True)
    own=pin(Path(__file__).absolute(),code=True)
    imap=pub.get('independent_source_files')
    check(type(imap) is dict and set(imap)=={'independent_foundation_release_peer.py',
              'independent_scientific_ready_peer.py','independent_unallocated_drain_review.py','independent_complete_return_peer.py'}
          and imap==review.get('independent_source_files')
          and imap.get(Path(__file__).name)==own['sha256'],
          'executing independent peer belongs to actual reviewed core')
    for name,sha in imap.items():
        check('/' not in name and name.endswith('.py'),'closed independent source filename')
        raw(source/name,sha,code=True)
    for name,sha in pub['extra_administrative_source_files'].items():raw(source/name,sha,code=True)
    if family=='numerical':
        for name,sha in pub['administrative_source_files'].items():raw(source/name,sha,code=True)
        for name,ref in c['scientific_sources'].items():raw(ref['path'],FIXED_SCIENCE[name],code=True)
    check(source.resolve(strict=True)==source,'physical frozen core root')
    return c,s,source,hashes


def import_core(source,names):
    sys.path.insert(0,str(source.parent))
    result=[]
    for name in names:
        module=importlib.import_module('pricefm_hb.'+name)
        check(Path(module.__file__).absolute()==source/(name+'.py'),'foreign cached/imported core module')
        result.append(module)
    for module_name,module in tuple(sys.modules.items()):
        if module_name=='pricefm_hb' or module_name.startswith('pricefm_hb.'):
            location=getattr(module,'__file__',None)
            check(location is not None and Path(location).absolute().parent==source,
                  'foreign imported dependency outside reviewed core')
    return result


def actual_action(config,role,action,guard_path,source_sha,limits):
    matches=[]
    for path in Path(config['registry']).glob('control_*.started.json'):
        value=local(path)
        if value.get('role')==role and value.get('action')==action:matches.append((path,value))
    check(len(matches)==1,'one actual durable native action')
    path,start=matches[0]
    pending=local(path.with_name(path.name.replace('.started.','.pending.')))
    g=local(guard_path);guard(g,limits['local_CPU'],limits['wall'])
    check(start.get('status')=='ACTION_STARTED_NOT_SUCCESS'
          and start.get('source_sha256')==source_sha and start.get('limits')==limits
          and type(start.get('command_pid')) is int and start['command_pid']>0
          and type(start.get('command_birth_ticks')) is int and start['command_birth_ticks']>0
          and g.get('session_id')==start['command_pid']
          and g.get('leader_start_ticks')==start['command_birth_ticks']
          and pending.get('status')=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
          and all(pending.get(k)==v for k,v in start.items() if k!='status')
          and strict(g['stdout'])==pending['result'],
          'actual source/PID/birth/native result and whole guardian closure')
    return pending['result'],pin(guard_path)


def accepted_chain(record_pin,expected_role,node,route,expected_source_hashes=None):
    record=linked(record_pin)
    check(record.get('status') in {'ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE',
          'ACCEPTED_COMPLETE_SCIENTIFIC_METADATA_ROLE'} and record.get('role')==expected_role
          and record.get('qualification_route_id')==route,'fresh exact-role canonical acceptance')
    g=linked(record['actual_accept_action_guard']);guard(g,5,180)
    candidate=strict(g['stdout'])
    check(candidate.get('status')=='ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD'
          and dict(candidate,status=record['status'],actual_accept_action_guard=record['actual_accept_action_guard'])==record,
          'canonical acceptance equals actual healthy guarded candidate')
    result=linked(record['result']);account=linked(record['accounting']);peer=linked(record['independent_review'])
    manifest=linked(record['full_return_manifest'])
    check(result.get('job_id')==account.get('job_id')==peer.get('job_id')==record['job_id']
          and result.get('role')==expected_role and result.get('node')==node
          and result.get('qualification_route_id')==route
          and account.get('complete') is True and account.get('terminal') is True
          and account.get('primary_charge_counted_once') is True
          and peer['status']==('PASS_REVIEWED_STARTUP_BATCH_ROLE' if expected_role in
              {'COMPUTE_RUNTIME_INVENTORY','EXACT_R46_STARTUP_METADATA'} else 'PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE')
          and peer['result']==record['result'] and peer['accounting']==record['accounting']
          and peer['return_manifest']==record['full_return_manifest'],
          'complete fresh same-node result/accounting/independent return')
    check(manifest.get('job_id')==record['job_id'] and manifest.get('scope_id')==record['scope_id'],
          'complete fresh return identity')
    rows=[x for x in manifest['files'] if x['relative']=='INVENTORY.json']
    check(len(rows)==1,'one returned actual inventory')
    ip=Path(record['full_return_manifest']['path']).parent/'INVENTORY.json'
    inventory=linked(dict(path=str(ip),sha256=rows[0]['sha256']))
    check(ip.stat().st_size==rows[0]['bytes'] and inventory.get('node')==node
          and inventory.get('job_id')==record['job_id']
          and inventory.get('qualification_route_id')==route,'actual fresh-node inventory, never cached-origin relabel')
    if expected_source_hashes is not None:
        check({k:v['sha256'] for k,v in result['sources'].items()}==expected_source_hashes,
              'same frozen source closure for qualification prerequisite')
    return record,result,inventory

WATCH_PROFILE=dict(maximum_probes=10,interval_seconds=20,deadline_seconds=300,
    probe_local_CPU=3,probe_remote_unknown_fee=3,probe_wall_seconds=45,combined_startup_watch_CPU_ceiling=60)


def review_startup_watch(config_path,c,s,packet,job,ready,family):
    """Independent raw reconciliation, without importing the producer watcher."""
    node,route=route_fields(c,s);role=packet['role'];now=time.time()
    watchroot=Path(c['startup_watch_roots'][role]);base=Path(s['allowed_metadata_output_root'])
    check(watchroot.resolve(strict=True)==watchroot and watchroot.is_relative_to(base)
          and watchroot!=base and watchroot.stat().st_uid==os.getuid()
          and watchroot.stat().st_mode&0o077==0,'one private canonical paid watch root')
    watch=local(watchroot/'STARTUP_WATCH.json')
    check(set(watch)=={'status','attempts','profile','elapsed_seconds','ready','authority','family','role'}
          and watch['status']=='STARTUP_READY_OBSERVED_AWAIT_ONE_SHOT_READY'
          and watch['profile']==WATCH_PROFILE and all(type(watch['profile'][k]) is int for k in WATCH_PROFILE)
          and type(watch['elapsed_seconds']) in (int,float) and math.isfinite(watch['elapsed_seconds'])
          and 0<=watch['elapsed_seconds']<=300 and watch['family']==family and watch['role']==role
          and type(watch['attempts']) is list and 1<=len(watch['attempts'])<=10,'closed bounded actual paid watch result')
    a=linked(watch['authority']);source=Path(c['source_dir'])/'node_startup_watch.py'
    sourcepin=pin(source,code=True);pub=linked(c['publication']);review=linked(c['source_review'])
    check(pub.get('extra_administrative_source_files',{}).get('node_startup_watch.py')==sourcepin['sha256']
          and review.get('extra_administrative_source_files')==pub.get('extra_administrative_source_files'),
          'published independently reviewed watcher source, no compute closure growth')
    original=pin(Path(c['source_dir'])/'profile_supervisor.py',code=True)
    check(original['sha256']==H_SHA and a['original_supervisor']==original
          and a['status']=='ROOT_AUTHORIZED_NODE_STARTUP_WATCH' and a['config']==pin(config_path)
          and a['parent_scope']==c['scope'] and a['role']==role and a['family']==family
          and a['source']==sourcepin and a['budget']==c['startup_watch_budget']
          and a['profile']==WATCH_PROFILE and exact_int(a['maximum_calls'],1) and a['automatic_retry'] is False
          and a['output_root']==str(watchroot)
          and s['issued_epoch']<=a['issued_epoch']<=now<a['expires_epoch']<=s['expires_epoch'],
          'actual one-shot source/config/original-H3-bound watcher authority')
    b=linked(c['startup_watch_budget'])
    if family=='numerical':
        check(b['status']=='PROSPECTIVE_FRESH_NUMERICAL_STARTUP_WATCH_BUDGET','numeric existing separate startup60')
    else:
        count=2 if family=='startup' else 1
        check(b['status']=='PROSPECTIVE_FRESH_NODE_STARTUP_WATCH_BUDGET'
              and role in b['roles'] and len(b['roles'])==count
              and exact_int(b['combined_startup_watch_CPU_ceiling'],60*count)
              and exact_int(s['administrative_allocations']['startup_watch'+str(60*count)],60*count),
              'each exact fresh role has fully priced startup60 local/remote')
    check(b['scope']==c['scope'] and b['profile']==WATCH_PROFILE and b['expires_epoch']==s['expires_epoch'],
          'actual startup funding same config scope and clock')
    intent=local(watchroot/'STARTUP.INTENT.json')
    check(intent==dict(status='PAID_NODE_STARTUP_WATCH_STARTED_NOT_READY',authority=watch['authority'],
        source=sourcepin,config=pin(config_path),role=role,family=family),'one actual durable whole-watch intent')
    folder=watchroot/'startup';check(folder.resolve(strict=True)==folder and folder.stat().st_mode&0o077==0,
          'private complete raw-probe evidence')
    ready_pin=pin(Path(c['registry'])/role/'READY.json');canonical=raw(ready_pin['path'],ready_pin['sha256'])
    check(strict(canonical)==ready and ready['job_id']==job['job_id'] and ready['scope_id']==packet['scope_id']
          and ready['node']==node and ready['qualification_route_id']==route
          and ready['inventory']['qualification_route_id']==route,'actual current one-shot READY exact selected route')
    epoch=ready['observed_epoch'];age=180 if family=='startup' else 80 if family=='scientific' else 90
    check(type(epoch) in (int,float) and math.isfinite(epoch) and 0<=now-epoch<age,'current observed READY freshness')
    files=set();previous=None;first=None;batch=packet['sources'][dict(startup='startup_batch_stop.py',scientific='scientific_batch.py',numerical='numerical_batch.py')[family]]['sha256']
    for index,attempt in enumerate(watch['attempts']):
        check(type(attempt) is dict and set(attempt)=={'guard','result'},'one closed paid probe reference')
        stem='probe_%02d'%index;final=index==len(watch['attempts'])-1
        files|={stem+suffix for suffix in ['.intent.json','.native.json','.RESULT.json','.guard.json','.guard.stderr']}
        gp=pin(folder/(stem+'.guard.json'));g=linked(gp);guard(g,3,45)
        v=local(folder/(stem+'.RESULT.json'))
        expected={'status','probe_index','family','role','job_id','scope_id','execution_node','qualification_route_id',
            'config','driver_authority','watch_source','batch_source_sha256','command_pid','command_birth_ticks',
            'observed_epoch','raw_observation','production_admission'}
        check(set(v)==expected|({'ready'} if final else set()) and attempt['guard']==gp
              and attempt['result']==v==strict(g['stdout'])
              and exact_int(v['probe_index'],index)
              and v['status']==('STARTUP_READY_PRESENT_MATCHED_NO_RELEASE' if final else 'STARTUP_WAITING_READY_ABSENT_NO_RELEASE')
              and v['family']==family and v['role']==role and v['job_id']==job['job_id']
              and v['scope_id']==packet['scope_id'] and v['execution_node']==node and v['qualification_route_id']==route
              and v['config']==pin(config_path) and v['driver_authority']==watch['authority']
              and v['watch_source']==sourcepin and v['batch_source_sha256']==batch
              and v['production_admission'] is False,'actual source/config/authority/job/index/role/node-bound raw probe')
        check(type(v['command_pid']) is type(v['command_birth_ticks']) is int and v['command_pid']>0
              and v['command_birth_ticks']>0 and g['session_id']==v['command_pid']
              and g['leader_start_ticks']==v['command_birth_ticks'],'exact original H3 probe PID and birth')
        observed=v['observed_epoch']
        check(type(observed) in (int,float) and math.isfinite(observed)
              and s['issued_epoch']<=observed<=now and (previous is None or previous<=observed),'ordered finite actual observations')
        if first is None:first=observed
        previous=observed;one=local(folder/(stem+'.intent.json'))
        check(set(one)=={'status','operation','epoch'} and one['status']=='INTENT_NOT_SUCCESS'
              and one['operation']==stem and type(one['epoch']) in (int,float) and math.isfinite(one['epoch'])
              and s['issued_epoch']<=one['epoch']<=observed,'one durable actual indexed pre-action intent')
        np=pin(folder/(stem+'.native.json'));native=linked(np)
        check(v['raw_observation']==np and set(native)=={'argv','returncode','stdout','stderr'}
              and native['argv']==['test','-f',packet['remote_root']+'/READY.json']
              and exact_int(native['returncode'],0 if final else 1)
              and native['stdout']==native['stderr']=='','exact absent-before-present native file test, no error-as-waiting')
        raw(folder/(stem+'.guard.stderr'))
        if final:
            files|={stem+suffix for suffix in ['.READY.json','.transfer.json','.sftp']}
            downloaded=pin(folder/(stem+'.READY.json'))
            check(v['ready']==watch['ready']==downloaded and downloaded['sha256']==ready_pin['sha256']
                  and raw(downloaded['path'],downloaded['sha256'])==canonical,'actual final SFTP READY equals canonical one-shot bytes')
            transfer=local(folder/(stem+'.transfer.json'))
            check(set(transfer)=={'returncode','stdout','stderr'} and exact_int(transfer['returncode'],0)
                  and type(transfer['stdout']) is type(transfer['stderr']) is str,'actual successful final transfer')
            command=('get '+packet['remote_root']+'/READY.json '+downloaded['path']+'\n').encode()
            check(raw(folder/(stem+'.sftp'))==command,'exact one-command owned READY download source and destination')
    check(previous-first<=watch['elapsed_seconds'] and {x.name for x in folder.iterdir()}==files,
          'complete bounded paid-probe artifact closure, no redundant/foreign observations')
    return pin(watchroot/'STARTUP_WATCH.json')

ROLES=('COMPUTE_RUNTIME_INVENTORY','EXACT_R46_STARTUP_METADATA')
CAPS={'packet':2,'plan':2,'release':4}


def foundation_context(config_path,role,prepare_or_ready_guard,packet_review=None):
    c,s,source,hashes=checked_core(config_path,'foundation');node,route=route_fields(c,s)
    check(role in ROLES and s['status']=='PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE'
          and exact_int(s['compute_CPU_reservation'],1200)
          and exact_int(s['max_concurrent_jobs'],1),'fresh paired kernel/R scope')
    root=Path(c['registry'])/role;packet=local(root/'PACKET.json');spec=local(root/'packet/SPEC.json')
    route_fields(c,s,spec)
    check(packet['role']==spec['role']==role and packet['remote_root']==spec['remote_root']
          and packet['scope_id']==spec['scope_id']
          and packet['spec_sha256']==pin(root/'packet/SPEC.json')['sha256']
          and spec['scope']==dict(path=packet['remote_root']+'/Q_SCOPE.json',sha256=c['scope']['sha256'])
          and spec['sources']==packet['sources']
          and {n:v['sha256'] for n,v in spec['sources'].items()}==hashes
          and exact_int(spec['aggregate_CPU_reservation'],600)
          and exact_int(spec['wall_seconds'],1200) and exact_int(spec['memory_MiB'],8192)
          and exact_int(spec['threads'],1) and spec['expires_epoch']==s['expires_epoch'],
          'closed exact paired-role source, packet, scope and resource identity')
    if packet_review is None:
        result,gp=actual_action(c,role,'prepare',prepare_or_ready_guard,hashes['startup_batch_stop.py'],
                               dict(local_CPU=4,wall=120))
        check(result==packet,'actual guarded prepare returned exact packet')
        return c,s,source,hashes,root,packet,spec,None,None,dict(prepare=gp)
    prior=local(packet_review)
    check(prior['status']=='PASS_REVIEWED_STARTUP_BATCH_PACKET'
          and prior['config']==pin(config_path) and prior['packet']==pin(root/'PACKET.json')
          and prior['qualification_route_id']==route,'actual independent packet review')
    job=local(root/'JOB.json');ready=local(root/'READY.json');facts=ready['inventory']
    check(ready['status']=='READY_SOURCE_BOUND_COMPUTE_METADATA' and ready['role']==role
          and ready['job_id']==job['job_id'] and type(job['job_id']) is str and job['job_id'].isdigit()
          and ready['scope_id']==job['scope_id']==packet['scope_id']
          and ready['node']==node and ready.get('qualification_route_id')==route
          and ready['spec_sha256']==packet['spec_sha256']
          and ready['sources']==packet['sources'] and ready['expires_epoch']==s['expires_epoch']
          and type(ready['affinity']) is list and len(ready['affinity'])==1
          and exact_int(ready['cpus_per_task'],1) and exact_int(ready['models'],0),
          'fresh same-node source/job-bound zero-model READY')
    check(facts['status']=='COMPUTE_RUNTIME_FACTS_NO_R' and facts['job_id']==job['job_id']
          and facts['node']==node and facts.get('qualification_route_id')==route
          and facts['affinity']==ready['affinity'] and exact_int(facts['cpus_per_task'],1)
          and facts['scientific_data_access'] is False
          and exact_int(facts['R_executions'],0) and exact_int(facts['optimizer_invocations'],0)
          and facts['python']==dict(path=c['cached_python'],sha256=c['cached_python_sha256'])
          and facts['filesystem']['path']==packet['remote_root'],'current actual runtime facts')
    guards={}
    limits=dict(prepare=dict(local_CPU=4,wall=120),
        stage=dict(local_CPU=18,remote_unknown_fee=18,wall=300,maximum_calls=1),
        submit=dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1),
        ready=dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1))
    for action in ['prepare','stage','submit']:
        matching=[]
        for vp in Path(c['registry']).glob('control_*.validated.json'):
            value=local(vp);start=linked(value['started'])
            if start['role']==role and start['action']==action:matching.append(value)
        check(len(matching)==1 and matching[0]['status']=='ACTUAL_ACTION_GUARD_PASSED',
              'one fully validated predecessor action')
        _,guards[action]=actual_action(c,role,action,matching[0]['guard']['path'],
                                       hashes['startup_batch_stop.py'],limits[action])
    value,guards['ready']=actual_action(c,role,'ready',prepare_or_ready_guard,
                                       hashes['startup_batch_stop.py'],limits['ready'])
    check(value==ready,'actual whole READY guard returned exact current READY')
    guards['startup_watch']=review_startup_watch(config_path,c,s,packet,job,ready,'startup')
    check(not(root/'ROLE_FAILED_SPENT.json').exists() and not(root/'release.intent.json').exists()
          and not(root/'ACCEPTED.json').exists(),'fresh unreleased unspent role')
    return c,s,source,hashes,root,packet,spec,job,ready,guards


def validate_R_plan(plan,child,manifest,ready,spec,scope,scope_pin,hashes):
    node,route=route_fields(dict(node=scope['execution_node']),scope,spec)
    remote=spec['remote_root'];nonce=hashlib.sha256((ready['scope_id']+'/'+ready['job_id']+'/R46-metadata').encode()).hexdigest()[:32]
    check(plan['schema']=='pricefm_startup_helper_plan_v1' and plan['role']=='R_STARTUP_METADATA_ONLY'
          and plan['nonce']==nonce and plan['limits']==dict(CPU=30,wall=120,output_cap=1048576)
          and plan['placement']==dict(kind='SLURM_SINGLE_CPU_METADATA',job_id=ready['job_id'],node=node),
          'fixed single metadata R helper purpose')
    sources=dict(adapter=spec['sources']['startup_stop_helper.py'],
        supervisor=spec['sources']['startup_stop_candidate.py'],
        fixture=spec['sources']['startup_helper_metadata_fixture.R'],
        original_supervisor=spec['sources']['profile_supervisor.py'],
        original_adapter=spec['sources']['startup_helper.py'])
    check(plan['sources']==sources and sources['original_supervisor']['sha256']==H_SHA,
          'unchanged original guard and corrected five-key helper source binding')
    rows=manifest['files'];check(type(rows) is list and 0<len(rows)<=2048,'finite original R carrier')
    expected=[];total=0;seen=set()
    for row in rows:
        rel=PurePosixPath(row['relative'])
        check(str(rel)==row['relative'] and not rel.is_absolute() and '..' not in rel.parts
              and rel.parts[0] in {'R_HOME','lib'} and str(rel) not in seen
              and type(row['bytes']) is int and 0<=row['bytes']<=64*1024**2
              and type(row['mode']) is int and 0<=row['mode']<=0o777
              and re.fullmatch('[0-9a-f]{64}',row['sha256']),
              'closed unique code-only carrier member')
        seen.add(str(rel));expected.append(dict(path=remote+'/runtime_carrier/'+str(rel),sha256=row['sha256']))
        total+=row['bytes']
    check(total==manifest['total_bytes'],'carrier declared exact total')
    carrier=ready['carrier']
    check(carrier['status']=='DURABLE_BYTE_IDENTICAL_RUNTIME_CARRIER_INSTALLED'
          and carrier['manifest']==spec['carrier_manifest'] and carrier['root']==remote+'/runtime_carrier'
          and carrier['files']==expected and carrier['file_count']==len(rows) and carrier['total_bytes']==total
          and carrier['all_writes_before_file_sync'] is True and carrier['no_original_runtime_mutation'] is True,
          'actual durable carrier bytes, never installed-runtime compatibility by descriptor')
    helpers={};aliases=[]
    for name in ['which','uname']:
        value=ready['inventory']['helpers'][name];target=value['resolved_file'];check_pin(target)
        check(value['logical_path']=='/usr/bin/'+name and type(value['bytes']) is int
              and 0<value['bytes']<=64*1024**2 and target['path'].startswith('/usr/')
              and target not in expected,'actual resolved native helper alias')
        expected.append(target);total+=value['bytes'];helpers[name]=target
        aliases.append(dict(logical_path=value['logical_path'],resolved_file=target))
    check(len(expected)<=2048 and total<=128*1024**2 and plan['runtime_files']==expected,
          'unchanged complete helper/runtime2048files128MiB envelope')
    rhome=remote+'/runtime_carrier/R_HOME'
    native=dict(path=rhome+'/bin/exec/R',sha256=NATIVE_R_SHA)
    check(native in expected and plan['supervisor_python']==ready['inventory']['python']
          and plan['runtime']==dict(kind='NATIVE_R_METADATA',version='4.6.0',executable=native,
              R_home=rhome,uname=helpers['uname'],which=helpers['which'],helper_aliases=aliases),
          'exact R4.6 native metadata runtime')
    env={k:'1' for k in THREADS}
    env.update(PATH='/usr/bin:/bin',LC_ALL='C',LANG='C',TZ='UTC',HOME=remote,TMPDIR=remote,
        R_HOME=rhome,R_ARCH='',R_DOC_DIR=rhome+'/doc',R_INCLUDE_DIR=rhome+'/include',R_SHARE_DIR=rhome+'/share',
        R_LIBS_USER='',R_LIBS_SITE='',LD_LIBRARY_PATH=rhome+'/lib:'+remote+'/runtime_carrier/lib',
        SLURM_JOB_ID=ready['job_id'],SLURMD_NODENAME=node,SLURM_CPUS_PER_TASK='1')
    check(plan['environment']==env and plan['command']==[native['path'],'--vanilla','--slave','--no-save',
        '--no-restore','--file='+sources['fixture']['path'],'--args',nonce]
          and plan['output_dir']==remote+'/result/R_STARTUP_'+nonce,'closed loader/env/command/output')
    check(child['status']=='PROSPECTIVE_PRICEFM_STARTUP_COMPUTE_QUALIFICATION_SCOPE'
          and child['parent']==scope_pin and child['role']=='R_STARTUP_METADATA_ONLY'
          and child['job_id']==ready['job_id'] and child['node']==node
          and child['expires_epoch']==scope['expires_epoch']
          and scope['issued_epoch']<=child['issued_epoch']<=time.time()<child['expires_epoch']
          and child['funded_within_role600']==30 and child['no_new_compute_reservation'] is True
          and child['optimizer_invocations']==0 and child['scientific_data_access'] is False,
          'fresh exact within-role helper30 root child authority')
    return plan


def review_foundation(config_path,role,ready_guard,packet_review,peer_scope,bundle,phase='release'):
    check(phase in CAPS,'one declared independent phase')
    c,s,source,hashes,root,packet,spec,job,ready,guards=foundation_context(
        config_path,role,ready_guard,None if phase=='packet' else packet_review)
    node,route=route_fields(c,s,spec);own=linked(peer_scope);out=Path(bundle)
    check(own['parent']==c['scope'] and own['role']==role
          and own['allocations']['independent_release_peer8']==8
          and own['allowed_packet_review_output_root' if phase=='packet' else 'allowed_review_output_root']==str(out)
          and out.is_dir() and out.stat().st_uid==os.getuid() and out.stat().st_mode&0o077==0
          and own['issued_epoch']<=time.time()<own['expires_epoch']<=s['expires_epoch'],
          'separate finite independent peer8 private output scope')
    if phase=='packet':
        value=dict(status='PASS_REVIEWED_STARTUP_BATCH_PACKET',config=pin(config_path),
            packet=pin(root/'PACKET.json'),spec=pin(root/'packet/SPEC.json'),prepare_guard=guards['prepare'],
            role=role,execution_node=node,qualification_route_id=route,source_review=c['source_review'],
            source_publication=c['publication'],review_source=pin(__file__,code=True),no_execution_authority=True)
        write_new(out/'PACKET_REVIEW.json',value);return value
    remote=packet['remote_root']+'/release/'
    rp=lambda name:dict(path=remote+name,sha256=pin(out/name)['sha256'])
    limits=dict(kernel_matrix_CPU_reservation=30,kernel_case_caps=[4]*6,kernel_driver_SELF_cap=6,R_executions=0)
    if role==ROLES[0]:
        check(phase=='release' and ready['carrier'] is None,'kernel release has no R payload')
    else:
        first=Path(c['registry'])/ROLES[0]
        prior,prior_result,prior_inventory=accepted_chain(pin(first/'ACCEPTED.json'),ROLES[0],node,route,hashes)
        check(prior['kernel_matrix_pass'] is True and spec['accepted_inventory']==prior,
              'fresh accepted same14-source same-route kernel before R')
        check(local(sorted(first.glob('record_*.json'))[-1])['state']=='ACCEPTED',
              'kernel claim finalized before R')
        manifest=linked(c['carrier_manifest']);integrity=linked(c['carrier_integrity_review'])
        check(integrity['status']=='PASS_REVIEWED_STREAMING_RUNTIME_ARCHIVE_REAL_ARTIFACT'
              and integrity['manifest']==c['carrier_manifest']
              and integrity['archive']==c['carrier'],'independent original carrier byte integrity')
        plan=local(out/'R_STARTUP_PLAN.json');child=local(out/'R_CHILD_SCOPE.json')
        validate_R_plan(plan,child,manifest,ready,spec,s,c['scope'],hashes)
        plan_pin=rp('R_STARTUP_PLAN.json')
        if phase=='plan':
            value=dict(status='PASS_REVIEWED_STARTUP_HELPER_SOURCE_AND_PLAN',plan=plan_pin,
                sources=plan['sources'],limits=plan['limits'],placement=plan['placement'],
                current_READY=pin(root/'READY.json'),current_READY_guard=guards['ready'],
                parent=c['scope'],qualification_route_id=route,review_source=pin(__file__,code=True),
                no_R_or_runtime_acceptance=True)
            write_new(out/'R_REVIEW.json',value);return value
        review=local(out/'R_REVIEW.json');authority=local(out/'R_AUTHORITY.json')
        check(review['status']=='PASS_REVIEWED_STARTUP_HELPER_SOURCE_AND_PLAN'
              and review['plan']==plan_pin and review['sources']==plan['sources']
              and review['limits']==plan['limits'],'actual independently reviewed R plan')
        check(authority['schema']=='pricefm_startup_helper_authority_v1'
              and authority['status']=='ROOT_AUTHORIZED_SOURCE_BOUND_STARTUP_HELPER_PROOF'
              and authority['plan']==plan_pin and authority['source_review']==rp('R_REVIEW.json')
              and authority['root_scope']==rp('R_CHILD_SCOPE.json')
              and authority['role']==plan['role'] and authority['sources']==plan['sources']
              and authority['limits']==plan['limits'] and authority['placement']==plan['placement']
              and exact_int(authority['executions'],1) and authority['no_real_target_data_or_optimizer'] is True
              and authority['allowed_output_parent']==packet['remote_root']+'/result'
              and s['issued_epoch']<=authority['issued_epoch']<=time.time()<authority['expires_epoch']<=s['expires_epoch'],
              'root authority issued only after exact independent R-plan review')
        limits=dict(R_guard_CPU=30,R_guard_wall=120,R_executions=1,scientific_data_access=False)
    value=dict(status='PASS_REVIEWED_STARTUP_BATCH_RELEASE',issued_epoch=time.time(),expires_epoch=s['expires_epoch'],
        role=role,job_id=job['job_id'],node=node,qualification_route_id=route,scope_id=packet['scope_id'],
        scope=c['scope'],scope_sha256=c['scope']['sha256'],ready_sha256=pin(root/'READY.json')['sha256'],
        spec_sha256=packet['spec_sha256'],sources=spec['sources'],actual_READY=pin(root/'READY.json'),
        actual_native_guards=guards,packet=pin(root/'PACKET.json'),packet_review=pin(packet_review),
        source_review=c['source_review'],source_publication=c['publication'],review_scope=peer_scope,
        release_limits=limits,review_source=pin(__file__,code=True),read_set=list(READS.values()),
        no_payload_or_runtime_acceptance_preclaimed=True,independently_authored=True)
    write_new(out/'PEER_RELEASE.json',value);return value


def main():
    check(os.sched_getaffinity(0)=={31},'administrative31 only')
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['config','role','guard','scope','bundle']:p.add_argument('--'+name,required=True)
    p.add_argument('--phase',choices=tuple(CAPS),default='release');p.add_argument('--packet-review')
    a=p.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU,(CAPS[a.phase],CAPS[a.phase]))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(30)
    out=Path(a.bundle);intent=out/(a.phase+'.peer.INTENT.json')
    write_new(intent,dict(status='INDEPENDENT_PEER_PHASE_STARTED_NO_REPLAY',phase=a.phase,
        source=pin(__file__,code=True),config=pin(a.config),scope=pin(a.scope),issued_epoch=time.time()))
    result=review_foundation(a.config,a.role,a.guard,a.packet_review,pin(a.scope),a.bundle,a.phase)
    u=resource.getrusage(resource.RUSAGE_SELF)
    write_new(out/(a.phase+'.peer.RECEIPT.json'),dict(status='COMPLETED_INDEPENDENT_METADATA_PHASE',
        phase=a.phase,result_status=result['status'],SELF_CPU_seconds=u.ru_utime+u.ru_stime,
        phase_CPU_cap=CAPS[a.phase],all_peer8_fees_retained=True,read_set=list(READS.values())))
    print(json.dumps(dict(status=result['status'],phase=a.phase,SELF_CPU=u.ru_utime+u.ru_stime)))


if __name__=='__main__':main()

