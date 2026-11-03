"""Independent r203 metadata policy; never delegates to stage-owner validators.

Only basic immutable metadata IO/type/hash primitives are shared. Actual role
admission, captures, raw native facts and complete accounting are rechecked here.
"""
import datetime,errno,hashlib,importlib.util,json,os,re,resource,sys,time
from pathlib import Path
ROOT=Path(__file__).absolute().parent.parent
_MP=ROOT/'common/metadata.py';_raw=_MP.read_bytes()
if hashlib.sha256(_raw).hexdigest()!='6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':
    raise ValueError('exact independently reviewed basic metadata primitives')
_sp=importlib.util.spec_from_file_location('_r203_independent_basic_metadata',_MP)
m=importlib.util.module_from_spec(_sp);exec(compile(_raw,str(_MP),'exec'),m.__dict__)
BASE=m.strict_json(m.source_bytes(dict(path=str(ROOT/'RUNTIME_BASE.json'),sha256='85bce27c0cc4aaf16e744c1abb0988abdea64ef582c578fb8871997db6a8e543')))
POLICY=m.strict_json(m.source_bytes(dict(path=str(ROOT/'PEER_POLICY.json'),sha256='65094e86aca9121f776bffff260ddb6a84890a8f39344291ab9a6456d7cbf234')))
CATALOG_SHA='33195e8a0a67663fc8286a682f8885c0e6b6995798d50faca592a82e4618a305'
STAGES={'FACILITY_PRECHECK','OWNED_NATIVE_BUILD','READONLY_DEPLOYMENT','NATIVE_ABI_SUITE'}
CASES=('pre_ack_live','wrong_lifetime','wrong_permit','late_transition','repeat_transition',
       'real_ACK','live_rechecks','noreplace_collision','bounded_storage')
CASE_NAMES={'preparation_outside_trace_refused','pre_ack_live_refused','wrong_lifetime_refused',
 'wrong_permit_refused','late_or_repeated_transition_refused','real_TSYNC_ACK',
 'live_identity_permit_rechecks','noreplace_collision_refused','bounded_payload_proof_storage','complete_reap_drain'}
FLAGS=('all_owned_descendants_reaped','independent_guardian','kernel_escape_filter',
       'orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once')
def admin_before_records(cpu=5):
    m.require(os.sched_getaffinity(0)=={31} and resource.getrlimit(resource.RLIMIT_CPU)==(cpu,cpu)
      and os.getpid()==os.getsid(0)==os.getpgrp(),'actual new original-H administrative context before records')
    s=dict(x.split(':',1) for x in Path('/proc/self/status').read_text().splitlines() if ':' in x)
    m.require(s.get('NoNewPrivs','').strip()=='1' and s.get('Seccomp','').strip()=='2','actual original-H kernel boundary')
def _guard_value(g,result,cpu):
    for k in ('returncode','command_returncode','CPU_limit'):m.require(type(g.get(k)) is int,'typed actual guard '+k)
    m.require(g['returncode']==g['command_returncode']==0 and g['CPU_limit']==cpu
      and g.get('cap_reason') is None and g.get('guardian_forced_monitor_stop') is False,'actual healthy whole guard')
    for k in ('aggregate_CPU_seconds','complete_lifecycle_wall_seconds'):m.finite(g.get(k),k)
    m.require(0<=g['aggregate_CPU_seconds']<cpu and 0<=g['complete_lifecycle_wall_seconds']<=180
      and all(g.get(k) is True for k in FLAGS),'actual complete CPU/wall/owned lifecycle')
    m.require(m.strict_json(g['stdout'])==result and g['session_id']==result.get('command_pid')
      and g['leader_start_ticks']==result.get('command_birth_ticks'),'actual stdout/PID/birth binding')
    return result
def guarded(pair,cpu=8):
    m.closed(pair,{'result','guard'},'actual result/guard pair')
    return _guard_value(m.linked(pair['guard']),m.linked(pair['result']),cpu)
def program(pin,t,name='peer/independent_peer.py'):
    m.descriptor(pin)
    m.require(pin['sha256']==t['control_sources'][name]['sha256'],'independently reviewed program source SHA')
def resolve(pin,observation=None):
    m.descriptor(pin)
    if observation is not None:
        rows=[r for r in observation.get('records',[]) if r.get('remote_path')==pin['path']]
        m.require(len(rows)<=1,'unique actual captured remote path')
        if rows:
            r=rows[0];m.closed(r,{'remote_path','sha256','local_copy'},'actual byte-copy row')
            m.require(r['sha256']==pin['sha256'] and r['local_copy']['sha256']==pin['sha256'],'actual exact remote bytes, no JSON rewrite')
            return m.linked(r['local_copy'])
    return m.linked(pin)
def _same(v,r,keys=('purpose','nonce','stage','job_id','node')):
    for k in keys:m.require(v.get(k)==r[k],'same actual '+k)
def _lineage(current,ancestor):
    seen=set()
    for _ in range(96):
        v=m.linked(current)
        if current==ancestor:return True
        m.require(current['sha256'] not in seen,'acyclic complete ledger');seen.add(current['sha256'])
        previous=v.get('previous');old=m.linked(previous)
        m.require(set(v)==set(old)|{'previous','created_epoch'} and len(v['scopes'])==len(old['scopes'])+1
          and v['scopes'][:-1]==old['scopes'],'whole inherited ledger fields and one new row')
        row=v['scopes'][-1];s=m.linked(row['scope'])
        admin=m.integer(row.get('administrative_CPU_reservation'),'full new admin',1)
        compute=m.integer(row.get('compute_CPU_reservation'),'full primary compute',0)
        m.require(s.get('previous_ledger',s.get('ledger_before'))==previous
          and s.get('purpose')==row.get('purpose') and s.get('new_administrative_CPU_reservation')==admin
          and s.get('compute_CPU_reservation',s.get('new_compute_CPU_reservation'))==compute
          and all(x.get('purpose')!=row['purpose'] for x in old['scopes']),'no old fee/intent reuse')
        counters=('total_administrative_reservation','total_new_administrative_reservation',
                  'total_qualification_compute_reservation','total_new_qualification_compute_reservation')
        for k,n in zip(counters,(admin,admin,compute,compute)):
            m.require(type(v[k]) is type(old[k]) is int and v[k]==old[k]+n,'exact whole counter '+k)
        before=old['compute_roles'];after=v['compute_roles']
        m.require(after[:len(before)]==before,'old primary roles intact')
        if compute:m.require(len(after)==len(before)+1 and after[-1]==dict(purpose=s['purpose'],stage=s['stage'],scope=row['scope'],compute_CPU_reservation=compute,primary_actual_CPU=None),'one exact new primary charge')
        else:m.require(after==before,'source-only append has no compute role')
        for k in old:
            if k not in {'previous','created_epoch','scopes','compute_roles',*counters}:m.require(v[k]==old[k],'old field '+k)
        current=previous
    raise ValueError('bounded whole ledger must reach exact control publication')
def template(pin,check_current=True):
    t,q=_template_value(m.linked(pin),check_current,True)
    script_policy(t,pin['path'])
    return t,q

def _template_value(t,check_current=True,require_admission=True):
    keys={'schema','purpose','nonce','stage','node','control_publication','control_sources','control_map_sha256',
      'runtime_publication','runtime_sources','runtime_map_sha256','scope','ledger','quote',
      'bootstrap_authority','admission','output_root','parameters','issued_epoch','expires_epoch'}
    m.closed(t,keys,'closed exact template');m.require(t['schema']=='r203_control_job_template_v1' and t['stage'] in STAGES,'control stage only')
    m.require(type(t['nonce']) is str and re.fullmatch('[0-9a-f]{32}',t['nonce']),'one exact nonce')
    for k in ('issued_epoch','expires_epoch'):m.finite(t[k],k)
    m.require(0<t['expires_epoch']-t['issued_epoch']<=28800,'finite stage interval')
    if check_current:m.require(t['issued_epoch']<=time.time()<t['expires_epoch'],'live stage interval')
    m.require(t['runtime_publication']==BASE['runtime_publication']
      and t['runtime_map_sha256']==BASE['runtime_map_sha256']
      and {k:p['sha256'] for k,p in t['runtime_sources'].items()}==BASE['runtime_source_hashes'],'immutable runtime39')
    pub=m.linked(t['control_publication']);hashes={k:p['sha256'] for k,p in t['control_sources'].items()}
    m.require(pub.get('schema')=='r203_control_source_publication_v1'
      and pub.get('status')=='PASS_PUBLISHED_R203_CONTROL_SOURCE_PREPARATION'
      and pub.get('commit')==pub.get('remote_readback') and pub.get('files')==hashes
      and m.digest(hashes)==t['control_map_sha256']
      and pub.get('runtime_source_publication')==BASE['runtime_publication']
      and pub.get('runtime_admitted') is False,'actual separate control publication, no qualification transfer')
    s=m.linked(t['scope']);q=m.linked(t['quote'])
    m.require(s.get('schema')=='r203_funded_control_stage_scope_v1'
      and s.get('status')=='ROOT_FUNDED_R203_CONTROL_STAGE_NO_TARGETS','source448 never execution funding')
    for k in ('purpose','nonce','stage','control_publication','control_map_sha256','runtime_publication','runtime_map_sha256'):
        m.require(s.get(k)==q.get(k)==t[k],'same funded '+k)
    for k,v in [('maximum_jobs',1),('maximum_owner_calls',1),('optimizer_invocations',0),('new_posterior_fits',0)]:
        m.require(type(s.get(k)) is int and s[k]==v,'one stage/no fit '+k)
    m.require(s.get('automatic_retry') is False and s.get('requeue') is False
      and s.get('target_input_manifest') is None and s.get('remote_namespace')==t['output_root'],'closed target-free namespace')
    components=('startup','namespace','import','optimizer','certification','checkpoint','return','independent_peer','closure')
    m.closed(q.get('components'),components,'all nine cost components')
    channels=('compute_CPU_upper_seconds','administrative_CPU_upper_seconds','remote_unknown_CPU_reservation')
    totals=('compute_CPU_reservation','administrative_CPU_reservation','remote_unknown_CPU_reservation')
    for c in q['components'].values():
        m.require(c.get('covered') is True,'complete cost coverage')
        for k in (*channels,'CPU_upper_seconds','wall_upper_seconds'):m.integer(c.get(k),k,0)
        m.require(c['CPU_upper_seconds']==sum(c[k] for k in channels),'no double-counted cost channels')
    for c,k in zip(channels,totals):
        m.integer(q.get(k),k,0);m.require(sum(v[c] for v in q['components'].values())==q[k],'full channel '+k)
    m.require(q['compute_CPU_reservation']>0 and q['components']['optimizer']['compute_CPU_upper_seconds']==0
      and s.get('compute_CPU_reservation')==q['compute_CPU_reservation']
      and s.get('new_administrative_CPU_reservation',0)>=q['administrative_CPU_reservation']+q['remote_unknown_CPU_reservation'],'new full funds')
    m.require(q['components']['startup']['wall_upper_seconds']>=120
      and q['whole_CPU_seconds']==sum(q[k] for k in totals)
      and sum(c['wall_upper_seconds'] for c in q['components'].values())==q['whole_wall_seconds']<=28800,'whole startup/lifecycle quote')
    params=m.digest(t['parameters']);m.require(s.get('parameters_sha256')==q.get('parameters_sha256')==params,'exact parameters')
    qr=m.linked(q['independent_review']);core=dict(q);core.pop('independent_review')
    m.require(qr.get('status')=='PASS_REVIEWED_R203_CONTROL_STAGE_QUOTE' and qr.get('quote_core_sha256')==m.digest(core),'acyclic independent price')
    program(qr['independent_program'],t)
    m.require(s['issued_epoch']<=t['issued_epoch']<t['expires_epoch']==s['expires_epoch'],'original runtime window')
    _lineage(t['ledger'],pub['source_ledger'])
    ledger=m.linked(t['ledger']);rows=[r for r in ledger['scopes'] if r.get('scope')==t['scope']]
    roles=[r for r in ledger['compute_roles'] if r.get('scope')==t['scope']]
    m.require(len(rows)==len(roles)==1 and rows[0]['administrative_CPU_reservation']==s['new_administrative_CPU_reservation']
      and rows[0]['compute_CPU_reservation']==roles[0]['compute_CPU_reservation']==q['compute_CPU_reservation'],'one primary actual funded row')
    profile=m.linked(t['parameters']['common']['physical_profile'])
    profile_values(profile,q['owner_wall_seconds'],t['parameters']['common']['canonical_metadata_root'],t['nonce'])
    m.require(not Path(t['parameters']['common']['canonical_metadata_root']).is_relative_to(Path(t['output_root'])),'Slurm logs/chdir cannot precreate future fresh owner root')
    m.require(q['reserved_filesystem_bytes']>=sum(row['maximum_bytes'] for row in t['parameters']['common']['storage_policy']['slots'])+q['transient_tree_reservation_bytes']+t['parameters']['common']['storage_policy']['dynamic_artifact_reservation_bytes']+32*1024**2,'external native logs have disjoint physical reservation')
    m.finite(ledger['created_epoch'],'actual new ledger clock')
    m.require(s['issued_epoch']<=ledger['created_epoch']<=t['issued_epoch'] and roles[0]==dict(purpose=t['purpose'],stage=t['stage'],scope=t['scope'],compute_CPU_reservation=q['compute_CPU_reservation'],primary_actual_CPU=None),'actual immediate ledger clock and exact primary role')
    script_policy(t)
    if require_admission:validate_admission(t,q,check_current)
    return t,q
