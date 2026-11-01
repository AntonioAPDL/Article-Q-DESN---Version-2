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

ALLOCATIONS=dict(query_local4=4,query_remote4=4,independent_review4=4,drain_local4=4,
    drain_remote4=4,preparation4=4,closeout4=4)
SACCT_FIELDS='JobIDRaw,JobName%128,User,UID,Account,Partition,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,ReqCPUS,Start,End,NodeList'
OBS_KEYS={'ready','release','return','marker','lock'}
FAILED_ACTION_LIMITS=dict(
    ready=dict(local_CPU=6,remote_unknown_fee=6,wall=330,maximum_calls=1),
    release=dict(local_CPU=4,remote_unknown_fee=4,wall=180,maximum_calls=1),
    observe=dict(local_CPU=3,remote_unknown_fee=3,wall=45,maximum_calls=3),
    collect=dict(local_CPU=6,remote_unknown_fee=6,wall=300,maximum_calls=1),
    accept=dict(local_CPU=5,remote_unknown_fee=5,wall=180,maximum_calls=1),
    cancel=dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1),
    retire_failed=dict(local_CPU=3,wall=120))


def exact_keys(value,keys,label):
    check(type(value) is dict and set(value)==set(keys),label)


def finite(value,label):
    check(type(value) in (int,float) and math.isfinite(value),label);return value


def native_result(value,argv,rc,label):
    exact_keys(value,{'argv','returncode','stdout','stderr'},label+' fields')
    check(value['argv']==argv and type(value['argv']) is list
          and all(type(x) is str for x in value['argv'])
          and exact_int(value['returncode'],rc) and type(value['stdout']) is type(value['stderr']) is str
          and value['stderr']=='' and len(value['stdout'].encode())<=2*1024**2,label+' native command/result')
    return value['stdout']


def failed_action_guard(value,start,expected_source,family=None):
    """A drained failed action may have only the typed OwnedStopError witness."""
    action=start.get('action');expected=FAILED_ACTION_LIMITS.get(action)
    if action=='reconcile' and family=='numerical':expected=dict(local_CPU=3,wall=120)
    limits=start.get('limits')
    check(expected is not None and type(limits) is dict and set(limits)==set(expected)
          and all(type(limits[k]) is int and limits[k]==v for k,v in expected.items()),
          'closed original action and complete exact typed limits, even absent failed-guard CPU_limit')
    check(start.get('status')=='ACTION_STARTED_NOT_SUCCESS'
          and start.get('source_sha256')==expected_source
          and type(start.get('command_pid')) is int and start['command_pid']>0
          and type(start.get('command_birth_ticks')) is int and start['command_birth_ticks']>0
          and type(start.get('limits')) is dict and type(start['limits'].get('local_CPU')) is int,
          'actual immutable failed-action journal identity')
    check(type(value.get('returncode')) is int and value['returncode']!=0
          and value.get('all_owned_descendants_reaped') is True
          and value.get('independent_guardian') is True
          and value.get('guardian_forced_monitor_stop') is False
          and value.get('guardian_included_in_CPU') is True
          and value.get('inherited_waited_history_included_once') is True,
          'actual failed original guard completely drained; no action success inferred')
    witness=value.get('owned_stop_witness')
    if witness is not None:
        check(type(witness) is dict and witness.get('schema')=='r164_owned_stop_failure_witness_v1'
              and witness.get('uid')==os.getuid() and witness.get('monitor_affinity')==[31]
              and witness.get('states_are_not_accepted_for_accounting') is True,
              'typed original owned-stop witness')
    sid=value.get('session_id',witness.get('session_id') if witness else None)
    birth=value.get('leader_start_ticks',witness.get('leader_start_ticks') if witness else None)
    check(type(sid) is type(birth) is int and sid==start['command_pid']
          and birth==start['command_birth_ticks'],'failed guard journal PID/birth exact')
    if 'CPU_limit' in value:check(exact_int(value['CPU_limit'],start['limits']['local_CPU']),'failed guard unchanged cap')
    if witness is not None:
        check(witness['session_id']==sid and witness['leader_start_ticks']==birth,
              'nested original witness cannot contradict top-level identity')
        items=witness.get('exact_proved_owned_items')
        check(type(items) is list and len(items)>0 and any(x.get('pid')==sid and x.get('start_ticks')==birth
              and x.get('sid')==sid and x.get('uid')==os.getuid() for x in items),'nested witness proves actual leader')


