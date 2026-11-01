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
    check(family in {'foundation','scientific','numerical'},'supported metadata family')
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
    check(len(hashes)=={'foundation':14,'scientific':15,'numerical':21}[family],'exact family compute source count')
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


import errno
import struct

RETURN_CAPS={'foundation':8,'scientific':8,'numerical':6}
ACCOUNT_FORMAT='JobIDRaw,State,ExitCode,TotalCPU,ElapsedRaw,AllocCPUS,JobName%128,Account,Partition,ReqMem,MaxRSS,User,UID,ReqCPUS,Start,NodeList'
TERMINAL={'COMPLETED','FAILED','CANCELLED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','PREEMPTED','BOOT_FAIL'}


def cpu_seconds(text):
    match=re.fullmatch(r'(?:(\d+)-)?(?:(\d+):)?(\d\d):(\d\d(?:\.\d+)?)',text)
    check(match is not None,'complete exact Slurm CPU')
    days,hours,minutes,seconds=match.groups()
    result=int(days or 0)*86400+int(hours or 0)*3600+int(minutes)*60+float(seconds)
    check(math.isfinite(result) and result>=0 and int(minutes)<60 and float(seconds)<60,'finite nonnegative Slurm CPU')
    return result


def raw_account(account,job_id,scope_id,node):
    observed=linked(account['raw_observation'])
    check(observed['argv']==['sacct','--jobs',job_id,'--noheader','--parsable2','--format',ACCOUNT_FORMAT]
          and exact_int(observed['returncode'],0) and observed['stdout']==account['raw_sacct']
          and observed['stderr']=='','exact actual native full accounting evidence')
    rows=[x.split('|') for x in observed['stdout'].splitlines() if x.strip()]
    check(rows and all(len(x)==16 for x in rows)
          and len({x[0] for x in rows})==len(rows)
          and {job_id,job_id+'.batch'}<={x[0] for x in rows}<={job_id,job_id+'.batch',job_id+'.extern'},
          'complete exact allocated primary/batch accounting; Alloc0 uses separate H4 tail')
    primary=next(x for x in rows if x[0]==job_id)
    check(primary[5]=='1' and primary[6]==scope_id and primary[7:9]==['128x24','128x24']
          and primary[11]=='jaguir26' and primary[12]==str(os.getuid()) and primary[13]=='1'
          and primary[14] not in {'','None','Unknown','N/A'} and primary[15]==node,
          'fresh actual own allocated primary selected-node accounting')
    memory=re.fullmatch(r'([0-9.]+)([KMG])([cn])?',primary[9])
    check(memory is not None and float(memory[1])*{'K':1/1024,'M':1,'G':1024}[memory[2]]==8192,
          'actual requested memory8GiB')
    charge=cpu_seconds(primary[3]);elapsed=int(primary[4])
    check(0<=charge<=600 and 0<=elapsed<=1200
          and abs(charge-account['canonical_primary_CPU_seconds'])<1e-9
          and elapsed==account['elapsed_seconds']
          and all(x[1].split()[0] in TERMINAL and re.fullmatch('[0-9]+:[0-9]+',x[2])
              and 0<=int(x[4])<=1200 and x[5] in {'0','1'} and cpu_seconds(x[3])<=charge+.01 for x in rows)
          and account['job_id']==job_id and account['terminal'] is True
          and type(account['complete']) is bool and account['missing_required_rows']==[]
          and account['primary_charge_counted_once'] is True
          and account['step_rows_diagnostic_not_added'] is True
          and account['primary_CPU_consistent_with_each_step'] is True,
          'whole primary charge counted once with each step bounded, never step summation')
    complete=all(x[1].split()[0]=='COMPLETED' and x[2]=='0:0' for x in rows)
    check(account['complete'] is complete,'complete flag derives from actual terminal rows')
    return complete


def journal(root):
    values=[];previous=None
    for path in sorted(root.glob('record_[0-9][0-9][0-9][0-9].json')):
        item=local(path);check(item.get('previous')==previous,'complete canonical hash-chained role journal')
        previous=pin(path);values.append(item)
    check(values,'actual role journal exists');return values


def action_guard(config,role,action,path,source_sha,limits):
    # Accounting permits three paid observations: select the exact guard lifetime.
    g=local(path);guard(g,limits['local_CPU'],limits['wall']);matches=[]
    for p in Path(config['registry']).glob('control_*.started.json'):
        item=local(p)
        if item.get('role')==role and item.get('action')==action and item.get('command_pid')==g.get('session_id')\
                and item.get('command_birth_ticks')==g.get('leader_start_ticks'):matches.append((p,item))
    check(len(matches)==1,'one actual exact native action lifetime')
    p,start=matches[0];pending=local(p.with_name(p.name.replace('.started.','.pending.')))
    check(start['status']=='ACTION_STARTED_NOT_SUCCESS' and start['source_sha256']==source_sha
          and start['limits']==limits and pending['status']=='INTERNAL_ACTION_RESULT_NOT_GUARD_SUCCESS'
          and all(pending.get(k)==v for k,v in start.items() if k!='status')
          and strict(g['stdout'])==pending['result'],'actual exact-source native action/guard/stdout')
    return pending['result'],pin(path)



def numerical_output_inventory(role):
    check(role in {'TOY_PARITY','ZERO_UPDATE_BRIDGE'},'closed numerical output role')
    names={'RESULT.json','INVENTORY.json','PHYSICAL_SNAPSHOT.json','EXECUTION_CONTEXT.json',
        'numerical/INTENT.json','numerical/owned_guard.json','numerical/owned_tree.json',
        'numerical/child.stdout','numerical/child.stderr','numerical/RESULT.json',
        'numerical/PHYSICAL_BEFORE_R.json','numerical/PARSE_PARENT_GATE.json',
        'physical/ALLOCATION_WITNESS.json','physical/PEER_OWNERSHIP_WITNESS.json',
        'physical/PRIORITY_DRAIN_WITNESS.json','physical/NATIVE_OBSERVATIONS.json'}
    binaries=set()
    if role=='TOY_PARITY':
        names.add('numerical/toy/validation_core.json')
        for label,count in [('default_pair',4),('beta_sigma_pair',4),('checkpoint_import',1),('stress_default_pair',4)]:
            for i in range(1,count+1):
                stem='numerical/toy/'+label+'/checkpoints/sweep_%04d/'%i
                binaries.add(stem+'full_state.rds');names.add(stem+'completed_evidence.json')
            for name in ['X.bin','y.bin']:binaries.add('numerical/toy/synthetic_data/'+label+'/'+name)
    else:
        names|={'numerical/bridge/bridge_validation.json','numerical/bridge/baseline_certificate.json'}
        binaries.add('numerical/bridge/full_state.rds')
    return names|binaries,binaries