def request(pin,check_current=True):
    r=m.linked(pin);t,q=template(r['template'],check_current)
    m.require(r.get('schema')=='r203_control_stage_request_v1' and r['root']==t['output_root'],'actual request')
    _same(r,t,('purpose','nonce','stage','node','control_map_sha256','runtime_map_sha256','scope','ledger','quote'))
    m.integer(r['owner']['pid'],'actual owner PID',1);m.integer(r['owner']['start_ticks'],'actual owner birth',1)
    m.require(type(r['job_id']) is str and re.fullmatch('[1-9][0-9]{0,11}',r['job_id'])
      and type(r['affinity']) is list and len(r['affinity'])==1,'actual job and one CPU')
    m.integer(r['affinity'][0],'CPU',0);m.integer(r['permit_fd'],'real permit fd',3)
    return r,t,q
def observation(pin,r,t,mode,request_pin):
    pair=pin;o=_pair_capture(pair,t,mode,r)
    m.require(o['request']==request_pin and o['template']==r['template'],'actual postREADY request capture; discovery cannot replace it')
    m.require(o.get('schema')=='r203_owned_stage_metadata_capture_v1'
      and o.get('status')=='CAPTURED_R203_ACTUAL_NATIVE_STAGE_METADATA_NOT_ADMISSION'
      and o.get('mode')==mode,'actual exact capture mode')
    _same(o,r);program(o['controller_source'],t,'peer/observation_capture.py')
    m.require(0<=time.time()-o['completed_epoch']<=90,'actual fresh source/owner capture')
    paths=[v['remote_path'] for v in o['records']];m.require(len(paths)==len(set(paths)),'unique canonical copies')
    return o
def _physical(r,t,q,w,o):
    _same(w,r)
    m.require(w.get('schema')=='r203_actual_control_physical_witness_v1' and w.get('owner')==r['owner']
      and w.get('affinity')==r['affinity'] and w.get('parameters_sha256')==m.digest(t['parameters']),'actual physical owner witness')
    m.require(re.search(r'(?:^|/)job_'+re.escape(r['job_id'])+r'(?:/|$)',w['cgroup_path']),'actual job cgroup')
    siblings=w['online_thread_siblings'];effective=w['effective_job_cpus']
    m.require(type(siblings) is list and type(effective) is list and siblings
      and all(type(v) is int and v>=0 for v in siblings+effective)
      and r['affinity'][0] in siblings and set(siblings)<=set(effective),'whole physical-core SMT ownership')
    m.integer(w['cgroup_memory_limit_bytes'],'job memory',1)
    m.require(w['cgroup_memory_limit_bytes']<=q['memory_MiB']*1024**2
      and w['mandatory_headroom_bytes']>=q['mandatory_headroom_bytes']
      and w['filesystem_available_bytes']>=w['mandatory_headroom_bytes']+q['transient_tree_reservation_bytes'],'actual memory and live storage')
    reservation=resolve(w['reservation'],o);slots=t['parameters']['common']['storage_policy']['slots']
    m.closed(reservation,{'schema','owner','root','slots','physical_slot_bytes','created_epoch','no_sparse_fallback_or_cleanup'},'actual reservation')
    m.require(reservation['schema']=='r203_actual_preREADY_reservation_v1' and reservation['owner']==r['owner']
      and reservation['root']==r['root'] and reservation['no_sparse_fallback_or_cleanup'] is True
      and len(reservation['slots'])==len(slots),'complete actual preREADY slots')
    expected={v['name']:v for v in slots};seen=set();inodes=set();total=0
    for row in reservation['slots']:
        m.closed(row,{'name','kind','maximum_bytes','final_alias','device','inode'},'actual reserved slot row')
        name=row['name'];m.require(name in expected and name not in seen,'exact unique prepaid slot')
        m.require({k:row[k] for k in expected[name]}==expected[name],'fixed slot capacity/alias plan')
        m.integer(row['inode'],'physical slot inode',1);m.integer(row['device'],'physical slot device',0)
        identity=(row['device'],row['inode']);m.require(identity not in inodes,'one actual paid inode per slot')
        inodes.add(identity);seen.add(name);total+=row['maximum_bytes']
    m.require(seen==set(expected) and total==reservation['physical_slot_bytes']
      and total==t['parameters']['common']['storage_policy']['physical_proof_reservation_bytes'],'exact physical sum, no alias double charge')
    return True
def _source(r,t,o):
    w=resolve(r['source_capture'],o)
    _same(w,r)
    m.require(w.get('schema')=='r203_actual_control_source_capture_v1'
      and w['control_sources']==t['control_sources'] and w['runtime_sources']==t['runtime_sources']
      and w['control_map_sha256']==t['control_map_sha256']
      and w['runtime_map_sha256']==t['runtime_map_sha256'],'actual full two-source closure')
    files={v['path']:v for v in w['files']}
    required=list(t['control_sources'].values())+list(t['runtime_sources'].values())
    required+=t['parameters']['common']['source_and_baseline']['baseline_files']
    for p in required:
        m.require(p['path'] in files and files[p['path']]['sha256']==p['sha256'],'actual captured source/baseline bytes')
    ro={v['path']:v for v in w['readonly_files']}
    for p in required:
        m.require(p['path'] in ro and 'ro' in ro[p['path']]['mount_options']
          and 'ro' in ro[p['path']]['super_options'],'actual RO backing, no bind-only claim')
    return w
def source_physical(request_pin,observation_pair,output_path):
    admin_before_records(5);r,t,q=request(request_pin);o=observation(observation_pair,r,t,'SOURCE_PHYSICAL',request_pin)
    _job_observation(o,r);_source(r,t,o);_physical(r,t,q,resolve(r['physical_witness'],o),o);now=time.time()
    v=dict(schema='r203_control_source_physical_review_v1',status='PASS_REVIEWED_R203_ACTUAL_SOURCE_PHYSICAL',
      request=request_pin,template=r['template'],**{k:r[k] for k in ('purpose','nonce','stage','job_id','node')},
      **{k:t[k] for k in ('control_publication','control_map_sha256','runtime_publication','runtime_map_sha256')},
      parameters_sha256=m.digest(t['parameters']),source_capture=r['source_capture'],physical_witness=r['physical_witness'],
      observation=observation_pair,independent_program=m.pin_file(Path(__file__)),runtime_admitted=False,
      issued_epoch=now,expires_epoch=min(r['expires_epoch'],now+60))
    return m.write_new(output_path,v)
def owner_release(request_pin,source_review_pin,observation_pair,output_path):
    admin_before_records(5);r,t,q=request(request_pin);s=m.linked(source_review_pin)
    _same(s,r);program(s['independent_program'],t)
    m.require(s['status']=='PASS_REVIEWED_R203_ACTUAL_SOURCE_PHYSICAL' and s['request']==request_pin
      and s['issued_epoch']<=time.time()<s['expires_epoch'],'actual separate first phase')
    o=observation(observation_pair,r,t,'OWNER_READY',request_pin);ready=resolve(r['ready'],o)
    _same(ready,r);m.require(ready['schema']=='r203_control_owner_ready_v1'
      and ready['status']=='READY_R203_METADATA_ONLY_AWAIT_TWO_PEERS_AND_ROOT_RELEASE'
      and ready['owner']==r['owner'] and ready['permit_fd']==r['permit_fd']
      and ready['source_capture']==r['source_capture'] and ready['physical_witness']==r['physical_witness']
      and ready['created_epoch']<=time.time()<ready['expires_epoch']<=ready['created_epoch']+120,'actual one READY120')
    _job_observation(o,r);_source(r,t,o);_physical(r,t,q,resolve(r['physical_witness'],o),o);now=time.time()
    v=dict(schema='r203_control_owner_release_review_v1',status='PASS_REVIEWED_R203_ACTUAL_OWNER_RELEASE',
      request=request_pin,template=r['template'],source_review=source_review_pin,
      **{k:r[k] for k in ('purpose','nonce','stage','job_id','node')},
      **{k:t[k] for k in ('control_publication','control_map_sha256','runtime_publication','runtime_map_sha256')},
      parameters_sha256=m.digest(t['parameters']),owner_ready=r['ready'],physical_witness=r['physical_witness'],
      observation=observation_pair,independent_program=m.pin_file(Path(__file__)),runtime_admitted=False,
      issued_epoch=now,expires_epoch=min(r['expires_epoch'],s['expires_epoch'],ready['expires_epoch']))
    return m.write_new(output_path,v)