def failure_basis(scope,config,job,packet,family_source):
    value=scope['failure_evidence'];kind=value.get('kind')
    if kind=='FAILED_NATIVE_ACTION_DRAINED':
        exact_keys(value,{'kind','failed_guard','failed_started'},'closed failed-action evidence union')
        start=linked(value['failed_started']);g=linked(value['failed_guard'])
        check(start['role']==scope['role'],'same failed role')
        failed_action_guard(g,start,family_source['sha256'],scope['family'])
        check(start['action'] not in {'prepare','stage','submit'},'known submitted job stage required; ambiguous submit blocked')
    elif kind=='STARTUP_DEADLINE_NO_RELEASE':
        exact_keys(value,{'kind','failure_receipt','cancel_guard','cancel_started'},'closed startup-deadline evidence union')
        receipt=linked(value['failure_receipt']);start=linked(value['cancel_started']);g=linked(value['cancel_guard'])
        check(receipt['status'] in {'STARTUP_FAILED_NO_RELEASE','ROLE_FAILED_SPENT',
              'STARTUP_DEADLINE_EXHAUSTED_NO_RELEASE','CRITICAL_DRIVER_FAILED_SPENT_NO_AUTORETRY'}
              and receipt.get('job_id')==job['job_id'] and receipt.get('role')==scope['role']
              and receipt.get('no_release') is True,'actual spent startup deadline, never manufactured cancellation')
        guard(g,4,45)
        check(start['status']=='ACTION_STARTED_NOT_SUCCESS' and start['action']=='cancel'
              and start['role']==scope['role'] and start['source_sha256']==family_source['sha256']
              and start['limits']==dict(local_CPU=4,remote_unknown_fee=4,wall=45,maximum_calls=1)
              and g['session_id']==start['command_pid'] and g['leader_start_ticks']==start['command_birth_ticks'],
              'actual healthy same-source cancellation guard')
        pending_path=Path(value['cancel_started']['path'])
        pending=local(pending_path.with_name(pending_path.name.replace('.started.','.pending.')))
        check(pending['status']=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
              and all(pending.get(k)==v for k,v in start.items() if k!='status')
              and strict(g['stdout'])==pending['result'] and pending['result']['job_id']==job['job_id'],
              'actual healthy known-job cancellation native result')
    else:raise ValueError('no admitted independently reviewed failure basis')


def expected_paths(config,packet,scope_id):
    remote=packet['remote_root'];lock=config['remote_namespace']+'/qualification.lock'
    return dict(ready=remote+'/READY.json',release=remote+'/release/RELEASE.json',
        return_=remote+'/result/RETURN_MANIFEST.json',marker=lock+'/OWNED_'+scope_id,lock=lock)