def validate_numerical_core(role,core,grant,grant_pin,metadata,rows,config,contract):
    check(core['source']==grant['source'],'exact imported mathematical source identity')
    if role=='TOY_PARITY':
        check(core['schema']=='r154_project_adapter_validation_core_v1'
              and core['status']=='NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF'
              and core['root_grant_pin']==grant_pin and core['actual_R_runtime_binding']==grant['actual_R_runtime_binding']
              and all(core[k] is True for k in ['toy_default_and_import_parity_pass','checkpoint_all_factors_schedules_RNG_IO_verified',
                  'stock_AST_exactly_preserved','no_production_data_used','production_gate_unchanged_and_rejects_synthetic'])
              and exact_int(core['toy_optimizer_invocations'],8) and exact_int(core['total_toy_optimizer_iterations'],30)
              and exact_int(core['maximum_n'],128) and exact_int(core['maximum_p'],32)
              and exact_int(core['production_fit_invocations'],0) and exact_int(core['production_passflags_written'],0)
              and core['optimizer_resume_claimed'] is False and core['continuation_will_certify_claimed'] is False
              and core['stock_body_sha256']==contract.STOCK_BODY_SHA,'exact synthetic full-factor/RNG/schedule parity proof')
        counts=[('default_pair',4),('beta_sigma_pair',4),('checkpoint_import',1),('stress_default_pair',4)]
        check([x['count'] for x in core['checkpoints']]==[4,4,1,4],'exact thirteen checkpoint group counts')
        paths=set()
        for group,(label,count) in zip(core['checkpoints'],counts):
            check(group['label']=='synthetic_NONCANDIDATE_'+label
                  and [x['completed_sweep'] for x in group['entries']]==list(range(1,count+1)),
                  'exact contiguous synthetic checkpoint history')
            for entry in group['entries']:
                ref=entry['state_pin'];path=metadata(ref,path_only=True)
                check(str(path) not in paths and path.name=='full_state.rds'
                      and entry['contains_all_factors_and_schedules'] is True,'all factors/schedules retained in unique checkpoint')
                paths.add(str(path));rel=ref['path'].rsplit('/',1)[0]+'/completed_evidence.json'
                relative=str(path.parent/'completed_evidence.json')
                # Resolve the corresponding declared metadata proof, never the opaque state value.
                suffix='/numerical/toy/';tail='numerical/toy/'+rel.split(suffix,1)[1]
                check(tail in rows,'checkpoint completed evidence is in full return')
                evidence=metadata(dict(path=rel,sha256=rows[tail]['sha256']))
                check(evidence['completed_sweep']==entry['completed_sweep'] and evidence['state_pin']==ref,
                      'completed evidence matches exact opaque state inventory')
        check(len(paths)==13,'all thirteen opaque checkpoints returned')
        cases=core['cases'];check(set(cases)=={x for x,_ in counts}
              and all(x['pass'] is True and exact_int(x['optimizer_invocations'],2) for x in cases.values())
              and sum(x['requested_sweeps'] for x in cases.values())==30,'all four actual synthetic parity cases')
        for label,n,p in [('default_pair',32,4),('beta_sigma_pair',64,8),('stress_default_pair',128,32)]:
            check(cases[label]['n']==n and cases[label]['p']==p and cases[label]['exact_science_equal'] is True
                  and rows['numerical/toy/synthetic_data/'+label+'/X.bin']['bytes']==n*p*8
                  and rows['numerical/toy/synthetic_data/'+label+'/y.bin']['bytes']==n*8,'exact bounded synthetic dimensions')
        check(cases['checkpoint_import']['all_factors_plus_one_equal_stock_fifth'] is True
              and cases['checkpoint_import']['new_outer_history_not_exact_resume'] is True
              and rows['numerical/toy/synthetic_data/checkpoint_import/X.bin']['bytes']==32*4*8
              and rows['numerical/toy/synthetic_data/checkpoint_import/y.bin']['bytes']==32*8,
              'synthetic imported factors start new outer history, no exact optimizer resume')
        return
    check(core['schema']=='r154_conditional_state_bridge_v1'
          and core['status']=='VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE'
          and core['target_name']==contract.TARGET and exact_int(core['optimizer_updates'],0)
          and core['production_acceptance_authority'] is False and core['exact_optimizer_resume'] is False
          and all(core[k] is True for k in ['full_state_factors_verified','explicit_factor_elbo_verified',
              'original_seven_certificate_computed','rhs_unit_and_dispersed_verified','source_recipe_reproduced'])
          and core['original_failed_state_modified'] is False and core['units']=='original_design_and_response',
          'source-bound zero-update full-state bridge, original seven gates and both starts')
    metadata(core['factor_state'],path_only=True);baseline=metadata(core['baseline_certificate_pin'])
    delivery={row['relative']:row for row in config['target_delivery']}
    check(len(delivery)==15,'all original fifteen opaque source aliases retained')
    old=linked(delivery['fit/fixedpoint_certificate.json']['source'])
    target=linked(delivery['contract/target.json']['source']);manifest=linked(config['original_manifest'])
    matches=[x for x in manifest['targets'] if x['name']==contract.TARGET]
    check(len(matches)==1,'original exact target contract')
    original=matches[0];logical={row['logical_path']:row['source']['sha256'] for row in delivery.values()}
    check(len(logical)==15 and all(logical.get(row['path'])==row['sha256'] for row in original['bindings'])
          and {k:original[k] for k in ['n','p','tau','tau0']}==dict(n=48576,p=417,tau=.75,tau0=.0022915214919211734)
          and core['prior']==manifest['scope']['prior'] and core['posterior_target_sha256']==original['posterior_target_sha256']==target['posterior_target_sha256']
          and target['certificate_limits']==LIMITS and target['tau']==.75 and target['tau0']==.0022915214919211734,
          'unchanged posterior/prior/normalization/scaler/source contract')
    check(set(baseline['measures'])==set(LIMITS) and baseline['measures']==old['measures']
          and baseline['limits']==old['limits']==LIMITS and baseline['checks']==old['checks']
          and baseline['certified']==old['certified'] and baseline['rhs_reconstruction']==old['rhs_reconstruction']
          and baseline['rhs_reconstruction']['unit_converged'] is True
          and baseline['rhs_reconstruction']['dispersed_converged'] is True
          and all(baseline[k]==old[k] for k in ['raw_reconstructed_elbo','raw_next_elbo']),
          'original seven measures/limits/checks/failed status and both RHS starts reproduced')
    check(set(core['data_references'])=={'X','y'}
          and core['data_references']['X']['sha256']==delivery['design/X.bin']['source']['sha256']
          and core['data_references']['y']['sha256']==delivery['design/y.bin']['source']['sha256'],
          'original data aliases preserved without opening scientific arrays')
    objective=core['explicit_factor_objective']
    check(objective['state_semantics']=='explicit_imported_factors_not_reconditioned_r129_state'
          and set(objective['terms'])=={'prior','sigma_prior','latent_prior','likelihood','Hbeta','Hsigma','Hlatent'}
          and all(type(x) in (int,float) and math.isfinite(x) for x in objective['terms'].values())
          and all(type(x) in (int,float) and math.isfinite(x) for x in [objective['objective'],
              core['original_conditional_objective'],core['objective_difference'],core['verification_bound_not_a_production_gate']])
          and 0<=core['verification_bound_not_a_production_gate']
          and abs(core['objective_difference'])<=core['verification_bound_not_a_production_gate']
          and core['original_conditional_objective']==baseline['raw_reconstructed_elbo'],
          'finite explicit-factor objective verification is separate from production certification')