def traced_guard(pin,r,handshake):
    g=m.linked(pin)
    m.require(g.get('schema')=='r157_traced_bootstrap_guard_receipt_v1' and g.get('status')=='EXITED'
      and type(g.get('returncode')) is int and g['returncode']==0
      and all(g.get(k) is True for k in ('reaped','drained','CPU_accounting_complete',
       'all_newborns_kernel_traced_before_execution','tracer_death_kernel_EXITKILL_enabled'))
      and g.get('remaining_owned_lifetimes')==[] and g.get('unexpected_untraced_child_waits')==[],
      'actual complete original traced subject')
    p=g['supervisor'];m.require(p['pid']==r['owner']['pid'] and p['start_ticks']==r['owner']['start_ticks'],'same actual owner/tracer lifetime')
    m.require(g.get('scientific_target_access_handshake') is handshake,'fixed exact handshake policy')
    if not handshake:m.require(g.get('postbootstrap_TSYNC_scientific_fork_denial') is False and g.get('scientific_filter_kernel_attestation') is None,'negative has no earned TSYNC or ACK')
    if handshake:
        m.require(g.get('postbootstrap_TSYNC_scientific_fork_denial') is True,'actual earned postbootstrap fork denial')
        a=g.get('scientific_filter_kernel_attestation') or {}
        m.require(a.get('operation')=='SECCOMP_SET_MODE_FILTER' and a.get('flags')=='TSYNC'
          and a.get('kernel_return')==0,'actual once earned kernel transition')
    return g
def _ops(v):
    rows=v.get('operations')
    m.require(type(rows) is list and rows,'actual raw native operations')
    terminal=False
    for p in rows:
        m.closed(p,{'operation','arguments','return_value','errno','first_error','started_epoch','finished_epoch','receipt'},'closed raw native operation')
        m.require(not terminal and p['operation'] in {'r201_prepare_v1','r201_scientific_boundary_v1','r201_validate_live_v1','r201_rename_noreplace_v1','r201_receipt_v1'},'fixed operation/no failed singleton reuse')
        m.require(type(p['return_value']) is int and p['return_value'] in (0,-1),'actual C return')
        m.finite(p['started_epoch'],'native start');m.finite(p['finished_epoch'],'native end')
        m.require(p['started_epoch']<=p['finished_epoch'],'actual native clock order')
        if p['return_value']==-1:
            m.require(type(p['errno']) is int and p['errno']==errno.EPERM
              and type(p['first_error']) is str and p['first_error'] and p['receipt'] is None,'observed refusal, no invented private state')
            terminal=True
        else:m.require(p['first_error'] is None,'success errno unspecified; no stale error claim')
    return rows
def founder(v,r,t):
    m.require(v.get('schema')=='r203_ABI_founder_raw_observation_v1'
      and v.get('status')=='RAW_FOUNDER_NATIVE_OBSERVATION_NOT_ACCEPTED'
      and type(v.get('actual_tracer_pid')) is int and v['actual_tracer_pid']==0
      and {k:v['owner'][k] for k in r['owner']}==r['owner']
      and v['owner']['tracer_pid']==0 and v['native_role']==1
      and v['isolated_trace_predicate_proved'] is False and v['private_terminal_state_observed'] is None
      and v['no_target_data'] is True,'honest actual founder observational facts')
    _same(v,r,('job_id','node'))
    parent=v['actual_parent'];m.require(parent['pid']==v['owner']['ppid'] and parent['pid']>1 and parent['start_ticks']>0,'actual parent facts')
    abi_probe(v['abi_probe'],t)
    ops=_ops(v);m.require(len(ops)==1 and ops[0]['operation']=='r201_prepare_v1' and ops[0]['return_value']==-1,'one actual founder refusal')
    env=v['environment_preconditions'];matrix=v['unmet_precondition_matrix']
    m.require(all(env[k] is None for k in ('R157_FILTER_PROOF_FD','R157_FILTER_ACK_FD','R157_FILTER_TOKEN'))
      and matrix['unavailable_required_facts']==[] and matrix['actual_tracer_pid']==0
      and matrix['parent_is_actual_kernel_tracer'] is False
      and matrix['real_proof_pipe_available'] is matrix['real_ACK_pipe_available'] is matrix['real_original_token_available'] is False
      and matrix['actual_FLOCK_holder_pid']==r['owner']['pid']
      and ops[0]['arguments']['owner_pid']==parent['pid']
      and ops[0]['arguments']['owner_start_ticks']==parent['start_ticks']
      and ops[0]['arguments']['permit_fd']==r['permit_fd']
      and ops[0]['first_error']=='exact inherited original handshake unavailable','actual unmet conjunction and exact first error, no isolated causality claim')
    return True
def _native_subject(v,r,t,case,g):
    m.require(v.get('schema')=='r203_ABI_subject_raw_result_v1' and v.get('status')=='RAW_NATIVE_SUBJECT_FACTS_NOT_ACCEPTED'
      and v.get('case_id')==case and type(v.get('ordinal')) is int and v['ordinal']==CASES.index(case)+1
      and v['owner']==r['owner'] and v['native_role']==1 and v['no_target_data'] is True
      and v['no_optimizer_or_fit'] is True,'actual fixed native subject facts')
    _same(v,r,('job_id','node'));child=g['owned_root']
    m.require(v['child']['pid']==child['pid'] and v['child']['start_ticks']==child['start_ticks']
      and v['child']['ppid']==v['child']['tracer_pid']==r['owner']['pid']
      and v['runtime_map_sha256']==t['runtime_map_sha256'] and v['control_map_sha256']==t['control_map_sha256'],'actual child/tracer/two maps')
    abi_probe(v['abi_probe'],t)
    ops=_ops(v)
    expected={
      'pre_ack_live':['prepare','validate_live'],'wrong_lifetime':['prepare'],'wrong_permit':['prepare'],
      'late_transition':['prepare','scientific_boundary'],
      'repeat_transition':['prepare','scientific_boundary','receipt','scientific_boundary'],
      'real_ACK':['prepare','scientific_boundary','validate_live','receipt'],
      'live_rechecks':['prepare','scientific_boundary','validate_live','receipt','validate_live','receipt'],
      'noreplace_collision':['prepare','scientific_boundary','receipt','rename_noreplace'],
      'bounded_storage':['prepare','scientific_boundary','rename_noreplace','validate_live','receipt']}
    m.require([p['operation'] for p in ops]==['r201_'+n+'_v1' for n in expected[case]],'exact independent native operation sequence')
    errors={'pre_ack_live':'actual once-earned native lifetime is no longer live',
      'wrong_lifetime':'actual owner trace permit or handshake pipe mismatch','wrong_permit':'inherited permit missing',
      'late_transition':'actual prepared owner required before once-only kernel transition',
      'repeat_transition':'actual prepared owner required before once-only kernel transition',
      'noreplace_collision':'existing or unprovable final refuses without cleanup'}
    for index,p in enumerate(ops):
        fail=case in errors and index==len(ops)-1
        m.require(p['return_value']==(-1 if fail else 0),'actual success/refusal position')
        if fail:m.require(p['first_error']==errors[case],'exact observed first error')
    args=ops[0]['arguments'];birth=r['owner']['start_ticks']+(1 if case=='wrong_lifetime' else 0)
    m.require(args['owner_pid']==r['owner']['pid'] and args['owner_start_ticks']==birth
      and args['permit_fd']==(2147483647 if case=='wrong_permit' else r['permit_fd'])
      and args['role']==1 and args['expires_epoch']==v['actual_native_expiry_epoch'],'exact deliberate argument scope')
    o=v['observations']
    if case=='wrong_permit':
        wrong=o['wrong_native_argument']
        m.require(wrong['requested_fd']==2147483647 and wrong['actual_fstat_errno']==errno.EBADF
          and wrong['Root_permit_fd']==r['permit_fd']
          and wrong['coverage']=='WRONG_NATIVE_ARGUMENT_NOT_EVERY_LIVE_WRONG_INODE','literal wrong-argument coverage with healthy Root permit')
    if case=='late_transition':
        expiry=v['actual_native_expiry_epoch'];der=v['expiry_derivation']
        m.require(der['kind']=='PREP_READY_PLUS_SECONDS_WITH_FIXED_DESCRIPTOR_UPPER_BOUND'
          and der['native_interval_seconds']==2 and der['wait_margin_seconds']==1
          and expiry==der['ready_epoch']+2 and der['descriptor_upper_bound_epoch']==v['native_deadline_upper_bound_epoch']
          and ops[0]['finished_epoch']<expiry and ops[-1]['started_epoch']>=expiry+1
          and expiry+1<v['native_deadline_upper_bound_epoch'],'real prepare then actual expiry before late transition, no renewal')
    receipts=[p['receipt'] for p in ops if p['operation']=='r201_receipt_v1' and p['return_value']==0]
    if case in CASES[4:]:m.require(receipts,'actual live state3 receipt before terminal refusal where applicable')
    for a in receipts:
        m.require(a['abi_version']==1 and a['state']==3 and a['role']==1 and a['uid']==r['uid']
          and a['child_pid']==child['pid'] and a['child_start_ticks']==child['start_ticks']
          and a['owner_pid']==r['owner']['pid'] and a['owner_start_ticks']==r['owner']['start_ticks']
          and a['boot_id']==r['owner']['boot_id'] and a['job_id']==r['job_id']
          and a['node'].split('.')[0]==r['node'] and a['expires_epoch']==v['actual_native_expiry_epoch'],'actual earned native receipt identity')
    if case=='live_rechecks':m.require(o['first_identity']==o['second_identity'],'current actual identity unchanged across two live checks')
    if case=='noreplace_collision':
        m.require(o['before']==o['after'] and len(o['before'])==2,'actual both collision files preserved')
        for row in o['before'].values():
            for key in ('device','inode','bytes'):m.integer(row[key],key,0)
            m.require(row['nlink']==1 and row['bytes']>0 and row['uid']==r['uid'],'actual existing single-link collision file')
    if case=='bounded_storage':
        before=o['payload_before'];after=o['payload_after'];cap=o['kernel_cap_probe']
        m.require(o['rename_source_absent'] is True and
          tuple(before[k] for k in ('device','inode','sha256','bytes'))==tuple(after[k] for k in ('device','inode','sha256','bytes'))
          and before['path'].endswith('.partial') and after['path'].endswith('.final')
          and cap['limit_bytes']==512*1024 and cap['actual_RLIMIT_FSIZE']==[512*1024,512*1024]
          and cap['actual_errno']==errno.EFBIG and cap['before_bytes']==cap['after_bytes']==cap['actual_cursor']==512*1024
          and cap['coverage']=='ABI_CONTROL_ASCII_KERNEL_FSIZE_NOT_PRODUCTION_WRITER','actual sameinode rename and real bounded ABI kernel storage; production writer unqualified')
    return True
def _read_stream(slot,o=None):
    m.descriptor(slot)
    pin=copy_pin(slot,o)
    m.require(Path(slot['path']).suffix in {'.json','.stdout','.stderr','.txt'},'allowlisted control stream')
    return m.read_regular(pin['path'],limit=16*1024**2,expected_sha=pin['sha256'],expected_uid=os.getuid())