def accounting(raw_value,job_id,job_name,uid):
    text=native_result(raw_value,['sacct','-j',job_id,'-n','-P','--format='+SACCT_FIELDS],0,'exact raw SACCT')
    lines=[x for x in text.splitlines() if x.strip()]
    check(len(lines)==1,'one exact primary unallocated accounting row, no step or foreign allocations')
    columns=lines[0].split('|')
    if len(columns)==16 and columns[-1]=='':columns.pop()
    check(len(columns)==15,'original explicit SACCT15 schema')
    jid,name,user,raw_uid,account,partition,state,exit_code,cpu,elapsed,alloc,requested,start,end,node=columns
    check(jid==job_id and name==job_name and user=='jaguir26' and raw_uid==str(uid)
          and account==partition=='128x24' and state=='CANCELLED' and exit_code=='0:0'
          and cpu in {'00:00:00','00:00.000','00:00:00.000'} and elapsed=='0'
          and alloc=='0' and requested=='1' and start in {'None','Unknown','N/A'}
          and node in {'None','None assigned','(null)','Unknown','N/A'}
          and end not in {'','None','Unknown','N/A'},'exact owned terminal Alloc0/CPU0/no-start/no-node cancellation')
    return dict(job_id=jid,state=state,AllocCPUS=0,ReqCPUS=1,TotalCPU_seconds=0,
        ElapsedRaw=0,never_allocated=True,raw_primary_counted_once=True)


def stat_identity(raw_value,lock,marker):
    fmt='%u|%d|%i|%s|%h|%f|%n\n'
    text=native_result(raw_value,['stat','--printf='+fmt,'--',lock,marker],0,'exact no-follow native claim stat')
    lines=text.splitlines();check(len(lines)==2,'one lock and one marker identity')
    out={}
    for label,path,line in zip(['lock','marker'],[lock,marker],lines):
        fields=line.split('|');check(len(fields)==7 and fields[-1]==path,'exact stat path')
        check(all(re.fullmatch('[0-9]+',x) for x in fields[:5])
              and re.fullmatch('[0-9a-fA-F]+',fields[5]),'numeric native identity fields')
        uid,dev,ino,size,nlink=map(int,fields[:5]);mode=int(fields[5],16)
        check(uid==os.getuid() and dev>=0 and ino>0 and size>=0 and nlink>=1,'owned real claim identity')
        check((stat.S_ISDIR(mode) if label=='lock' else stat.S_ISREG(mode))
              and (label=='lock' or size==0 and nlink==1),'owned directory and zero-byte single-link regular marker, no symlink')
        out[label]=dict(path=path,uid=uid,device=dev,inode=ino,bytes=size,nlink=nlink,mode=mode)
    return out