def full_return(root,manifest,packet,job_id,family):
    check(manifest['job_id']==job_id and manifest['scope_id']==packet['scope_id']
          and manifest['schema']==('r182_frozen525_numerical_return_manifest_v1' if family=='numerical'
              else 'pricefm_startup_batch_return_manifest_v1'),'current full manifest identity and closed family schema')
    if family=='numerical':
        check(exact_int(manifest['production_fits'],0) and exact_int(manifest['pilot_fits'],0)
              and type(manifest['complete_success']) is bool,'zero-production numerical manifest')
    else:check(exact_int(manifest['new_models'],0),'zero-model metadata manifest')
    rows={};total=0
    for row in manifest['files']:
        rel=PurePosixPath(row['relative'])
        check(not rel.is_absolute() and '..' not in rel.parts and str(rel)==row['relative']
              and str(rel) not in rows and type(row['bytes']) is int and 0<=row['bytes']<=16*1024**2
              and re.fullmatch('[0-9a-f]{64}',row['sha256']),'closed unique bounded return members')
        path=root/'returned'/str(rel);info=path.lstat()
        check(stat.S_ISREG(info.st_mode) and not path.is_symlink() and info.st_nlink==1
              and info.st_uid==os.getuid() and info.st_size==row['bytes'],'actual owned single-link return metadata')
        if path.suffix.lower() in {'.rds','.rda','.rdata','.bin','.npz','.npy'}:
            check(family=='numerical' and str(rel) in numerical_output_inventory(packet['role'])[1],
                  'only explicit opaque full-state transport is permitted; no value read')
        else:raw(path,row['sha256'],code=True)
        rows[str(rel)]=row;total+=row['bytes']
    check(1<=len(rows)<=(256 if family=='numerical' else 4096)
          and total<=(64 if family=='numerical' else 32)*1024**2
          and {'RESULT.json','INVENTORY.json'}<=set(rows),'closed bounded useful full metadata return')
    actual={str(p.relative_to(root/'returned')) for p in (root/'returned').rglob('*') if p.is_file()}
    check(actual==set(rows)|{'RETURN_MANIFEST.json'},'no foreign/unmanifested returned artifact')
    return rows,total


def kernel_proof(result,metadata):
    case=result['outcome']
    check(case==metadata(dict(path=result['_remote']+'/kernel/KERNEL_MATRIX_RESULT.json',
                             sha256=result['_rows']['kernel/KERNEL_MATRIX_RESULT.json']['sha256'])),
          'canonical actual kernel case result')
    labels=['wait_and_escape','orphan','aggregate_CPU','wall','monitor_death','guardian_death']
    check(case['status']=='PASS_COMPUTE_OWNED_HELPER_KERNEL_MATRIX_NOT_R'
          and case['job_id']==result['job_id'] and case['node']==result['node'] and case['error'] is None
          and case['all_private_descendants_reaped'] is True and case['aggregate_CPU_seconds']<30
          and abs(case['SELF_CPU_seconds']+case['waited_CPU_seconds']-case['aggregate_CPU_seconds'])<1e-9
          and all(case[k] is False for k in ['R_startup_proved','numerical_parity_proved','production_ready'])
          and [x['label'] for x in case['case_results']]==labels,'all six complete actual source-bound kernel cases')
    for row in case['case_results']:
        check(row['test_expectation_met'] is True and row['all_private_descendants_reaped'] is True
              and row['deliberate_guard_failures_remain_failed'] is True
              and row['invoked_supervision_profile']=='r176_conservative_stop_lead_v1','actual six-case expectation/drain')
        # Validate stderr transport without interpreting it as runtime success.
        metadata(row['stderr'],parse=False)
        g=metadata(row['guard']) if row['actual_guard_returncode'] is not None else None
        expectation=row['expected']
        if expectation in {'SUCCESS','CPU_BOUNDARY','WALL_BOUNDARY'}:
            check(row['candidate_receipt_required'] is True and row['candidate_receipt_present'] is True
                  and g['supervision_profile']=='r176_conservative_stop_lead_v1'
                  and g['original_supervisor_sha256']==H_SHA
                  and g['conservative_stop_policy']==dict(schema='r176_conservative_stop_lead_v1',
                      CPU_stop_lead_seconds=.25,wall_stop_lead_seconds=.25,original_hard_ceilings_and_stop_checks_unchanged=True)
                  and g['CPU_decision_ceiling']==g['CPU_active_ceiling']-.25
                  and exact_int(g['CPU_limit'],4) and 0<=g['aggregate_CPU_seconds']<4
                  and all(g[k] is True for k in ['all_owned_descendants_reaped','kernel_escape_filter',
                      'orphan_subreaper','independent_guardian','guardian_included_in_CPU']),'unchanged original hard kernel4 ceilings')
        if expectation=='SUCCESS':
            check(row['actual_process_returncode']==g['returncode']==g['command_returncode']==0
                  and g['cap_reason'] is None and g['stderr']=='','successful synthetic helper guard')
            f=strict(g['stdout'])
            check(f['status']=='PASS_SYNTHETIC_OWNED_HELPER_FIXTURE' and exact_int(f['models'],0)
                  and exact_int(f['optimizer_invocations'],0) and f['scientific_data_read'] is False,'data-free synthetic helper')
            if row['label']=='wait_and_escape':
                check(f['helper_wait_status']==0 and f['escape_operations_denied']==3
                      and f['deliberate_nonzero_helper_status_observed']==7,'escape denials and nonzero wait preserved')
            else:check(len(g['reaped'])>=2 and f['intentionally_unwaited_private_helper'] is True,'orphan independently reaped')
        elif expectation in {'CPU_BOUNDARY','WALL_BOUNDARY'}:
            check(row['actual_process_returncode']==g['returncode']==124 and len(g['reaped'])>=2
                  and g['cap_reason']==('AGGREGATE_CPU_BOUNDARY' if expectation=='CPU_BOUNDARY' else 'WALL_BOUNDARY'),
                  'deliberate hard-boundary failures remain failed')
            if expectation=='CPU_BOUNDARY':
                f=strict(g['stdout']);check(f['inherited_CPU_limits']==[4,4]
                    and any(x['pid']==f['helper_pid'] and x['CPU_seconds']>.1 for x in g['reaped']),'inclusive child CPU proof')
        elif expectation=='MONITOR_DEATH':
            check(row['candidate_receipt_required'] is False and row['actual_process_returncode']==g['returncode']==125
                  and g['all_owned_descendants_reaped'] is True
                  and row['injection']['signal_method']=='PIDFD_UID_BIRTH_PRIVATE_PARENT','expected monitor-death drain')
        else:
            check(expectation=='GUARDIAN_DEATH' and row['candidate_receipt_required'] is False
                  and row['actual_process_returncode']==-9 and g is None and len(row['reaped'])>=2
                  and row['injection']['signal_method']=='PIDFD_UID_BIRTH_PRIVATE_PARENT','expected guardian-death outer drain')
    return dict(all_six_source_bound_actual_cases_verified=True,case_labels=labels)