def reconstruct_ABI(raw_pin,accounting_pin):
    raw,r,t,q,account,observation_copy=raw_stage(raw_pin,accounting_pin,'NATIVE_ABI_SUITE')
    _same(raw,r)
    m.require(raw.get('schema')=='r203_owned_control_raw_stage_result_v1'
      and raw.get('status')=='RAW_R203_CONTROL_STAGE_NOT_ACCEPTED_AWAIT_TERMINAL_ACCOUNTING'
      and r['stage']=='NATIVE_ABI_SUITE' and raw.get('terminal_accounting_pending') is True
      and raw.get('runtime_qualified') is False and raw.get('scientific_acceptance') is False,'raw evidence is not accepted')
    account,observation_copy=_terminal(accounting_pin,r,t,q)
    e=raw['phase_evidence'];m.require(e['schema']=='r203_ABI_engine_raw_result_v1'
      and e['status']=='RAW_ABI_STAGE_FACTS_NOT_ACCEPTED' and len(e['subjects'])==9,'actual exact engine raw shape')
    f=e['founder_observation'];fv=resolve(f['pin'],observation_copy)
    m.require(fv==f['value'],'actual founder file matches retained raw object')
    founder(fv,r,t);guards=[]
    for i,row in enumerate(e['subjects']):
        case=CASES[i];m.require(row['case_id']==case and type(row['ordinal']) is int and row['ordinal']==i+1,'fixed case order')
        d=resolve(row['descriptor'],observation_copy);m.require(d['request']==raw['request'] and d['authority']==raw['authority']
          and d['case_id']==case and d['ordinal']==i+1,'actual case descriptor')
        g=traced_guard(copy_pin(row['owned_guard'],observation_copy),r,i>=4)
        m.require(g['maximum_combined_CPU_seconds']==q['owner_CPU_seconds'],'same absolute whole-stage CPU ceiling')
        data=_read_stream(row['stdout'],observation_copy);lines=[p for p in data.splitlines() if p.strip()]
        m.require(len(lines)==2 and _read_stream(row['stderr'],observation_copy)==b'','exact actual child frames, no silently dropped output')
        ready=m.strict_json(lines[0]);value=m.strict_json(lines[1])
        m.require(ready==row['ready_frame'] and value==row['raw_result']
          and ready['descriptor']==row['descriptor'] and ready['child']['pid']==g['owned_root']['pid']
          and ready['status']=='READY_BEFORE_REAL_NATIVE_TRANSITION_NOT_ACK','actual parsed source frame not a fake ACK')
        _native_subject(value,r,t,case,g)
        cleanup=row['post_cleanup']
        m.require(cleanup['before']==cleanup['after'] and set(cleanup['before'])=={'subreaper','fd_set','permit'}
          and type(cleanup['before']['subreaper']) is int and cleanup['before']['subreaper'] in (0,1)
          and str(r['permit_fd']) in cleanup['before']['fd_set'],'actual complete FD/permit/subreaper restoration; guard proves complete reap')
        guards.append(row['owned_guard'])
    return dict(schema='r201_actual_native_ABI_suite_v1',status='CORE_R203_NATIVE_ABI_SUITE_AWAIT_INDEPENDENT_REVIEW',
      source_map_sha256=t['runtime_map_sha256'],native_library=t['parameters']['stage']['native_library'],
      native_abi=t['parameters']['stage']['native_abi'],node=r['node'],cases={k:True for k in CASE_NAMES},
      owned_guards=guards,accounting=accounting_pin,raw_stage_result=raw_pin,
      control_source_publication=t['control_publication'],control_map_sha256=t['control_map_sha256'],
      isolated_trace_predicate_proved=False,production_writer_or_analytic_qualification_earned=False)

def _pair_capture(pair,t,mode,r=None):
    o=guarded(pair,8)
    m.require(o.get('schema')=='r203_owned_stage_metadata_capture_v1'
      and o.get('status')=='CAPTURED_R203_ACTUAL_NATIVE_STAGE_METADATA_NOT_ADMISSION'
      and o.get('mode')==mode,'actual native role capture')
    program(o['controller_source'],t,'peer/observation_capture.py')
    _same(o,t,('purpose','nonce','stage','node'))
    for k in ('scope','ledger','quote','control_publication','control_map_sha256','runtime_publication','runtime_map_sha256'):
        m.require(o[k]==t[k],'capture exact '+k)
    if r is not None:m.require(o['job_id']==r['job_id'],'actual owned job only')
    return o

def _clock(reply):
    m.require(reply.get('returncode')==0 and reply.get('stderr')=='','native clock success')
    parts=reply['stdout'].strip().split('|')
    m.require(len(parts)==4 and parts[2] in ('+0000','+00:00') and parts[3]=='UTC','native UTC clock')
    dt=datetime.datetime.fromisoformat(parts[0].replace('Z','+00:00'))
    m.require(dt.tzinfo is not None and int(dt.timestamp())==int(parts[1]),'native exact epoch')
    return float(parts[1])

def validate_admission(t,q,check_current=True):
    a=m.linked(t['admission'])
    m.require(a.get('schema')=='r203_control_stage_admission_v1' and a.get('status')=='ADMITTED_R203_ONE_DIRECT_SLURM_STAGE','actual admission')
    g=m.linked(a['actual_accept_guard']);candidate=m.strict_json(g['stdout']);_guard_value(g,candidate,5)
    m.require(dict(candidate,status=a['status'],actual_accept_guard=a['actual_accept_guard'])==a
      and candidate.get('status')=='CANDIDATE_R203_CONTROL_STAGE_ADMISSION_AWAIT_H5','real H5 promotion')
    _same(a,t,('purpose','nonce','stage','node','control_publication','control_map_sha256','runtime_publication','runtime_map_sha256','scope','ledger','quote'))
    m.require(a['parameters_sha256']==m.digest(t['parameters']) and a['output_root']==t['output_root']
      and type(a['maximum_jobs']) is int and a['maximum_jobs']==1
      and type(a['optimizer_invocations']) is type(a['new_posterior_fits']) is int
      and a['optimizer_invocations']==a['new_posterior_fits']==0
      and t['issued_epoch']<=a['issued_epoch']<a['expires_epoch']<=t['expires_epoch'],'single fixed admission')
    if check_current:m.require(a['issued_epoch']<=time.time()<a['expires_epoch'],'actual admission live')
    review=m.linked(a['independent_review']);program(review['independent_program'],t)
    core={k:v for k,v in a.items() if k not in {'independent_review','actual_accept_guard','status','issued_epoch','command_pid','command_birth_ticks'}}
    m.require(review.get('status')=='PASS_REVIEWED_R203_CONTROL_STAGE_ADMISSION'
      and review.get('admission_core_sha256')==m.digest(core),'independent acyclic admission core')
    return admission_evidence(a,t,q)

def _terminal(accounting_pin,r,t,q):
    a=m.linked(accounting_pin)
    m.require(a.get('schema')=='r203_actual_terminal_control_stage_accounting_v1'
      and a.get('status')=='CAPTURED_TERMINAL_R203_PRIMARY_STAGE_ACCOUNTING'
      and a.get('terminal') is True and a.get('complete') is True and a.get('primary_charge_counted_once') is True
      and a.get('job_id')==r['job_id'],'actual terminal account')
    o=_pair_capture(a['native_capture'],t,'TERMINAL',r);reply=_native_rows(o,'accounting')
    m.require(reply['stderr']=='','native sacct complete success')
    lines=[v for v in reply['stdout'].splitlines() if v.strip()];m.require(len(lines)==1,'one allocation row')
    f=lines[0].split('|')
    if f[-1]=='':f.pop()
    m.require(len(f)==14,'exact terminal allocation fields')
    jid,name,state,user,uid,cpus,elapsed,allocated,rss,node,start,end,exitcode,total=f
    p=m.linked(t['parameters']['common']['physical_profile'])
    m.require(jid==r['job_id'] and name==p['job_name'] and state=='COMPLETED' and uid==str(r['uid'])
      and node==r['node'] and exitcode=='0:0' and re.fullmatch('[1-9][0-9]*',cpus)
      and re.fullmatch('[0-9]+',elapsed) and re.fullmatch('[0-9]+',allocated),'actual successful terminal owned job')
    for stamp in (start,end):
        m.require(re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:?\d\d)',stamp),'explicit UTC terminal accounting clock')
    begin=datetime.datetime.fromisoformat(start.replace('Z','+00:00')).timestamp()
    finish=datetime.datetime.fromisoformat(end.replace('Z','+00:00')).timestamp()
    measured=_slurm_CPU(total);wall=int(elapsed)
    m.require(begin<=finish<=o['completed_epoch'] and abs((finish-begin)-wall)<=1
      and int(allocated)==int(cpus)*wall,'actual allocation wall accounting')
    for key in ('owner_whole_CPU_seconds','whole_CPU_seconds','whole_wall_seconds'):m.finite(a[key],key)
    m.require(a['whole_CPU_seconds']==max(measured,a['owner_whole_CPU_seconds']) and a['whole_wall_seconds']==wall
      and 0<=a['owner_whole_CPU_seconds']<=q['owner_CPU_seconds']
      and a['owner_whole_CPU_seconds']<=measured+1.0
      and max(measured,a['owner_whole_CPU_seconds'])<=q['compute_CPU_reservation'] and wall<=q['whole_wall_seconds'],'one native primary charge, whole bounds')
    complete_inventory(r,t,q,o)
    return a,o

def _native_rows(o,name):
    rows=o['raw'];m.require(type(rows) is list,'actual native reply list')
    if name=='clocks':return [v for v in rows if v['argv']==['env','TZ=UTC','date','--utc','+%Y-%m-%dT%H:%M:%SZ|%s|%z|%Z']]
    if name=='node':out=[v for v in rows if v['argv'][:3]==['scontrol','show','node']]
    elif name=='forecast':out=[v for v in rows if Path(v['argv'][0]).name=='sbatch' and '--test-only' in v['argv']]
    elif name=='accounting':out=[v for v in rows if 'sacct' in v['argv']]
    elif name=='job':out=[v for v in rows if v['argv'][:3]==['scontrol','show','job']]
    else:raise ValueError('closed native reply selector')
    m.require(len(out)==1,'exact one native '+name)
    v=out[0];m.closed(v,{'argv','returncode','stdout','stderr'},'closed actual native reply')
    m.require(v['returncode']==0,'actual native command succeeded')
    return v

def _job_observation(o,r):
    v=_native_rows(o,'job');m.require(v['argv']==['scontrol','show','job',r['job_id'],'--oneliner'],'only exact own job')
    fields=dict(re.findall(r'(?:^|\s)([A-Za-z][A-Za-z0-9_]*)=([^\s]+)',v['stdout']))
    m.require(fields.get('JobId')==r['job_id'] and fields.get('JobState')=='RUNNING'
      and fields.get('NodeList')==r['node'] and fields.get('UserId','').endswith('('+str(r['uid'])+')'),'actual own running allocation')
    return fields

def copy_pin(pin,o=None):
    m.descriptor(pin)
    if o is not None:
        rows=[v for v in o['records'] if v['remote_path']==pin['path']]
        m.require(len(rows)<=1,'unique canonical captured copy')
        if rows:
            row=rows[0];m.require(row['sha256']==pin['sha256']==row['local_copy']['sha256'],'exact actual copied proof')
            return row['local_copy']
    return pin