def review_query(result_path,guard_path,tail_scope_path,output_path):
    tpin=pin(tail_scope_path);scope=linked(tpin);now=time.time()
    check(scope['schema']=='node_unallocated_failure_tail_scope_v1'
          and scope['status']=='PROSPECTIVE_EXACT_UNALLOCATED_NODE_ROLE_DRAIN_SCOPE',
          'distinct prospectively issued exact Alloc0 failure purpose')
    config=linked(scope['config']);parent=linked(scope['parent_scope'])
    node,route=route_fields(config,parent)
    check(scope['parent_scope']==config['scope'] and scope['execution_node']==scope['qualification_node']==node
          and scope['qualification_route_id']==route and scope['allocations']==ALLOCATIONS
          and all(exact_int(v,4) for v in scope['allocations'].values())
          and exact_int(scope['total_administrative_CPU'],28)
          and all(exact_int(scope[k],1) for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
          and parent['issued_epoch']<=scope['issued_epoch']<=now<scope['expires_epoch']<=parent['expires_epoch'],
          'same fresh selected node/route and separate complete28 fee')
    budget=linked(scope['parent_budget'])
    check(scope['parent_budget']==config['failure_tail_budgets'][scope['role']]
          and budget['schema']=='node_unallocated_failure_budget_v1'
          and budget['status']=='PROSPECTIVE_DISTINCT_NODE_UNALLOCATED_FAILURE_TAIL_BUDGET'
          and budget['parent_scope']==config['scope'] and budget['role']==scope['role']
          and budget['allocations']==ALLOCATIONS and all(exact_int(v,4) for v in budget['allocations'].values())
          and exact_int(budget['total_administrative_CPU'],28)
          and all(exact_int(budget[k],1) for k in ['maximum_query_calls','maximum_drain_calls','maximum_peer_calls'])
          and budget['expires_epoch']==parent['expires_epoch'],'prospective parent budget, no original-H3 fee credit')
    own=pin(__file__,code=True);approval=linked(scope['peer_source_approval'])
    check(scope['peer_source']==own and approval['status'].startswith('PASS_REVIEWED_')
          and (approval.get('independent_source_files',{}).get(Path(__file__).name)==own['sha256']
               or approval.get('source')==own),'actual separately authored reviewed peer hash')
    family=scope['family'];check(family in {'startup','scientific','numerical'},'closed role family')
    canonical=linked(config['canonical_authority'])
    statuses=dict(startup='ROOT_AUTHORIZED_CANONICAL_STARTUP_BATCH_CONFIG',
        scientific='ROOT_AUTHORIZED_CANONICAL_SCIENTIFIC_METADATA_CONFIG',numerical='ROOT_AUTHORIZED_CANONICAL_FROZEN525_NUMERICAL_CONFIG')
    check(canonical['status']==statuses[family]
          and canonical['binding']=={k:v for k,v in config.items() if k!='canonical_authority'}
          and parent['issued_epoch']<=canonical['issued_epoch']<=now<canonical['expires_epoch']<=parent['expires_epoch'],
          'actual complete canonical whole-configuration authority')
    source_name=dict(startup='startup_batch_stop.py',scientific='scientific_batch.py',numerical='numerical_batch.py')[family]
    publication=linked(config['publication']);review=linked(config['source_review'])
    closed_source_maps(publication,review,'foundation' if family=='startup' else family,config)
    check(publication['status'].startswith('PASS_') and 'PUBLICATION' in publication['status']
          and re.fullmatch('[0-9a-f]{40}',publication['commit'])
          and publication['source_files']==review['source_files']
          and review['source_commit']==publication['commit'] and review['status'].startswith('PASS_REVIEWED_')
          and len(publication['source_files'])==dict(startup=14,scientific=15,numerical=21)[family],
          'same independently reviewed published family source')
    for name,sha in publication['source_files'].items():
        check('/' not in name and name.endswith(('.py','.R')),'closed family source filename')
        raw(Path(config['source_dir'])/name,sha,code=True)
    check(publication.get('independent_source_files')==review.get('independent_source_files')
          ==approval.get('independent_source_files')
          and approval['independent_source_files'].get(Path(__file__).name)==own['sha256'],
          'same separately authored four-peer map across publication and actual source approval')
    family_source=dict(path=str(Path(config['source_dir'])/source_name),sha256=publication['source_files'][source_name])
    raw(family_source['path'],family_source['sha256'],code=True)
    check(scope['query_source']==scope['drain_source'],'one exact closed native producer for both phases')
    raw(scope['query_source']['path'],scope['query_source']['sha256'],code=True)
    check(publication.get('extra_administrative_source_files',{}).get('unallocated_tail.py')==scope['query_source']['sha256']
          and review.get('extra_administrative_source_files')==publication.get('extra_administrative_source_files'),
          'separately reviewed immutable H4-tail producer outside compute maps')
    job=linked(scope['job']);packet=linked(scope['packet']);role=scope['role']
    root=Path(config['registry'])/role
    check(scope['job']['path'] in {str(root/'JOB.json'),str(root/'RECONCILED_JOB.json')}
          and scope['packet']==pin(root/'PACKET.json')
          and job['job_id']==scope['job_id'] and type(job['job_id']) is str and re.fullmatch('[1-9][0-9]*',job['job_id'])
          and job['scope_id']==packet['scope_id']==scope['scope_id']
          and packet['role']==role and packet['execution_node']==node
          and packet['qualification_route_id']==route,'actual exact known role/job/packet, no ambiguous submission')
    failure_basis(scope,config,job,packet,family_source)
    value=local(result_path);g=local(guard_path);guard(g,4,120)
    fields={'schema','status','config','tail_scope','parent_scope','family','role','job','packet','job_id','scope_id',
        'execution_node','qualification_route_id','source','command_pid','command_birth_ticks','observed_epoch',
        'raw_accounting','raw_queue','observations'}
    exact_keys(value,fields|({'claim_identity'} if 'claim_identity' in value else set()),'closed query result fields')
    check(value['schema']=='node_unallocated_query_v1'
          and value['status']=='OBSERVED_EXACT_UNALLOCATED_JOB_AND_OWN_CLAIM'
          and value['config']==scope['config'] and value['tail_scope']==tpin and value['parent_scope']==scope['parent_scope']
          and all(value[k]==scope[k] for k in ['family','role','job','packet','job_id','scope_id','execution_node','qualification_route_id'])
          and value['source']==scope['query_source'] and type(value['command_pid']) is type(value['command_birth_ticks']) is int
          and value['command_pid']>0 and value['command_birth_ticks']>0
          and g['session_id']==value['command_pid'] and g['leader_start_ticks']==value['command_birth_ticks']
          and strict(g['stdout'])==value
          and scope['issued_epoch']<=finite(value['observed_epoch'],'finite raw observation time')<=now
          and 0<=now-value['observed_epoch']<=120,'actual H4 query stdout/source/PID/birth/current job identity')
    rootout=Path(scope['allowed_output_root']);target=Path(output_path)
    check(rootout.resolve(strict=True)==rootout and rootout.is_dir()
          and rootout.stat().st_uid==os.getuid() and rootout.stat().st_mode&0o077==0
          and target==rootout/'QUERY_REVIEW.json'
          and Path(result_path)==rootout/'QUERY_RESULT.json' and Path(guard_path)==rootout/'QUERY_GUARD.json',
          'one private actual scope output root and create-only review')
    intent=local(rootout/'QUERY_INTENT.json')
    identity={k:value[k] for k in ['config','tail_scope','parent_scope','family','role','job','packet','job_id',
        'scope_id','execution_node','qualification_route_id','source','command_pid','command_birth_ticks']}
    check(set(intent)==set(identity)|{'status','issued_epoch'}
          and all(intent[k]==v for k,v in identity.items())
          and intent['status']=='ONE_SHOT_QUERY_STARTED_NO_REPLAY'
          and scope['issued_epoch']<=finite(intent['issued_epoch'],'finite actual query intent time')<=value['observed_epoch'],
          'one durable create-only actual query intent before raw observations')
    rawrefs=[value['raw_accounting'],value['raw_queue']]
    observed=accounting(linked(value['raw_accounting']),job['job_id'],packet['scope_id'],os.getuid())
    queue=linked(value['raw_queue'])
    exact_keys(queue,{'argv','returncode','stdout','stderr'},'closed raw SQUEUE')
    check(queue['argv']==['squeue','-h','-j',job['job_id'],'-o','%i|%T|%j|%u|%N']
          and type(queue['returncode']) is int and queue['stdout']==''
          and ((queue['returncode']==0 and queue['stderr']=='') or
               (queue['returncode']==1 and queue['stderr']=='slurm_load_jobs error: Invalid job id specified\n')),
          'actual queue absent under exact terminal Alloc0 proof, never arbitrary error-as-absence')
    paths=expected_paths(config,packet,packet['scope_id']);paths['return']=paths.pop('return_')
    exact_keys(value['observations'],OBS_KEYS,'closed exact scoped observations')
    existence={}
    for key in sorted(OBS_KEYS):
        row=value['observations'][key];exact_keys(row,{'path','exists','observation'},'closed native path observation')
        check(row['path']==paths[key] and type(row['exists']) is bool,'same exact owned namespace paths')
        result=linked(row['observation']);rc=0 if row['exists'] else 1
        text=native_result(result,['test','-e',paths[key]],rc,'exact scoped native existence')
        check(text=='','test existence has no payload output')
        check(key in {'lock','marker'} or not row['exists'],'no READY/release/return payload ever existed')
        existence[key]=row['exists'];rawrefs.append(row['observation'])
    check(existence['lock']==existence['marker'],'both owned lock and marker exist or both absent')
    identity=None
    if existence['marker']:
        check('claim_identity' in value,'present marker requires prospective no-follow ownership/inode proof')
        ci=value['claim_identity'];exact_keys(ci,{'raw_stat','lock','marker'},'closed claim identity fields')
        identity=stat_identity(linked(ci['raw_stat']),paths['lock'],paths['marker'])
        check(ci['lock']==identity['lock'] and ci['marker']==identity['marker'],'typed identity equals actual raw stat')
        rawrefs.append(ci['raw_stat'])
    else:check('claim_identity' not in value,'absent claim makes no invented inode proof')
    check(len({x['path'] for x in rawrefs})==len(rawrefs),'one distinct raw receipt per native command')
    for ref in rawrefs:
        check_pin(ref);check(Path(ref['path']).parent==rootout,'raw evidence retained under exact scope output root')
    expected={Path(ref['path']).name for ref in rawrefs}|{'QUERY_INTENT.json','QUERY_RESULT.json','QUERY_GUARD.json'}
    check({p.name for p in rootout.glob('QUERY_*.json')}==expected,
          'complete exact query-artifact closure, no redundant/foreign paid native receipts')
    review_value=dict(status='PASS_REVIEWED_EXACT_UNALLOCATED_NODE_ROLE_DRAIN',query_result=pin(result_path),
        query_guard=pin(guard_path),config=scope['config'],tail_scope=tpin,parent_scope=scope['parent_scope'],
        job=scope['job'],packet=scope['packet'],job_id=scope['job_id'],scope_id=scope['scope_id'],
        family=family,role=role,execution_node=node,qualification_node=node,qualification_route_id=route,
        expected_lock=paths['lock'],expected_marker=paths['marker'],observed_presence=existence,
        claim_identity=identity,accounting=observed,review_source=own,source_approval=scope['peer_source_approval'],
        observed_epoch=now,expires_epoch=min(scope['expires_epoch'],value['observed_epoch']+120),
        permitted_operation='REMOVE_EXACT_OWNED_ZERO_BYTE_MARKER_THEN_NONRECURSIVE_EMPTY_LOCK' if identity else 'VERIFY_TWO_EXACT_ABSENCES_ONLY',
        no_blanket_delete=True,no_numerical_success_or_runtime_admission=True,old_failed_action_fee_retained=True,
        distinct_failure_tail28_fully_retained=True,read_set=list(READS.values()))
    write_new(output_path,review_value);return review_value


def main():
    check(os.sched_getaffinity(0)=={31},'administrative31 required')
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ['query-result','query-guard','tail-scope','output']:parser.add_argument('--'+key,required=True)
    a=parser.parse_args();resource.setrlimit(resource.RLIMIT_CPU,(4,4));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(45)
    out=Path(a.output);write_new(out.with_name('PEER_REVIEW_INTENT.json'),
        dict(status='EXACT_UNALLOCATED_REVIEW_STARTED_NO_REPLAY',source=pin(__file__,code=True),
             tail_scope=pin(a.tail_scope),issued_epoch=time.time()))
    value=review_query(a.query_result,a.query_guard,a.tail_scope,a.output)
    u=resource.getrusage(resource.RUSAGE_SELF)
    write_new(out.with_name('PEER_REVIEW_RECEIPT.json'),dict(status='COMPLETED_INDEPENDENT_EXACT_UNALLOCATED_REVIEW',
        output=pin(a.output),SELF_CPU_seconds=u.ru_utime+u.ru_stime,CPU_cap=4,wall_cap=45,
        all28_fees_retained=True,read_set=list(READS.values())))
    print(json.dumps(dict(status=value['status'],SELF_CPU=u.ru_utime+u.ru_stime)))


if __name__=='__main__':main()