def R_startup_proof(result,ready,release,metadata,staged):
    outcome=result['outcome'];plan=staged(outcome['plan']);authority=staged(outcome['authority'])
    review=staged(outcome['source_review'])
    check(outcome['status']=='PASS_R_METADATA_STARTUP_UNDER_OWNED_HELPER_GUARD'
          and outcome['R_startup_proved'] is True and all(outcome[k] is False for k in
              ['numerical_parity_proved','real_target_bridge_proved','production_ready','old_scope_fee_refund']),
          'actual R metadata proof has no numerical/target/promotion claim')
    check(outcome==metadata(dict(path=result['_remote']+'/R_STARTUP_PROOF.json',
              sha256=result['_rows']['R_STARTUP_PROOF.json']['sha256']))
          and outcome['source_closure']==plan['sources']==review['sources']
          and authority['status']=='ROOT_AUTHORIZED_SOURCE_BOUND_STARTUP_HELPER_PROOF'
          and authority['sources']==plan['sources'] and authority['plan']==outcome['plan']
          and authority['placement']==plan['placement']==dict(kind='SLURM_SINGLE_CPU_METADATA',
              job_id=result['job_id'],node=result['node'])
          and authority['limits']==plan['limits']==dict(CPU=30,wall=120,output_cap=1048576)
          and exact_int(authority['executions'],1) and authority['no_real_target_data_or_optimizer'] is True,
          'actual R plan/review/root authority closure')
    intent=metadata(outcome['execution_intent']);g=metadata(outcome['original_guard']);guard(g,30,120)
    check(intent['plan']==outcome['plan'] and intent['authority']==outcome['authority']
          and intent['source_review']==outcome['source_review'] and intent['sources']==plan['sources']
          and g['stderr']=='' and g['guardian_nondumpable'] is True
          and intent['created_epoch']+g['complete_lifecycle_wall_seconds']<authority['expires_epoch']
          and g['bootstrap_anchor']['guardian_pid']==intent['process_pid']
          and g['bootstrap_anchor']['guardian_birth_ticks']==intent['process_birth_ticks']
          and g['reaped'] and all(type(x['returncode']) is int and x['returncode']==0 for x in g['reaped'])
          and g['supervision_profile']=='r176_conservative_stop_lead_v1'
          and g['original_supervisor_sha256']==H_SHA
          and g['conservative_stop_policy']==dict(schema='r176_conservative_stop_lead_v1',
              CPU_stop_lead_seconds=.25,wall_stop_lead_seconds=.25,original_hard_ceilings_and_stop_checks_unchanged=True)
          and g['CPU_decision_ceiling']==g['CPU_active_ceiling']-.25,'actual R owned whole lifecycle and unchanged hard limits')
    f=strict(g['stdout'])
    check(f==outcome['fixture'] and f['status']=='PASS_R_STARTUP_METADATA_FIXTURE'
          and f['role']=='R_STARTUP_METADATA_ONLY' and f['nonce']==plan['nonce'] and f['R_version']=='4.6.0'
          and f['R_home']==plan['runtime']['R_home'] and f['default_utils_loaded'] is True
          and f['uname_path']==plan['runtime']['uname']['path'] and f['uname_result']=='Linux'
          and f['hostname'].split('.')[0]==f['SLURMD_NODENAME']==result['node']
          and f['SLURM_JOB_ID']==result['job_id'] and exact_int(f['models'],0)
          and exact_int(f['optimizer_invocations'],0) and f['scientific_data_read'] is False
          and outcome['whole_lifecycle_CPU_seconds']==g['aggregate_CPU_seconds']
          and outcome['whole_lifecycle_wall_seconds']==g['complete_lifecycle_wall_seconds'],
          'exact source/native R4.6 current selected-node metadata fixture')
    return dict(R_startup_proved=True,numerical_parity_proved=False,real_target_bridge_proved=False,production_ready=False)


def kernel_tsync(g):
    deny=0x00050000|errno.EPERM;enosys=0x00050000|errno.ENOSYS
    rows=[(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),(0x20,0,0,0),
        (0x45,0,1,0x40000000),(0x06,0,0,deny),(0x15,0,1,57),(0x06,0,0,deny),
        (0x15,0,1,58),(0x06,0,0,deny),(0x15,0,1,435),(0x06,0,0,enosys),
        (0x15,0,3,56),(0x20,0,0,16),(0x45,1,0,0x10000),(0x06,0,0,deny),(0x06,0,0,0x7fff0000)]
    digest=hashlib.sha256(b''.join(struct.pack('<HBBI',*x) for x in rows)).hexdigest()
    att=g['scientific_filter_kernel_attestation']
    check(att['operation']=='SECCOMP_SET_MODE_FILTER' and att['flags']=='TSYNC' and exact_int(att['kernel_return'],0)
          and exact_int(att['instruction_count'],17) and att['program_sha256']==digest
          and g['postbootstrap_TSYNC_scientific_fork_denial'] is True
          and g['scientific_target_access_handshake'] is True,'independently reconstructed exact17-instruction kernel TSYNC and ACK')
    return digest


def owner_lifetime(g,tree,ready,scope_id,authority):
    identity=ready['worker_identity']
    check(identity['uid']==ready['inventory']['scheduler']['uid']==os.getuid()
          and type(identity['pid']) is type(identity['start_ticks']) is int
          and identity['pid']>0 and identity['start_ticks']>0 and len(identity['affinity'])==1,
          'current owned READY worker lifetime')
    check(g['schema']=='r157_traced_bootstrap_guard_receipt_v1' and g['status']=='EXITED'
          and all(g[k] is True for k in ['reaped','drained','CPU_accounting_complete',
              'all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled'])
          and g['remaining_owned_lifetimes']==g['unexpected_untraced_child_waits']==[]
          and exact_int(g['maximum_combined_CPU_seconds'],450)
          and 0<=g['parent_plus_all_reaped_child_CPU_seconds']<450 and 0<=g['wall_seconds']<300
          and tree['state']=='CLOSED' and tree['scope']==scope_id and tree['authority_pin']==authority,
          'actual original native owner whole lifetime closed/reaped/drained')
    for actual in [g['supervisor'],tree['supervisor']]:
        check(all(actual[k]==identity[k] for k in ['pid','start_ticks','boot_id','affinity']),
              'all tracees belong to exact current READY lifetime')


def numerical_physical(result,ready,ospec,release,metadata,staged,gate):
    snapshot=metadata(dict(path=result['_remote']+'/PHYSICAL_SNAPSHOT.json',
        sha256=result['_rows']['PHYSICAL_SNAPSHOT.json']['sha256']))
    current=metadata(dict(path=result['_remote']+'/numerical/PHYSICAL_BEFORE_R.json',
        sha256=result['_rows']['numerical/PHYSICAL_BEFORE_R.json']['sha256']))
    proof=staged(release['physical_core_proof']);peer=staged(release['physical_core_review'])
    check(snapshot==ready['physical_snapshot_value']
          and proof['actual_snapshot']==peer['actual_snapshot']==ospec['physical_snapshot']==ready['physical_snapshot']
          and all(snapshot[k]==current[k] for k in ['topology','Slurm_core_policy','job_cpuset','online_thread_siblings']),
          'exact source-bound current physical before-R/core/peer identity')
    policy=snapshot['Slurm_core_policy'];parameters={x.upper() for x in policy['SelectTypeParameters'].split(',')}
    check(policy['SelectType']=='select/cons_tres' and policy['ProctrackType']=='proctrack/cgroup'
          and 'task/cgroup' in policy['TaskPlugin'].split(',') and policy['PartitionOverSubscribe'] in {'NO','EXCLUSIVE'}
          and (bool(parameters&{'CR_CORE','CR_CORE_MEMORY'}) or bool(parameters&{'CR_CPU','CR_CPU_MEMORY'})
              and snapshot['topology']['thread_siblings']==ready['affinity'])
          and snapshot['job_cpuset']['effective_cpus']==snapshot['online_thread_siblings']
          and snapshot['online_thread_siblings'] and ready['affinity'][0] in snapshot['online_thread_siblings']
          and 'job_'+result['job_id'] in PurePosixPath(snapshot['job_cpuset']['job_cgroup_path']).parts
          and proof['all_SMT_siblings_reserved_to_this_job'] is True and proof['priority_drain_complete'] is True
          and proof['unreviewed_numerical_peer_intersections']==[]
          and proof['old_processes_signalled_or_peer_allowlist_broadened'] is False
          and peer['all_peer_and_drain_witnesses_bound'] is True,'whole selected physical core and exact known-job drain')
    for name in ['allocation_witness','peer_ownership_witness','priority_drain_witness']:
        check(proof[name]==peer[name]==snapshot['witness_pins'][name]
              and metadata(proof[name])==snapshot['witnesses'][name]
              and snapshot['witnesses'][name]['node']==result['node']
              and snapshot['witnesses'][name]['job_id']==result['job_id']
              and snapshot['witnesses'][name]['uid']==ready['worker_identity']['uid'],'actual same-node physical witnesses')
    for fs in [snapshot['filesystem'],current['filesystem'],gate['filesystem_before_ACK']]:
        check(fs['path']==ospec['remote_namespace'] and fs['quota_status']=='UNKNOWN'
              and fs['minimum_available_bytes']==80*1024**3 and fs['available_bytes']>=80*1024**3
              and fs['available_bytes']==fs['fragment_bytes']*fs['available_blocks']
              and fs['fragment_bytes']>0 and fs['free_bytes']>=fs['available_bytes'],'actual root80GiB floor, quota explicitly unknown')