def _slurm_CPU(text):
    m.require(type(text) is str and re.fullmatch(r'(?:\d+-)?\d+:\d\d:\d\d(?:\.\d+)?',text),'typed exact terminal TotalCPU')
    days,clock=(text.split('-',1) if '-' in text else ('0',text))
    hours,minutes,seconds=clock.split(':')
    m.require(int(minutes)<60 and 0<=float(seconds)<60,'terminal CPU clock fields')
    return int(days)*86400+int(hours)*3600+int(minutes)*60+float(seconds)


def raw_stage(raw_pin,accounting_pin,stage):
    raw=m.linked(raw_pin);r,t,q=request(raw['request'],False)
    m.require(raw.get('schema')=='r203_owned_control_raw_stage_result_v1'
      and raw.get('status')=='RAW_R203_CONTROL_STAGE_NOT_ACCEPTED_AWAIT_TERMINAL_ACCOUNTING'
      and r['stage']==stage and raw.get('terminal_accounting_pending') is True
      and raw.get('runtime_qualified') is False and raw.get('scientific_acceptance') is False,'actual raw unaccepted stage')
    _same(raw,r);m.require(raw['template']==r['template'] and raw['owner']==r['owner'],'exact raw owner')
    for key in ('control_publication','runtime_publication','control_map_sha256','runtime_map_sha256'):
        m.require(raw[key]==t[key],'raw '+key)
    a,o=_terminal(accounting_pin,r,t,q)
    claim=resolve(raw['stage_claim'],o);auth=resolve(raw['authority'],o)
    m.require(claim['owner']==r['owner'] and claim['request']==raw['request']
      and claim['authority']==raw['authority'] and claim['maximum_owner_calls']==1
      and claim['owner_started_epoch']==raw['started_epoch']
      and claim['stage_deadline_epoch']==min(auth['expires_epoch'],raw['started_epoch']+q['owner_wall_seconds'])
      and raw['started_epoch']<=claim['stage_started_epoch']<=raw['ended_epoch']<=claim['stage_deadline_epoch'],'actual one full-stage clock, no per-subject reset')
    usage=raw['usage']
    keys=('SELF_user_seconds','SELF_system_seconds','CHILDREN_user_seconds','CHILDREN_system_seconds')
    for key in keys:m.finite(usage[key],key);m.require(usage[key]>=0,'nonnegative whole owner usage')
    total=sum(usage[k] for k in keys)
    m.require(usage['inclusive_CPU_seconds']==total==a['owner_whole_CPU_seconds']
      and usage['no_sum_of_cumulative_trace_receipts'] is True and total<=q['owner_CPU_seconds'],'whole SELF plus all waited children counted once')
    return raw,r,t,q,a,o

def _build_facts(raw_pin,accounting_pin):
    raw,r,t,q,a,o=raw_stage(raw_pin,accounting_pin,'OWNED_NATIVE_BUILD');e=raw['phase_evidence'];p=t['parameters']['stage']
    m.require(e.get('schema')=='r203_raw_native_build_evidence_v1' and e['source_map_sha256']==t['runtime_map_sha256']
      and e['optimizer_invocations']==0 and type(e['optimizer_invocations']) is int
      and e['scientific_target_data_read'] is False,'actual no-target build evidence')
    flags=['-std=c11','-O2','-fPIC','-fvisibility=hidden','-Wall','-Wextra','-Werror','-shared']
    # The immutable renderer is source metadata; compare its declared fixed FLAGS.
    runtime_freeze=m.linked(BASE['runtime_freeze'])
    render_source=m.source_bytes(runtime_freeze['source_pins']['native_python/build_contract.py']).decode('utf-8')
    import ast
    assignments=[n for n in ast.parse(render_source).body if isinstance(n,ast.Assign)
      and any(isinstance(v,ast.Name) and v.id=='FLAGS' for v in n.targets)]
    m.require(len(assignments)==1,'one immutable compiler FLAGS source')
    flags=ast.literal_eval(assignments[0].value)
    expected=[p['compiler']['path'],*flags,'-o',p['output_library'],p['source']['path'],'-lm']
    m.require(e['compiler_argv']==expected and e['output_library']['path']==p['output_library']
      and e['output_identity']['path']==p['output_library'] and e['output_identity']['uid']==r['uid']
      and 0<e['output_bytes']<=16*1024**2 and e['output_identity']['inode']>0,'actual same canonical compiler output, no relocation')
    g=traced_guard(copy_pin(e['build_guard'],o),r,False)
    m.require(g['maximum_combined_CPU_seconds']==q['owner_CPU_seconds'],'actual compiler under same full-stage ceiling')
    events=[row for row in g['events'] if row.get('event')=='EXEC']
    m.require(any(row['pid']==g['owned_root']['pid'] and row['path']==p['compiler']['path'] and row['sha256']==p['compiler']['sha256'] for row in events),'actual root compiler exec source hash')
    tool=resolve(e['toolchain_closure'],o)
    m.require(1<=len(events)<=p['maximum_compiler_execs']
      and e['dependencies']==tool['native_dependencies'],'bounded compiler helpers and exact dependencies')
    for row in events:
        m.require(tool['exec_allowlist'].get(row['path'])==row['sha256'],'each actual compiler/helper exec hash allowed')
    m.require(len(e['dependencies']) in range(1,65),'old-compatible exact native dependencies')
    for d in e['dependencies']:
        m.closed(d,{'path','sha256','bytes'},'native dependency');m.descriptor({k:d[k] for k in ('path','sha256')});m.integer(d['bytes'],'native dependency size',1,64*1024**2)
    m.require(e['build_guard']==raw['owned_guards'][0] and len(raw['owned_guards'])==1,'one owned compiler trace')
    return raw,r,t,q,a,o,e

def raw_build_review(raw_pin,accounting_pin,output):
    admin_before_records(5);raw,r,t,q,a,o,e=_build_facts(raw_pin,accounting_pin)
    return m.write_new(output,dict(schema='r203_independent_raw_build_review_v1',
      status='PASS_REVIEWED_R203_RAW_OWNED_NATIVE_BUILD',raw_stage_result=raw_pin,accounting=accounting_pin,
      output_library=e['output_library'],compiler_argv=e['compiler_argv'],dependencies=e['dependencies'],
      independent_program=m.pin_file(__file__),runtime_qualified=False,observed_epoch=time.time()))

def readonly_facts(raw_pin,accounting_pin):
    raw,r,t,q,a,o=raw_stage(raw_pin,accounting_pin,'READONLY_DEPLOYMENT');e=raw['phase_evidence'];p=t['parameters']['stage']
    m.require(e['schema']=='r203_raw_readonly_deployment_evidence_v1' and e['source_map_sha256']==t['runtime_map_sha256']
      and e['optimizer_invocations']==0 and e['scientific_target_data_read'] is False,'raw same-path readonly observation')
    m.require(e['build_acceptance']==p['build_acceptance'] and e['native_build_manifest']==p['native_build_manifest']
      and e['native_library']==p['native_library'] and e['native_abi']==p['native_abi']
      and e['baseline_files']==p['baseline_files'],'unchanged exact accepted artifact and baseline')
    files={row['path']:row for row in e['files']};mounts={row['path']:row for row in e['readonly_files']}
    expected=list(t['control_sources'].values())+list(t['runtime_sources'].values())+p['baseline_files']+[p['native_library'],p['native_abi']]
    for pin in expected:
        row=files[pin['path']];mount=mounts[pin['path']]
        m.require(row['sha256']==pin['sha256'] and row['bytes']>0 and row['inode']>0
          and 'ro' in mount['mount_options'] and 'ro' in mount['super_options'],'actual source and most-specific backing RO mount')
    canonical=e['canonical_metadata_files'];expected_meta={v['path']:v['sha256'] for v in p['canonical_metadata_inputs']}
    m.require({v['path']:v['sha256'] for v in canonical}==expected_meta and all(v['bytes']>0 for v in canonical),'actual same bytes canonical namespace')
    m.require(len(raw['owned_guards'])==1,'one actual namespace observer')
    g=traced_guard(copy_pin(raw['owned_guards'][0],o),r,False)
    stdout=m.strict_json(_read_stream(e['stdout'],o));embedded={k:v for k,v in e.items() if k not in {'owned_guards','stdout','stderr','terminal_accounting_pending'}}
    m.require(stdout==embedded and _read_stream(e['stderr'],o)==b'','independent raw child stdout reconstruction')
    return raw,r,t,q,a,o,e

def bound_result_review(kind,result_pin,accounting_pin,output):
    admin_before_records(5);v=m.linked(result_pin)
    m.require(kind in {'BUILD','DEPLOYMENT','FACILITY'} and v['accounting']==accounting_pin,'closed compatible bound result')
    if kind=='BUILD':
        raw,r,t,q,a,o,e=_build_facts(v['raw_stage_result'],accounting_pin)
        manifest=m.linked(v['native_build_manifest'])
        m.require(v['native_library']==e['output_library']==manifest['output_library']
          and manifest['argv']==e['compiler_argv'] and manifest['build_accounting']==accounting_pin
          and manifest['build_guard']==e['build_guard'] and manifest['dependencies']==e['dependencies'],'compatible manifest independently bound to actual build')
        rr=m.linked(manifest['build_source_review'])
        m.require(rr['status']=='PASS_REVIEWED_R203_RAW_OWNED_NATIVE_BUILD'
          and rr['raw_stage_result']==v['raw_stage_result'] and rr['accounting']==accounting_pin,'actual raw build review')
        status='PASS_REVIEWED_R201_NATIVE_BUILD'
    elif kind=='FACILITY':
        raw,r,t,q,a,o,e=facility_facts(v['raw_stage_result'],accounting_pin)
        m.require(v['same_path_facility_route_observed'] is True and v['canonical_output_library']==e['canonical_output_library'],'actual same-path facility bound result')
        status='PASS_REVIEWED_R203_SAME_PATH_FACILITY_ROUTE'
    else:
        raw,r,t,q,a,o,e=readonly_facts(v['raw_stage_result'],accounting_pin)
        ns=m.linked(v['canonical_metadata_namespace'])
        m.require(ns['status']=='QUALIFIED_CANONICAL_METADATA_NAMESPACE' and ns['source_publication']==t['runtime_publication']
          and ns['same_bytes_without_old_JSON_rewrite'] is True
          and ns['canonical_metadata_files']==e['canonical_metadata_files']
          and v['read_only_backing_verified'] is True,'actual independently checked canonical namespace')
        status='PASS_REVIEWED_R201_READONLY_NAMESPACE'
    m.require(v['job_id']==r['job_id'] and v['node']==r['node'] and v['source_map_sha256']==t['runtime_map_sha256']
      and type(v['optimizer_invocations']) is int and v['optimizer_invocations']==0
      and v['scientific_target_data_read'] is False,'applicable old-compatible result')
    return m.write_new(output,dict(schema='r203_independent_compatible_stage_review_v1',status=status,
      result=result_pin,accounting=accounting_pin,raw_stage_result=v['raw_stage_result'],
      control_source_publication=t['control_publication'],control_map_sha256=t['control_map_sha256'],
      independent_program=m.pin_file(__file__),observed_epoch=time.time(),runtime_qualified=False))