def scientific_proof(result,ready,release,spec,metadata,staged,source):
    owner,contract,allocation=import_core(source,['scientific_metadata_owner','scientific_namespace_contract','scientific_allocation'])
    role=result['role'];outcome=result['outcome'];ospec=staged(release['owner_spec']);ns=staged(release['namespace_spec'])
    expected='PASS_HB_SCIENTIFIC_NAMESPACE_METADATA_ONLY' if role=='SCIENTIFIC_NAMESPACE_NO_OPTIMIZER' else 'PASS_HB_NATIVE_SCIENTIFIC_BOUNDARY_NO_TARGET_NO_OPTIMIZER'
    check(outcome['status']==expected and outcome['job_id']==result['job_id'] and outcome['node']==result['node']
          and outcome['spec']==release['owner_spec'] and outcome['authority']==release['owner_authority']
          and outcome['review']==release['owner_review'],'actual exact owned scientific role outcome')
    contract.validate(ns,spec['remote_root']);owner.validate_frames(outcome['namespace_frames'],ospec,ns)
    g=metadata(outcome['owned_guard']);tree=metadata(outcome['owned_tree'])
    owner_lifetime(g,tree,ready,result['scope_id'],release['owner_authority'])
    owner.validate_current_owner(g,tree,ospec,release['owner_authority'],ready['worker_identity'])
    tsync=role=='SCIENTIFIC_TSYNC_NO_TARGET_NO_OPTIMIZER'
    digest=kernel_tsync(g) if tsync else None
    check(outcome['scheduler']['uid']==ready['worker_identity']['uid']==os.getuid(),'actual scientific scheduler UID')
    for cgroup in outcome['scheduler']['cgroups']:allocation.exact_cgroup('0::'+cgroup+'\n',result['job_id'],os.getuid())
    check(result['whole_self_plus_waited_CPU']<600 and result['wall_seconds']<1200
          and result['whole_self_plus_waited_CPU']==result['worker_SELF_CPU_seconds']+result['worker_waited_CPU_seconds']
          and outcome['whole_parent_plus_reaped_CPU']<=result['whole_self_plus_waited_CPU']
          and exact_int(outcome['optimizer_invocations'],0) and outcome['scientific_data_read'] is False,
          'inclusive parent/all reaped scientific phase accounting and zero target')
    return dict(namespace_versions_and_stock_body_proved=True,actual_loaded_DLL_ABI_only=True,
        scientific_TSYNC_proved=tsync,exact_kernel_TSYNC_program_sha256=digest,numerical_parity_proved=False,production_admission=False)


def numerical_proof(result,ready,release,spec,config,metadata,staged,source):
    owner,contract=import_core(source,['numerical_stage_owner','numerical_stage_contract'])
    check({k:v['sha256'] for k,v in config['scientific_sources'].items()}==contract.SCIENCE_HASHES,
          'exact unchanged five mathematical and authority-only scientific sources')
    outcome=result['outcome'];role=result['role'];ospec=staged(release['owner_spec']);grant=staged(release['stage_grant'])
    check(outcome['status']==('PASS_HB_FROZEN525_SYNTHETIC_TOY' if role=='TOY_PARITY' else 'PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE')
          and all(outcome[k]==result[k] for k in ['job_id','node','role'])
          and outcome['current_TSYNC_and_parent_ACK'] is True and exact_int(outcome['pilot_fits'],0)
          and exact_int(outcome['production_fits'],0) and outcome['production_admission'] is False
          and outcome['spec']==release['owner_spec'] and outcome['authority']==release['owner_authority']
          and outcome['review']==release['owner_review'],'exact current numerical owner outcome')
    g=metadata(outcome['owned_guard']);tree=metadata(outcome['owned_tree'])
    owner_lifetime(g,tree,ready,result['scope_id'],release['owner_authority']);check(exact_int(g['returncode'],0),'successful current numerical owner exit')
    digest=kernel_tsync(g);gate=metadata(outcome['owner_validated_parse_before_kernel_ACK']);frame=gate['frame']
    check(gate['status']=='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK' and gate['authority']==release['owner_authority']
          and gate['original_tracer_pre_ACK_capture_callback'] is True
          and gate['kernel_ACK_still_requires_original_guard_completion'] is True
          and all(gate[k]==ospec[k] for k in ['role','job_id','node','scope_id'])
          and frame==outcome['source_parse_pass_before_numerical_entrypoint']
          and frame['status']=='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT'
          and all(frame[k]==ospec[k] for k in ['role','job_id','node','nonce'])
          and frame['source_files']==[ospec['scientific_sources'][k] for k in sorted(ospec['scientific_sources'])]
          and exact_int(frame['optimizer_invocations'],0) and frame['scientific_target_data_read'] is False,
          'independent raw current parent pre-ACK parse frame/source identity')
    stdout=metadata(dict(path=result['_remote']+'/numerical/child.stdout',
        sha256=result['_rows']['numerical/child.stdout']['sha256']),parse=False)
    frames=[strict(line) for line in stdout.splitlines() if line.lstrip().startswith(b'{')]
    check(frames==[frame],'successful numerical stdout has exactly one pre-ACK source frame')
    for k,v in config['scientific_sources'].items():raw(v['path'],v['sha256'],code=True)
    check({k:v['sha256'] for k,v in ospec['scientific_sources'].items()}=={k:v['sha256'] for k,v in config['scientific_sources'].items()},
          'unchanged five scientific source hashes')
    core=metadata(outcome['core'])
    validate_numerical_core(role,core,grant,release['stage_grant'],metadata,result['_rows'],config,contract)
    numerical_physical(result,ready,ospec,release,metadata,staged,gate)
    check(core.get('production_acceptance_authority') is not True and core.get('exact_optimizer_resume') is not True,
          'zero-update factor bridge is not an exact optimizer resume or production acceptance')
    return dict(current_kernel_TSYNC_and_parent_ACK=True,exact_kernel_program_sha256=digest,
        current_parent_parse_before_ACK_verified=True,current_owned_lifetime_closed_reaped_drained=True,
        current_physical_runtime_and_filesystem_proofs=True,opaque_binary_values_not_opened=True,
        exact_compute_core_proved_by_source_bound_metadata=True,production_admission=False)