def abi_suite_review(core_pin,output):
    admin_before_records(5);core=m.linked(core_pin)
    rebuilt=reconstruct_ABI(core['raw_stage_result'],core['accounting'])
    rebuilt['status']='ACCEPTED_NATIVE_ABI_SUITE_NOT_PRODUCTION'
    m.require({k:v for k,v in core.items() if k not in {'actual_suite_accept_guard','command_pid','command_birth_ticks'}}==rebuilt,'independent complete actual ABI reconstruction')
    g=m.linked(core['actual_suite_accept_guard']);c=m.strict_json(g['stdout']);_guard_value(g,c,5)
    m.require(c['status']=='CANDIDATE_R203_NATIVE_ABI_SUITE_AWAIT_H5'
      and c['raw_stage_result']==core['raw_stage_result'] and c['accounting']==core['accounting']
      and c['command_pid']==core['command_pid'] and c['command_birth_ticks']==core['command_birth_ticks'],'actual separate ABI H5 candidate')
    return m.write_new(output,dict(schema='r203_independent_native_ABI_suite_review_v1',
      status='PASS_REVIEWED_R201_NATIVE_ABI_SUITE',suite_core_sha256=m.digest(core),
      raw_stage_result=core['raw_stage_result'],accounting=core['accounting'],independent_program=m.pin_file(__file__),
      isolated_trace_predicate_proved=False,production_writer_or_analytic_qualification_earned=False,observed_epoch=time.time()))

def admission_evidence(a,t,q):
    o=_pair_capture(a['actual_resource_observation'],t,'ADMISSION');cal=_pair_capture(a['actual_calendar_assessment'],t,'ADMISSION')
    m.require(o==cal and o['job_id'] is o['template'] is o['request'] is None,'one genuine prejob observation')
    clocks=_native_rows(o,'clocks');m.require(len(clocks)==2,'two native UTC clocks')
    before=_clock(clocks[0]);after=_clock(clocks[1])
    m.require(before<=after<=a['issued_epoch'] and 0<=a['issued_epoch']-after<=90,'fresh at actual admission, no later clock reset')
    node=_native_rows(o,'node');m.require(node['argv']==['scontrol','show','node',t['node'],'--oneliner'] and node['stderr']=='','exact node')
    vals=dict(re.findall(r'(NodeName|RealMemory|AllocMem|CPUAlloc|CPUTot)=([^\s]+)',node['stdout']))
    for key in ('RealMemory','AllocMem','CPUAlloc','CPUTot'):m.require(vals.get(key,'').isdigit(),'actual typed scheduler '+key)
    profile=m.linked(t['parameters']['common']['physical_profile'])
    m.require(profile.get('schema')=='r203_control_physical_calendar_profile_v1'
      and profile.get('status')=='PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE'
      and profile['node']==t['node']==vals.get('NodeName') and profile['memory_MiB']==q['memory_MiB']
      and int(vals['RealMemory'])-int(vals['AllocMem'])>=q['memory_MiB']
      and int(vals['CPUTot'])-int(vals['CPUAlloc'])>=profile['requested_CPUs'],'native scheduler resources, no FreeMem substitution')
    pc=dict(profile);pc.pop('independent_review');pr=m.linked(profile['independent_review']);program(pr['independent_program'],t)
    m.require(pr.get('profile_core_sha256')==m.digest(pc)
      and pr.get('status')=='PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE','reviewed exact profile')
    expected=list(profile['rendered_sbatch_argv']);m.require(Path(expected[0]).name=='sbatch' and expected[-1]==profile['job_script']['path'],'fixed script argv')
    expected.insert(len(expected)-1,'--test-only');f=_native_rows(cal,'forecast')
    m.require(f['argv']==expected,'exact native test-only inserted before final script')
    starts=re.findall(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d)',f['stdout']+'\n'+f['stderr'])
    m.require(len(starts)==1 and 'start' in (f['stdout']+f['stderr']).lower()
      and t['node'] in f['stdout']+f['stderr'],'one explicit UTC/offset native forecast')
    start=datetime.datetime.fromisoformat(starts[0].replace('Z','+00:00')).timestamp()
    m.require(profile['not_before_epoch']<=start and a['issued_epoch']<=profile['latest_first_submit_epoch']<=a['issued_epoch']+255
      and start+q['whole_wall_seconds']+profile['reserve_seconds']<=profile['window_end_epoch'],'full priced stage and reserve fit window')
    b=m.linked(a['qualified_startup_baseline']);bc=dict(b);bc.pop('independent_review');br=m.linked(b['independent_review'])
    program(br['independent_program'],t)
    m.require(b.get('schema')=='r203_expected_startup_baseline_plan_v1'
      and b.get('status')=='PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN'
      and br.get('status')=='PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN'
      and br.get('baseline_core_sha256')==m.digest(bc),'reviewed expected startup plan, never earned native qualification')
    for key in ('node','control_publication','control_map_sha256','runtime_publication','runtime_map_sha256'):
        m.require(b[key]==t[key],'baseline '+key)
    for key in ('startup_python','traced_guard','source_and_baseline','physical_profile'):
        m.require(b[key]==t['parameters']['common'][key],'baseline fixed '+key)
    m.require(b['parameters_sha256']==m.digest(t['parameters']),'baseline parameters')
    facility=m.linked(b['facility_policy'])
    m.require(facility.get('schema')=='r203_same_path_facility_plan_v1'
      and facility.get('status')=='APPROVED_FACILITY_PLAN_REQUIRES_ACTUAL_OBSERVATION'
      and facility.get('node')==t['node'] and facility.get('controller_mounts_or_privilege_operations') is False
      and facility.get('canonical_output_path_preserved') is True,'explicit facility route, no assumed mount privilege')
    clean_launch_contract(facility['native_clean_launch_contract'],t)
    return a

def prospective(pin):
    v=m.linked(pin);m.closed(v,{'schema','status','template'},'prospective metadata core only')
    m.require(v['schema']=='r203_prospective_control_stage_v1'
      and v['status']=='PROSPECTIVE_SOURCE_METADATA_NOT_A_JOB_OR_AUTHORITY','no preview qualification transfer')
    t=v['template']
    m.require(t['admission'] is None and t['bootstrap_authority'] is None,'no invented future admission/bootstrap')
    return _template_value(t,True,False)

def _source_publications(core):
    pub=m.linked(core['control_publication']);rp=m.linked(core['runtime_publication'])
    m.require(pub.get('schema')=='r203_control_source_publication_v1' and pub.get('status')=='PASS_PUBLISHED_R203_CONTROL_SOURCE_PREPARATION'
      and pub['commit']==pub['remote_readback'] and pub.get('runtime_admitted') is False
      and pub['control_map_sha256']==core['control_map_sha256']
      and core['runtime_publication']==BASE['runtime_publication'] and core['runtime_map_sha256']==BASE['runtime_map_sha256']
      and rp['files']==BASE['runtime_source_hashes'],'actual source publications only, no runtime transfer')
    return pub

def static_review(kind,core_pin,output,resource_constraints=None):
    admin_before_records(5);v=m.linked(core_pin)
    cat=m.strict_json(m.source_bytes(dict(path=str(ROOT/'SCHEMAS.json'),
      sha256=CATALOG_SHA)))
    # The exact schema pin is replaced from the frozen catalog during integration.
    entry={'QUOTE':'quote','BASELINE':'expected_startup_baseline','PROFILE':None}
    m.require(kind in entry and 'independent_review' not in v,'closed acyclic static review')
    if kind=='QUOTE':
        m.closed(v,set(cat['quote']['keys'])-{'independent_review'},'complete prospective quote core')
        m.require(v['schema']=='r203_control_stage_quote_v1' and v['status']=='REVIEWED_R203_PROSPECTIVE_COMPLETE_STAGE_QUOTE'
          and v['stage'] in STAGES,'stage-only quote')
        _source_publications(v)
        names={'startup','namespace','import','optimizer','certification','checkpoint','return','independent_peer','closure'}
        m.closed(v['components'],names,'all mandatory stage costs')
        channels=('compute_CPU_upper_seconds','administrative_CPU_upper_seconds','remote_unknown_CPU_reservation')
        totals=('compute_CPU_reservation','administrative_CPU_reservation','remote_unknown_CPU_reservation')
        for row in v['components'].values():
            m.closed(row,{'covered','CPU_upper_seconds','wall_upper_seconds',*channels},'complete disjoint component')
            m.require(row['covered'] is True,'every component explicitly covered')
            for key in (*channels,'CPU_upper_seconds','wall_upper_seconds'):m.integer(row[key],key,0)
            m.require(row['CPU_upper_seconds']==sum(row[k] for k in channels),'disjoint CPU channels')
        for channel,total in zip(channels,totals):
            m.require(v[total]==sum(row[channel] for row in v['components'].values()),'exact channel reservation')
        for key in ('whole_CPU_seconds','whole_wall_seconds','owner_CPU_seconds','child_CPU_seconds','owner_wall_seconds',
          'memory_MiB','reserved_filesystem_bytes','mandatory_headroom_bytes','return_proof_reservation_bytes',
          'proof_storage_reservation_bytes','transient_tree_reservation_bytes'):m.integer(v[key],key,1)
        m.require(v['whole_CPU_seconds']==sum(v[k] for k in totals)
          and v['whole_wall_seconds']==sum(row['wall_upper_seconds'] for row in v['components'].values())<=28800
          and v['components']['startup']['wall_upper_seconds']>=120 and v['components']['optimizer']['compute_CPU_upper_seconds']==0
          and v['child_CPU_seconds']<=v['owner_CPU_seconds']<=v['compute_CPU_reservation']
          and v['owner_wall_seconds']<=v['whole_wall_seconds']
          and v['return_proof_reservation_bytes']>=16*1024**2 and v['transient_tree_reservation_bytes']>=32*1024**2
          and v['administrative_CPU_reservation']>=192 and v['remote_unknown_CPU_reservation']>=64,'complete inclusive quote and finite once-only administrative route')
        field,status='quote_core_sha256','PASS_REVIEWED_R203_CONTROL_STAGE_QUOTE'
    elif kind=='BASELINE':
        m.closed(v,set(cat['expected_startup_baseline']['keys'])-{'independent_review'},'complete expected baseline core')
        m.require(v['schema']=='r203_expected_startup_baseline_plan_v1'
          and v['status']=='PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN','expected immutable plan only')
        _source_publications(v)
        for key in ('startup_python','traced_guard','physical_profile','facility_policy'):m.descriptor(v[key])
        m.require(v['traced_guard']['sha256']==BASE['original_tracer']['sha256'],'unchanged original tracer')
        m.closed(v['source_and_baseline'],{'baseline_files','dependency_inventory'},'fixed immutable baseline closure')
        for pin in v['source_and_baseline']['baseline_files']:m.descriptor(pin)
        plan=m.linked(v['facility_policy'])
        m.require(plan.get('schema')=='r203_same_path_facility_plan_v1'
          and plan.get('status')=='APPROVED_FACILITY_PLAN_REQUIRES_ACTUAL_OBSERVATION'
          and plan.get('controller_mounts_or_privilege_operations') is False
          and plan.get('canonical_output_path_preserved') is True and plan.get('node')==v['node'],'explicit approved facility route still needs actual observation')
        field,status='baseline_core_sha256','PASS_REVIEWED_R203_EXPECTED_STARTUP_BASELINE_PLAN'
    else:
        m.closed(v,set(POLICY['physical_profile']['keys'])-{'independent_review'},'complete physical/calendar profile')
        m.require(v['schema']==POLICY['physical_profile']['schema'] and v['status']==POLICY['physical_profile']['status']
          and re.fullmatch('node-[0-9]+',v['node']) and len(v['affinity'])==1
          and set(v['affinity'])<=set(v['online_thread_siblings']),'explicit selected physical core and siblings')
        for key in ('requested_CPUs','memory_MiB','mandatory_headroom_bytes'):m.integer(v[key],key,1)
        for key in ('not_before_epoch','latest_first_submit_epoch','window_end_epoch'):m.finite(v[key],key)
        m.integer(v['reserve_seconds'],'reserve',0)
        m.closed(resource_constraints,{'owner_wall_seconds','canonical_metadata_root','nonce'},'prospective exact native allocation constraints')
        profile_values(v,**resource_constraints)
        argv=native_argv(v['rendered_sbatch_argv'])
        m.require(v['requested_CPUs']>=len(v['online_thread_siblings']) and len(set(v['online_thread_siblings']))==len(v['online_thread_siblings'])
          and type(argv) is list and all(type(s) is str and '\0' not in s for s in argv)
          and Path(argv[0]).name=='sbatch' and argv[-1]==v['job_script']['path']
          and not any('--wrap' in s or '--array' in s or s=='--requeue' for s in argv)
          and v['not_before_epoch']<=v['latest_first_submit_epoch']<v['window_end_epoch'],'fixed direct script/calendar, no array/wrap/requeue')
        m.read_regular(v['job_script']['path'],limit=65536,expected_sha=v['job_script']['sha256'],expected_uid=os.getuid()).decode('ascii')
        field,status='profile_core_sha256','PASS_REVIEWED_R203_FIXED_CONTROL_PHYSICAL_CALENDAR_PROFILE'
    return m.write_new(output,dict(schema='r203_independent_static_control_plan_review_v1',status=status,
      **{field:m.digest(v)},resource_constraints_sha256=m.digest(resource_constraints) if kind=='PROFILE' else None,independent_program=m.pin_file(__file__),runtime_admitted=False,observed_epoch=time.time()))