def review_complete(family,config_path,role,scope_path,bundle,observe_guard,collect_guard):
    check(family in RETURN_CAPS,'closed return family')
    c,s,source,hashes=checked_core(config_path,family);node,route=route_fields(c,s)
    check(role==c.get('role',role),'one current funded role')
    own=local(scope_path);out=Path(bundle);cap=RETURN_CAPS[family]
    check(own['parent']==c['scope'] and exact_int(own['allocations']['complete_actual_return_or_truthful_failure'],cap)
          and own['allowed_return_review_output_root']==str(out)
          and s['issued_epoch']<=own['issued_epoch']<=time.time()<own['expires_epoch']<=s['expires_epoch']
          and out.is_dir() and out.resolve(strict=True)==out and out.stat().st_uid==os.getuid()
          and out.stat().st_mode&0o077==0,'actual separate current finite private complete-return allocation')
    root=Path(c['registry'])/role;packet=local(root/'PACKET.json');job=local(root/'JOB.json')
    spec=local(root/'packet/SPEC.json');route_fields(c,s,spec);past=journal(root)
    check(packet['role']==role and packet['execution_node']==node and packet['qualification_route_id']==route
          and packet['spec_sha256']==pin(root/'packet/SPEC.json')['sha256']
          and packet['scope_id']==job['scope_id']==spec['scope_id']
          and spec['sources']==packet['sources'] and {n:v['sha256'] for n,v in packet['sources'].items()}==hashes,
          'current frozen exact-node/route/source role packet')
    account_pin=next(x['accounting'] for x in reversed(past) if x['state']=='OBSERVED')
    return_record=next(x for x in reversed(past) if x['state']=='RETURNED');manifest_pin=return_record['manifest']
    account=linked(account_pin);complete=raw_account(account,job['job_id'],packet['scope_id'],node)
    source_name={'foundation':'startup_batch_stop.py','scientific':'scientific_batch.py','numerical':'numerical_batch.py'}[family]
    observed,og=action_guard(c,role,'observe',observe_guard,hashes[source_name],
        dict(local_CPU=3,remote_unknown_fee=3,wall=45,maximum_calls=3))
    collected,cg=action_guard(c,role,'collect',collect_guard,hashes[source_name],
        dict(local_CPU=6,remote_unknown_fee=6,wall=300,maximum_calls=1))
    check(observed==account and return_record['full_return_hash_verified'] is True
          and collected['status']=='COMPLETE_HASH_VERIFIED_RETURN_NOT_YET_ACCEPTED'
          and collected['manifest']==manifest_pin and manifest_pin==pin(root/'returned/RETURN_MANIFEST.json'),
          'actual complete native collect guardian transported and hash-verified full manifest')
    manifest=linked(manifest_pin);rows,total=full_return(root,manifest,packet,job['job_id'],family)
    result_pin=pin(root/'returned/RESULT.json');result=linked(result_pin);ready=local(root/'READY.json')
    if family=='numerical':
        allowed,binaries=numerical_output_inventory(role)
        check(set(rows)<=allowed|{'numerical/FAILED.json'},'closed numerical return namespace')
        if result['status']=='PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER':
            check(set(rows)==allowed,'all useful numerical proofs and opaque states returned')
    check(all(result[k]==packet[k] for k in ['role','scope_id','sources','spec_sha256'])
          and result['job_id']==job['job_id'] and result['node']==node and result.get('qualification_route_id')==route
          and ready['node']==node and ready['qualification_route_id']==route
          and result['ready']['sha256']==pin(root/'READY.json')['sha256']
          and ready['job_id']==job['job_id'] and ready['scope_id']==packet['scope_id'],
          'actual result/READY/source/current job selected-node/route identity')
    inventory=local(root/'returned/INVENTORY.json')
    check(inventory==ready['inventory'] and inventory['qualification_route_id']==route and inventory['node']==node,
          'actual returned inventory is current READY, not cached node13 origin')
    # All metadata reads below are manifest-bound. Opaque state is only statted.
    def metadata(ref,parse=True,path_only=False):
        check_pin(ref);prefix=packet['remote_root']+'/result/'
        check(ref['path'].startswith(prefix),'exact current result namespace')
        rel=ref['path'][len(prefix):];check(rel in rows and rows[rel]['sha256']==ref['sha256'],'proof belongs to complete return')
        path=root/'returned'/rel
        if path.suffix.lower() in {'.rds','.rda','.rdata','.bin','.npz','.npy'}:
            check(path_only,'opaque state value must remain unopened');return path
        value=raw(path,ref['sha256'],code=True)
        return path if path_only else strict(value) if parse else value
    release_rows=[x['release'] for x in past if x['state']=='RELEASED']
    release=None;staged=None
    if result.get('release') is not None:
        check(len(release_rows)==1,'one actual source-bound RELEASED journal')
        release_pin=release_rows[0];release=linked(release_pin);release_root=Path(release_pin['path']).parent
        check(result['release']==dict(path=packet['remote_root']+'/release/RELEASE.json',sha256=release_pin['sha256'])
              and release['qualification_route_id']==route,'actual current root release identity')
        rfiles={x['relative']:x for x in release['files']}
        check(len(rfiles)==len(release['files']),'unique release bundle members')
        def staged(ref):
            check_pin(ref);p=PurePosixPath(ref['path'])
            check(p.parent==PurePosixPath(packet['remote_root'])/'release' and p.name in rfiles
                  and rfiles[p.name]['sha256']==ref['sha256'],'actual exact release-local evidence')
            return linked(dict(path=str(release_root/p.name),sha256=ref['sha256']))
    statuses={'foundation':('INVENTORY_COMPLETE_KERNEL_PASS_NO_R' if role=='COMPUTE_RUNTIME_INVENTORY' else 'R46_STARTUP_METADATA_PASS_NOT_NUMERICAL_PARITY'),
        'scientific':'PASS_COMPLETE_SCIENTIFIC_METADATA_WORKER','numerical':'PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER'}
    success=result['status']==statuses[family]
    check(complete is success,'actual terminal accounting and worker outcome must agree')
    report=dict(role=role,job_id=job['job_id'],scope_id=packet['scope_id'],node=node,qualification_route_id=route,
        result=result_pin,return_manifest=manifest_pin,accounting=account_pin,actual_phase_guards=dict(observe=og,collect=cg),
        review_scope=pin(scope_path),scope=c['scope'],config=pin(config_path),source_review=c['source_review'],
        source_publication=c['publication'],review_source=pin(__file__,code=True),
        canonical_primary_CPU_seconds=account['canonical_primary_CPU_seconds'],primary_charge_counted_once=True,
        exact_return_files=len(rows),exact_return_bytes=total,separate_return_CPU_cap=cap,all_previous_and_current_fees_retained=True,
        opaque_values_not_deserialized=True,opaque_transport_hashes_verified_by_actual_collect_guard=True,
        no_R_numpy_network_jobs_optimizer_or_target_evaluation_by_review=True,production_admission=False,
        root_accept_and_finalize_still_required=True,issued_epoch=time.time(),expires_epoch=s['expires_epoch'])
    if success:
        check(result.get('error') is None and release is not None,'successful worker requires actual root release and no error')
        temp=dict(result,_remote=packet['remote_root']+'/result',_rows=rows)
        if family=='foundation':
            check(exact_int(result['new_models'],0) and exact_int(result['optimizer_invocations'],0)
                  and result['no_numerical_parity_or_target_bridge_proved'] is True,'foundation zero-model/optimizer bounds')
            detail=kernel_proof(temp,metadata) if role=='COMPUTE_RUNTIME_INVENTORY' else R_startup_proof(temp,ready,release,metadata,staged)
            status='PASS_REVIEWED_STARTUP_BATCH_ROLE'
        elif family=='scientific':
            check(exact_int(result['new_models'],0) and exact_int(result['optimizer_invocations'],0)
                  and result['scientific_data_read'] is False and result['production_admission'] is False
                  and result['numerical_parity_proved'] is False,'scientific zero-target/model/optimizer bounds')
            detail=scientific_proof(temp,ready,release,spec,metadata,staged,source)
            status='PASS_REVIEWED_COMPLETE_SCIENTIFIC_METADATA_ROLE'
        else:
            check(exact_int(result['production_fits'],0) and exact_int(result['pilot_fits'],0)
                  and 0<=result['whole_self_plus_waited_CPU']<600 and 0<=result['wall_seconds']<1200,
                  'numerical qualification whole-accounting bounds')
            detail=numerical_proof(temp,ready,release,spec,c,metadata,staged,source)
            status='PASS_REVIEWED_COMPLETE_FROZEN525_NUMERICAL_ROLE'
        report.update(detail,status=status,complete_success=True)
    else:
        failed={'foundation':'FAILED_METADATA_ROLE','scientific':'FAILED_SCIENTIFIC_METADATA_WORKER','numerical':'FAILED_FROZEN525_NUMERICAL_WORKER'}
        check(result['status']==failed[family] and type(result['error']) is str and result['error'],
              'truthful exact failed allocated worker only')
        report.update(status=('PASS_REVIEWED_FROZEN525_FAILED_ROLE_RETIREMENT' if family=='numerical'
              else 'PASS_REVIEWED_FAILED_STARTUP_BATCH_RETIREMENT'),complete_success=False,no_acceptance_or_retry=True,
              actual_worker_error=result['error'],logger_runtime_tested=False,cause_known=False)
        if release is not None:
            prefix='numerical' if family=='numerical' else 'owner'
            if prefix+'/owned_guard.json' not in rows or prefix+'/owned_tree.json' not in rows:
                report.update(status='REVIEWED_FAILED_ROLE_REQUIRES_LIFETIME_DRAIN_PROOF_NOT_RETIREMENT',
                              claim_retirement_status='OWNER_LIFETIME_PROOF_UNAVAILABLE_KEEP_CLAIM')
            else:
                g=metadata(dict(path=packet['remote_root']+'/result/'+prefix+'/owned_guard.json',
                    sha256=rows[prefix+'/owned_guard.json']['sha256']))
                tree=metadata(dict(path=packet['remote_root']+'/result/'+prefix+'/owned_tree.json',
                    sha256=rows[prefix+'/owned_tree.json']['sha256']))
                owner_lifetime(g,tree,ready,packet['scope_id'],release['owner_authority'])
                report.update(actual_owner_lifetime_closed_reaped_drained=True)
                if family=='numerical':
                    # This helper validates a closed scalar whitelist only; no arrays or optimizer execution.
                    detail=review_post_ack_failure(dict(js=local,pin=pin,linked=linked,root=root,result=result,
                        remote=PurePosixPath(packet['remote_root']),rows=rows,records=past,config=c,unique=unique_pairs,raw=raw,os=os))
                    report.update(scalar_diagnostic_detail=detail,logger_runtime_tested=detail['logger_runtime_tested'],cause_known=False)
        else:
            check(not release_rows,'unreleased failure cannot possess a RELEASED journal')
            report.update(no_root_release_or_owner_or_R_execution=True)
    check(not(root/'ACCEPTED.json').exists(),'independent return review precedes guarded canonical acceptance')
    report['read_set']=list(READS.values());write_new(out/'RETURN_REVIEW.json',report);return report