def admission_review(preview_pin,core_pin,output):
    admin_before_records(5);t,q=prospective(preview_pin);core=m.linked(core_pin)
    cat=m.strict_json(m.source_bytes(dict(path=str(ROOT/'SCHEMAS.json'),sha256=CATALOG_SHA)))
    exclusions={'independent_review','actual_accept_guard','status','issued_epoch','command_pid','command_birth_ticks'}
    m.closed(core,set(cat['admission']['keys'])-exclusions,'acyclic actual admission logical core')
    a=dict(core,issued_epoch=time.time());admission_evidence(a,t,q)
    return m.write_new(output,dict(schema='r203_independent_control_admission_review_v1',
      status='PASS_REVIEWED_R203_CONTROL_STAGE_ADMISSION',admission_core_sha256=m.digest(core),
      independent_program=m.pin_file(__file__),observed_epoch=time.time(),runtime_admitted=False))



def complete_inventory(r,t,q,o):
    rows=[v for v in o['raw'] if v['argv'][:2]==['find',t['output_root']]]
    m.require(len(rows)==1,'one terminal exact owned namespace inventory')
    v=rows[0]
    m.require(v['argv']==['find',t['output_root'],'-mindepth','1','-maxdepth','1','-printf',r'%f|%y|%s|%D|%i|%U|%n\n']
      and v['returncode']==0 and v['stderr']=='','native bounded owned-file metadata inventory')
    physical=resolve(r['physical_witness'],o);reservation=resolve(physical['reservation'],o)
    slots={s['name']:s for s in reservation['slots']};ingress=set(POLICY['record_transport']['allowed_names'])
    aliases={s['final_alias']:s['name'] for s in slots.values() if s['final_alias'] is not None}
    found={};total=0;seeninodes=set()
    for line in v['stdout'].splitlines():
        parts=line.split('|');m.require(len(parts)==7,'exact native file-stat fields')
        name,kind,size,dev,ino,uid,links=parts
        m.require(name not in found and name in set(slots)|set(aliases)|ingress and kind=='f'
          and all(re.fullmatch('[0-9]+',x) for x in (size,dev,ino,uid,links)),'only fixed single-link regular owned proof names')
        row=dict(bytes=int(size),device=int(dev),inode=int(ino),uid=int(uid),links=int(links))
        m.require(row['uid']==r['uid'] and row['links']==1 and row['bytes']<=16*1024**2
          and (row['device'],row['inode']) not in seeninodes,'no hidden alias copies/links or per-file overflow')
        seeninodes.add((row['device'],row['inode']));found[name]=row;total+=row['bytes']
    for name,slot in slots.items():
        alias=slot['final_alias'];present=[v for v in (name,alias) if v is not None and v in found]
        m.require(len(present)==1,'every prepaid slot survives exactly once; no cleanup')
        row=found[present[0]]
        m.require((row['device'],row['inode'])==(slot['device'],slot['inode'])
          and row['bytes']<=slot['maximum_bytes'],'same prepaid inode/cap or granted sameinode NOREPLACE alias')
    meta=Path(t['parameters']['common']['canonical_metadata_root'])
    for suffix in ('.stdout','.stderr'):
        path=str(meta/('slurm_'+t['nonce']+suffix));rows=[row for row in o['records'] if row['remote_path']==path]
        m.require(len(rows)==1,'actual mandatory native job log returned')
        data=_read_stream(dict(path=path,sha256=rows[0]['sha256']),o);total+=len(data)
    m.require(ingress<=set(found) and found['RELEASE.ready']['bytes']==0 and total<=64*1024**2,'all ingress/logs/full retained return inventory within64MiB')
    return found

def facility_facts(raw_pin,accounting_pin):
    raw,r,t,q,a,o=raw_stage(raw_pin,accounting_pin,'FACILITY_PRECHECK');e=raw['phase_evidence']
    m.require(e['schema']=='r203_raw_facility_precheck_evidence_v1' and e['source_map_sha256']==t['runtime_map_sha256']
      and e['node']==r['node'] and e['canonical_output_library']==t['parameters']['stage']['output_library']
      and e['stop_reasons']==[] and e['same_path_facility_route_observed'] is True
      and e['controller_mounts_or_privilege_operations'] is False and e['accepted_deployment'] is False
      and e['optimizer_invocations']==0 and e['scientific_target_data_read'] is False,'actual same-path facility route; any STOP remains STOP')
    plan=resolve(e['facility_plan'],o);capability=resolve(plan['operator_capability_evidence'],o)
    m.require(capability.get('same_path_transition_observed') is True
      and capability.get('controller_mounts_or_privilege_operations') is False
      and capability.get('node')==r['node'] and capability.get('canonical_output_library')==e['canonical_output_library'],'actual separately evidenced facility capability, no invented privilege')
    guard=traced_guard(copy_pin(raw['owned_guards'][0],o),r,False)
    child=m.strict_json(_read_stream(e['stdout'],o));embedded={k:v for k,v in e.items() if k not in {'owned_guards','stdout','stderr','terminal_accounting_pending'}}
    m.require(len(raw['owned_guards'])==1 and child==embedded and _read_stream(e['stderr'],o)==b'','actual fixed observer raw stdout')
    return raw,r,t,q,a,o,e


def abi_probe(value,t):
    m.closed(value,{'native_library','native_abi','expected_receipt_bytes','actual_receipt_bytes','actual_export_names'},'actual native ABI probe')
    p=t['parameters']['stage'];abi=m.strict_json(m.source_bytes(m.linked(BASE['runtime_freeze'])['source_pins']['native_python/native_abi.json']))
    m.require(value['native_library']==p['native_library'] and value['native_abi']==p['native_abi']
      and type(value['expected_receipt_bytes']) is type(value['actual_receipt_bytes']) is int
      and value['expected_receipt_bytes']==value['actual_receipt_bytes']==8584
      and type(value['actual_export_names']) is list
      and len(value['actual_export_names'])==len(set(value['actual_export_names']))==7
      and set(value['actual_export_names'])==set(abi['symbols']),'actual native receipt ABI size/export observations, source-only checks do not substitute')


def clean_launch_facts(core,t=None):
    m.closed(core,{'schema','status','node','site','sbatch','bash','launcher','environment','submission_policy',
      'site_SPANK_policy','actual_evidence'},'actual native clean-launch core')
    m.require(core['schema']=='r203_native_clean_launch_contract_v1'
      and core['status']=='PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER'
      and core['site']=='hb.ucsc.edu' and re.fullmatch('node-[0-9]+',core['node'])
      and core['submission_policy']=='EXACT_REVIEWED_SBATCH_ARGV_ONE_EXPORT_NIL_NO_USER_ENV_NO_WRAP','fixed independently proved native start policy')
    for key in ('sbatch','bash','launcher'):m.descriptor(core[key])
    env=core['environment'];required={'OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','NUMEXPR_NUM_THREADS','VECLIB_MAXIMUM_THREADS','BLIS_NUM_THREADS','TZ'}
    m.require(required<=set(env)<=required|{'PATH','LANG','LC_ALL'}
      and all(env[k]=='1' for k in required-{'TZ'}) and env['TZ']=='UTC'
      and all(env.get(k,v)==v for k,v in (('PATH','/usr/bin:/bin'),('LANG','C'),('LC_ALL','C'))),'closed minimal native environment')
    policy=core['site_SPANK_policy'];m.closed(policy,{'allowed_environment_names'},'explicit actual site SPANK policy')
    names=policy['allowed_environment_names']
    m.require(type(names) is list and len(names)==len(set(names))<=128
      and all(type(n) is str and re.fullmatch('SPANK_[A-Z0-9_]+',n) for n in names),'explicit unique site-reviewed plugin names only')
    actual=guarded(core['actual_evidence'],8)
    keys={'schema','status','node','site','sbatch','bash','launcher','environment','submission_policy','site_SPANK_policy',
      'actual_probe_argv','first_exec_environment','first_exec_events','raw_native_observations',
      'command_source','source_review','command_pid','command_birth_ticks','observed_epoch'}
    m.closed(actual,keys,'actual site native collector result')
    m.require(actual['schema']=='r203_actual_native_clean_launch_evidence_v1'
      and actual['status']=='CAPTURED_ACTUAL_SITE_FIRST_EXEC_ENVIRONMENT_NOT_RUNTIME_QUALIFICATION','actual first-exec/site/NIL evidence only')
    for key in ('node','site','sbatch','bash','launcher','environment','submission_policy','site_SPANK_policy'):
        m.require(actual[key]==core[key],'actual clean-start binding '+key)
    m.finite(actual['observed_epoch'],'actual native start observation')
    m.require(actual['observed_epoch']<=time.time(),'no future first-exec evidence')
    review=m.linked(actual['source_review'])
    m.require(review.get('status')=='PASS_REVIEWED_R203_NATIVE_CLEAN_START_COLLECTOR_SOURCE'
      and review.get('source')==actual['command_source'],'exact independently reviewed actual collector, no expected-plan substitution')
    m.source_bytes(actual['command_source'])
    argv=native_argv(actual['actual_probe_argv'])
    m.require(type(argv) is list and all(type(s) is str and '\0' not in s for s in argv)
      and argv[0]==core['sbatch']['path'] and sum(v=='--export=NIL' for v in argv)==1
      and not any(v.startswith('--export') and v!='--export=NIL' or '--get-user-env' in v or '--wrap' in v for v in argv),'actual native NIL probe with no user environment alternatives')
    first=actual['first_exec_environment']
    m.require(type(first) is dict and all(type(k) is str and type(v) is str for k,v in first.items())
      and all(k in env or k=='SLURMD_NODENAME' or k.startswith('SLURM_') or k in names for k in first)
      and all(k not in first or first[k]==v for k,v in env.items())
      and re.fullmatch('[1-9][0-9]*',first.get('SLURM_JOB_ID','')) is not None and first.get('SLURMD_NODENAME')==core['node'],'actual first-exec environment, no loader/Python/bash controls')
    for key in ('first_exec_events','raw_native_observations'):
        m.require(type(actual[key]) is list and actual[key] and all(type(row) is dict and row for row in actual[key]),'actual nonempty '+key)
    m.require(len(actual['first_exec_events'])<=256 and len(actual['raw_native_observations'])<=64,'bounded actual native evidence')
    for row in actual['raw_native_observations']:
        m.closed(row,{'argv','returncode','stdout','stderr'},'actual native clean observation')
        m.require(type(row['argv']) is list and row['argv'] and all(type(x) is str for x in row['argv']) and type(row['returncode']) is int and row['returncode']==0 and type(row['stdout']) is str and type(row['stderr']) is str,'exact actual successful native reply bytes')
    if t is not None:
        m.require(core['node']==t['node'] and env==t['parameters']['common']['environment'],'actual current node/environment policy')
        profile=m.linked(t['parameters']['common']['physical_profile']);argv=native_argv(profile['rendered_sbatch_argv'])
        m.require(argv[0]==core['sbatch']['path'] and sum(v=='--export=NIL' for v in argv)==1
          and not any(v.startswith('--export') and v!='--export=NIL' or '--get-user-env' in v or '--wrap' in v for v in argv),'every current actual command obeys qualified native policy')
    return actual