def main():
    check(os.sched_getaffinity(0)=={31},'administrative31 required')
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--family',choices=tuple(RETURN_CAPS),required=True)
    for key in ['config','role','scope','bundle','observe-guard','collect-guard']:p.add_argument('--'+key,required=True)
    a=p.parse_args();cap=RETURN_CAPS[a.family]
    resource.setrlimit(resource.RLIMIT_CPU,(cap,cap));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(90)
    out=Path(a.bundle);write_new(out/'RETURN_PEER_INTENT.json',dict(status='EXACT_COMPLETE_RETURN_REVIEW_STARTED_NO_REPLAY',
        source=pin(__file__,code=True),config=pin(a.config),scope=pin(a.scope),issued_epoch=time.time()))
    value=review_complete(a.family,a.config,a.role,a.scope,a.bundle,a.observe_guard,a.collect_guard)
    u=resource.getrusage(resource.RUSAGE_SELF);write_new(out/'RETURN_PEER_RECEIPT.json',
        dict(status='COMPLETED_INDEPENDENT_RETURN_METADATA_REVIEW',output=pin(out/'RETURN_REVIEW.json'),
            result_status=value['status'],SELF_CPU_seconds=u.ru_utime+u.ru_stime,CPU_cap=cap,
            no_new_compute_authority=True,read_set=list(READS.values())))
    print(json.dumps(dict(status=value['status'],SELF_CPU=u.ru_utime+u.ru_stime)))

def unique_pairs(pairs):
 out={}
 for key,value in pairs:
  check(key not in out,'duplicate scalar-frame key');out[key]=value
 return out


LIMITS=dict(beta_posterior_sd_rms=1e-4,covariance_whitened_rms=1e-4,elbo_relative=1e-8,
 predictor_rms=1e-6,rhs_joint_log_rates=1e-6,rhs_start_log_precision=1e-6,sigma_relative=1e-6)
NUMERIC_RHS={'unit_iterations','dispersed_iterations','unit_residual','dispersed_residual'}
BOOLEAN_RHS={'unit_converged','dispersed_converged'}

def atom(x):
 assert type(x) is dict and type(x.get('available')) is bool
 if not x['available']:
  assert set(x)=={'available','label'} and x['label'] in {'UNAVAILABLE','REDACTED_NONSCALAR','REDACTED_TYPE'}
  return None
 assert set(x)=={'available','kind','value'} or set(x)=={'available','kind','label'}
 if x['kind']=='number':
  assert set(x)=={'available','kind','value'} and type(x['value']) in (int,float) and math.isfinite(x['value'])
  return x['value']
 if x['kind']=='boolean':
  assert set(x)=={'available','kind','value'} and type(x['value']) is bool
  return None
 assert x['kind']=='nonfinite' and set(x)=={'available','kind','label'} and x['label'] in {'NA','NaN','Inf','-Inf'}
 return None

def certificate(x,fallback):
 assert type(x) is dict and type(x.get('available')) is bool
 if fallback:
  assert x=={'available':False};return
 assert set(x)=={'available','measures','limits','certified','raw_reconstructed_elbo','raw_next_elbo','rhs_reconstruction'}
 assert set(x['measures'])==set(x['limits'])==set(LIMITS)
 assert set(x['rhs_reconstruction'])==NUMERIC_RHS|BOOLEAN_RHS
 for value in [*x['measures'].values(),*x['limits'].values(),x['certified'],x['raw_reconstructed_elbo'],x['raw_next_elbo'],*x['rhs_reconstruction'].values()]:atom(value)

def scalar_frame(frame,spec,parse_frame,line_bytes):
 assert line_bytes<=16384
 assert set(frame)=={'schema','status','role','job_id','node','nonce','source_files','entrypoint','bootstrap_spec',
  'context_complete','diagnostic_available','logging','original_limits','current_cert','old_cert','terminal_sigma','R_exit_status','numerical_acceptance'}
 assert frame['schema']=='r188_post_ACK_bridge_scalar_diagnostic_v1'
 assert frame['status']=='R188_BRIDGE_SCALARS_AFTER_ACK_FAILED_NOT_ACCEPTANCE'
 for key in ['role','job_id','node','nonce']:assert frame[key]==spec[key]
 assert frame['source_files']==parse_frame['source_files']
 assert frame['entrypoint']==spec['entrypoint'] and frame['bootstrap_spec']==spec['bootstrap_spec']
 assert frame['context_complete'] is True and type(frame['diagnostic_available']) is bool
 assert frame['original_limits']==LIMITS and frame['numerical_acceptance'] is False
 assert type(frame['R_exit_status']) is int and frame['R_exit_status']==1
 fallback=frame['logging']=='UNAVAILABLE'
 assert (fallback and frame['diagnostic_available'] is False) or (frame['logging']=='SCALAR_WHITELIST_ONLY' and frame['diagnostic_available'] is True)
 for key in ['current_cert','old_cert']:certificate(frame[key],fallback)
 atom(frame['terminal_sigma'])
 if fallback:return dict(scalars_available=False,scalar_differences={},cause_known=False)
 differences={}
 for key,limit in LIMITS.items():
  old=atom(frame['old_cert']['measures'][key]);current=atom(frame['current_cert']['measures'][key])
  differences[key]=dict(old=old,current=current,difference=None if old is None or current is None else current-old,
   exact_numeric_equal=None if old is None or current is None else current==old,
   original_limit=limit,current_over_original_limit=None if current is None else current/limit)
 return dict(scalars_available=any(v['old'] is not None and v['current'] is not None for v in differences.values()),scalar_differences=differences,cause_known=False)