def clean_launch_contract(pin,t):
    value=m.linked(pin);core=dict(value);review=m.linked(core.pop('independent_review'))
    actual=clean_launch_facts(core,t);program(review['independent_program'],t)
    m.require(review['status']=='PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER'
      and review['clean_launch_core_sha256']==m.digest(core),'acyclic independently reviewed real clean launch')
    for key in ('issued_epoch','expires_epoch'):m.finite(review[key],key)
    m.require(actual['observed_epoch']<=review['issued_epoch']<=t['issued_epoch']
      and t['expires_epoch']<=review['expires_epoch']<=review['issued_epoch']+86400,'original fixed site qualification validity covers whole stage')
    return value

def clean_launch_review(core_pin,expires_epoch,output):
    admin_before_records(5);core=m.linked(core_pin);actual=clean_launch_facts(core);now=time.time()
    m.finite(expires_epoch,'explicit site proof expiry')
    m.require(actual['observed_epoch']<=now<expires_epoch<=now+86400,'one finite original clean-launch proof interval')
    return m.write_new(output,dict(schema='r203_independent_actual_clean_launch_review_v1',
      status='PASS_REVIEWED_R203_NATIVE_CLEAN_LAUNCH_BEFORE_INTERPRETER',clean_launch_core_sha256=m.digest(core),
      independent_program=m.pin_file(__file__),actual_evidence=core['actual_evidence'],issued_epoch=now,expires_epoch=expires_epoch,runtime_qualification_earned=False))


def native_argv(argv):
    m.require(type(argv) is list and len(argv)>=4 and all(type(v) is str for v in argv)
      and Path(argv[0]).is_absolute() and Path(argv[0]).name=='sbatch','one absolute canonical native sbatch')
    valued={'partition','qos','nodes','ntasks','cpus-per-task','mem','time','nodelist','job-name','output','error','chdir','account',
      'reservation','hint','threads-per-core','ntasks-per-node','distribution','export'}
    flags={'parsable','no-requeue'};seen=set()
    for token in argv[1:-1]:
        key,sep,value=token.partition('=')
        m.require(key.startswith('--') and key[2:] not in seen,'one canonical option, no abbreviation/heterogeneous/extra scripts')
        name=key[2:];seen.add(name)
        m.require(name in flags and not sep or name in valued and sep=='=' and value and '\0' not in value and '\n' not in value,'closed native argv grammar')
        if name=='export':m.require(value=='NIL','exactly one NIL export, no fallback')
    m.require({'export','no-requeue'}<=seen and Path(argv[-1]).is_absolute(),'one fixed script and explicit no-requeue')
    return argv

def script_policy(t,template_path=None):
    import shlex,string
    c=t['parameters']['common'];profile=m.linked(c['physical_profile']);native_argv(profile['rendered_sbatch_argv'])
    script=profile['job_script'];raw=m.read_regular(script['path'],limit=65536,expected_sha=script['sha256'],expected_uid=os.getuid())
    lines=raw.decode('ascii').splitlines()
    letters=string.ascii_uppercase+string.ascii_lowercase+'_'
    loop='for r203_key in '+' '.join('$'+'{!'+letter+'@}' for letter in letters)+'; do'
    prefix=['#!/bin/bash -p','set -eu',loop,
      '  case "$r203_key" in SLURM_JOB_ID|SLURMD_NODENAME) ;; *) export -n "$r203_key" 2>/dev/null || :; unset "$r203_key" 2>/dev/null || : ;; esac','done']
    expected=prefix+['export '+key+'='+shlex.quote(value) for key,value in sorted(c['environment'].items())]
    tools=[path for path in c['exec_allowlist'] if Path(path).name=='sha256sum']
    m.require(len(tools)==1,'one fixed baseline native source-hash tool');tool=tools[0]
    for pin in (c['startup_python'],t['control_sources']['common/stage_owner.py']):
        expected.append('test "$('+shlex.quote(tool)+' '+shlex.quote(pin['path'])+')" = '+shlex.quote(pin['sha256']+'  '+pin['path']))
    m.require(len(lines)==len(expected)+1 and lines[:-1]==expected,'only exact reviewed cleanup/export/source-hash commands before fixed owner')
    command=shlex.split(lines[-1])
    m.require(len(command)==6 and command[:5]==['exec',c['startup_python']['path'],'-I','-B',t['control_sources']['common/stage_owner.py']['path']]
      and Path(command[-1]).is_absolute(),'fixed source owner PATH-only execution; no injected shell/science')
    if template_path is not None:m.require(command[-1]==template_path,'exact actual canonical template path, no SHA cycle')
    return True


def profile_values(profile,owner_wall_seconds,canonical_metadata_root,nonce):
    import math
    native_argv(profile['rendered_sbatch_argv'])
    m.integer(owner_wall_seconds,'whole original owner wall',1,28800)
    m.integer(profile['requested_CPUs'],'actual requested CPUs',1)
    m.integer(profile['memory_MiB'],'actual requested MiB',1)
    m.require(re.fullmatch('[0-9a-f]{32}',nonce),'one actual stage nonce')
    root=m.absolute(canonical_metadata_root)
    opts={v.partition('=')[0]:v.partition('=')[2] for v in profile['rendered_sbatch_argv'][1:-1]}
    required={'--nodes':'1','--ntasks':'1','--cpus-per-task':str(profile['requested_CPUs']),
      '--mem':str(profile['memory_MiB'])+'M','--nodelist':profile['node'],'--job-name':profile['job_name'],
      '--time':str(math.ceil(owner_wall_seconds/60)),'--chdir':str(root),
      '--output':str(root/('slurm_'+nonce+'.stdout')),'--error':str(root/('slurm_'+nonce+'.stderr'))}
    m.require(all(opts.get(key)==value for key,value in required.items()),'literal native allocation/log/chdir/wall values equal complete reviewed plan')
    return True

def _administrative_module():
    path=ROOT/'peer/admin_context.py'
    raw=m.read_regular(path,limit=128*1024,expected_sha='a877ebc7ae8a183b17eddaf1a7f28e4ea07df79c6c7e3f932251af612fc3a6ea')
    sp=importlib.util.spec_from_file_location('_r203_independent_admin_grant',path)
    x=importlib.util.module_from_spec(sp);exec(compile(raw,str(path),'exec'),x.__dict__)
    return x

def main():
    admin_before_records(5);m.require(len(sys.argv)==3,'exact peer operator manifest path and SHA')
    manifest=m.linked(dict(path=sys.argv[1],sha256=sys.argv[2]))
    m.closed(manifest,{'schema','status','administrative_grant','operation','inputs'},'one independent peer operation')
    m.require(manifest['schema']=='r203_independent_peer_operator_manifest_v1'
      and manifest['status']=='ROOT_AUTHORIZED_R203_ONE_INDEPENDENT_METADATA_REVIEW','no runtime authority from operator manifest')
    op=manifest['operation'];inputs=manifest['inputs']
    operations={'SOURCE_PHYSICAL':(source_physical,{}),'OWNER_RELEASE':(owner_release,{}),
      'RAW_BUILD_REVIEW':(raw_build_review,{}),'BOUND_BUILD_REVIEW':(bound_result_review,{'kind':'BUILD'}),
      'BOUND_DEPLOYMENT_REVIEW':(bound_result_review,{'kind':'DEPLOYMENT'}),
      'FACILITY_REVIEW':(bound_result_review,{'kind':'FACILITY'}),'ABI_SUITE_REVIEW':(abi_suite_review,{}),'REVIEW_QUOTE':(static_review,{'kind':'QUOTE'}),
      'REVIEW_BASELINE':(static_review,{'kind':'BASELINE'}),'REVIEW_PROFILE':(static_review,{'kind':'PROFILE'}),
      'ADMISSION_REVIEW':(admission_review,{}),'CLEAN_LAUNCH_REVIEW':(clean_launch_review,{})}
    m.require(op in operations and type(inputs) is dict,'closed independent review operation')
    admin=_administrative_module();g,root=admin.grant(manifest['administrative_grant'],'PEER_'+op,m.pin_file(__file__),5)
    root.mkdir(mode=0o700);m.write_new(root/'INTENT.json',dict(manifest=m.pin_file(sys.argv[1]),operation=op,started_epoch=time.time()))
    fn,fixed=operations[op]
    import inspect
    m.require(set(inputs)==set(inspect.signature(fn).parameters)-{'output','output_path',*fixed},'exact independent review arguments')
    output_key='output_path' if 'output_path' in inspect.signature(fn).parameters else 'output'
    pin=fn(**inputs,**fixed,**{output_key:str(root/'REVIEW.json')})
    print(json.dumps(dict(status='COMPLETED_ONE_INDEPENDENT_METADATA_REVIEW_NOT_RUNTIME_AUTHORITY',review=pin,
      operation=op,command_pid=os.getpid(),command_birth_ticks=int(Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19])),sort_keys=True))

if __name__=='__main__':main()