def review_post_ack_failure(C):
 js=C['js'];pin=C['pin'];linked=C['linked'];root=C['root'];result=C['result'];remote=C['remote'];rows=C['rows']
 report=dict(logger_runtime_tested=False,post_ACK_kernel_proved=False,cause_known=False,
  remote_claim_released=False,claim_retirement_status='EXACT_NATIVE_RETIREMENT_STILL_REQUIRED',
  no_acceptance_or_retry=True,no_scientific_array_values_opened=True)
 if result['release'] is None:
  report.update(no_root_release_or_R_execution=True);return report
 release_record=next(x for x in reversed(C['records']) if x['state']=='RELEASED')
 release=linked(release_record['release']);bundle=Path(release_record['release']['path']).parent
 release_rows={x['relative']:x for x in release['files']}
 def metadata(value):
  p=Path(value['path'])
  if p.is_relative_to(Path(str(remote))/'result'):
   rel=str(p.relative_to(Path(str(remote))/'result'));assert rel in rows and rows[rel]['sha256']==value['sha256']
   path=root/'returned'/rel
  else:
   assert p.parent==Path(str(remote))/'release' and p.name in release_rows
   assert release_rows[p.name]['sha256']==value['sha256'];path=bundle/p.name
  assert path.suffix.lower() not in {'.rds','.rda','.rdata','.bin','.npz'}
  assert pin(path)['sha256']==value['sha256'];return js(path)
 spec=metadata(release['owner_spec']);authority=metadata(release['owner_authority'])
 assert all(spec[k]==result[k] for k in ['job_id','scope_id','role','node'])
 assert authority['spec']==release['owner_spec'] and spec['stage_grant']==release['stage_grant']
 ready=js(root/'READY.json');identity=ready['worker_identity']
 assert identity['uid']==ready['inventory']['scheduler']['uid']==C['os'].getuid()
 assert type(identity['pid']) is type(identity['start_ticks']) is int and identity['pid']>0 and identity['start_ticks']>0
 report['actual_owner_spec']=release['owner_spec'];report['actual_owner_authority']=release['owner_authority']
 if 'numerical/owned_guard.json' not in rows:
  report['claim_retirement_status']='OWNER_LIFETIME_PROOF_UNAVAILABLE_KEEP_CLAIM';return report
 guard=js(root/'returned/numerical/owned_guard.json');tree=js(root/'returned/numerical/owned_tree.json')
 assert guard['schema']=='r157_traced_bootstrap_guard_receipt_v1' and guard['status']=='EXITED'
 for flag in ['reaped','drained','CPU_accounting_complete','all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled']:assert guard[flag] is True
 assert guard['remaining_owned_lifetimes']==guard['unexpected_untraced_child_waits']==[]
 assert guard['maximum_combined_CPU_seconds']==450 and guard['parent_plus_all_reaped_child_CPU_seconds']<450 and guard['wall_seconds']<300
 assert tree['state']=='CLOSED' and tree['scope']==result['scope_id'] and tree['authority_pin']==release['owner_authority']
 for value in [guard['supervisor'],tree['supervisor']]:
  assert all(value[k]==identity[k] for k in ['pid','start_ticks','boot_id','affinity'])
 report['current_owned_lifetime_closed_reaped_drained']=True
 att=guard.get('scientific_filter_kernel_attestation')
 if not att:return report
 deny=0x00050000|errno.EPERM;enosys=0x00050000|errno.ENOSYS
 ins=[(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),(0x20,0,0,0),(0x45,0,1,0x40000000),
  (0x06,0,0,deny),(0x15,0,1,57),(0x06,0,0,deny),(0x15,0,1,58),(0x06,0,0,deny),(0x15,0,1,435),
  (0x06,0,0,enosys),(0x15,0,3,56),(0x20,0,0,16),(0x45,1,0,0x10000),(0x06,0,0,deny),(0x06,0,0,0x7fff0000)]
 program=hashlib.sha256(b''.join(struct.pack('<HBBI',*x) for x in ins)).hexdigest()
 assert att['operation']=='SECCOMP_SET_MODE_FILTER' and att['flags']=='TSYNC' and att['kernel_return']==0
 assert att['instruction_count']==17 and att['program_sha256']==program
 assert guard['postbootstrap_TSYNC_scientific_fork_denial'] is True and guard['scientific_target_access_handshake'] is True
 gate=js(root/'returned/numerical/PARSE_PARENT_GATE.json')
 assert gate['status']=='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK'
 assert gate['authority']==release['owner_authority'] and gate['original_tracer_pre_ACK_capture_callback'] is True
 assert gate['kernel_ACK_still_requires_original_guard_completion'] is True
 for key in ['role','job_id','node','scope_id']:assert gate[key]==spec[key]
 parse=gate['frame']
 assert parse['status']=='R182_FROZEN_SOURCE_PARSE_PASS_BEFORE_NUMERICAL_ENTRYPOINT'
 for key in ['role','job_id','node','nonce']:assert parse[key]==spec[key]
 assert parse['source_files']==[spec['scientific_sources'][x] for x in sorted(spec['scientific_sources'])]
 assert parse['optimizer_invocations']==0 and parse['scientific_target_data_read'] is False
 assert {k:v['sha256'] for k,v in spec['scientific_sources'].items()}=={k:v['sha256'] for k,v in C['config']['scientific_sources'].items()}
 snapshot=js(root/'returned/PHYSICAL_SNAPSHOT.json');current=js(root/'returned/numerical/PHYSICAL_BEFORE_R.json')
 assert snapshot==ready['physical_snapshot_value']
 for key in ['topology','Slurm_core_policy','job_cpuset','online_thread_siblings']:assert snapshot[key]==current[key]
 for fs in [snapshot['filesystem'],current['filesystem'],gate['filesystem_before_ACK']]:
  assert fs['path']==spec['remote_namespace'] and fs['quota_status']=='UNKNOWN'
  assert fs['minimum_available_bytes']==80*1024**3 and fs['available_bytes']>=80*1024**3
  assert fs['available_bytes']==fs['fragment_bytes']*fs['available_blocks']
 report.update(post_ACK_kernel_proved=True,current_parse_before_ACK_verified=True,exact_kernel_program_sha256=program)
 stdout=root/'returned/numerical/child.stdout'
 raw=C['raw'](stdout);assert len(raw)<=2*1024**2
 frames=[]
 for line in raw.splitlines():
  if line.lstrip().startswith(b'{'):
   value=json.loads(line,object_pairs_hook=C['unique'],parse_constant=lambda x:(_ for _ in ()).throw(ValueError('nonfinite JSON')))
   frames.append((value,len(line)))
 assert frames and frames[0][0]==parse
 diagnostics=[(v,size) for v,size in frames[1:] if v.get('schema')=='r188_post_ACK_bridge_scalar_diagnostic_v1']
 assert len(diagnostics)<=1 and len(frames)==1+len(diagnostics)
 if not diagnostics:return report
 frame,size=diagnostics[0];detail=scalar_frame(frame,spec,parse,size)
 assert guard['returncode']==1
 report.update(detail,logger_runtime_tested=True,diagnostic_frame=frame,diagnostic_frame_bytes=size,
  diagnostic_frame_source=pin(stdout),R_failure_exit_status=1,numerical_acceptance=False)
 return report



if __name__=='__main__':main()

