"""Administrative grants only; never imported by a scientific/control owner."""
import hashlib,importlib.util,os,re,resource,time
from pathlib import Path
P=Path(__file__).absolute().parent.parent/'common/metadata.py';raw=P.read_bytes()
if hashlib.sha256(raw).hexdigest()!='6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':raise ValueError('immutable metadata primitives')
sp=importlib.util.spec_from_file_location('_r203_administrative_metadata',P)
m=importlib.util.module_from_spec(sp);exec(compile(raw,str(P),'exec'),m.__dict__)
HOME_PARENT=Path('/home/jaguir26/.local/state/pricefm/r180_native_4503eef91eaa')
def kernel(cpu):
    m.require(os.sched_getaffinity(0)=={31} and resource.getrlimit(resource.RLIMIT_CPU)==(cpu,cpu)
      and os.getpid()==os.getsid(0)==os.getpgrp(),'actual original administrative H before supplied records')
    s=dict(v.split(':',1) for v in Path('/proc/self/status').read_text().splitlines() if ':' in v)
    m.require(s.get('NoNewPrivs','').strip()=='1' and s.get('Seccomp','').strip()=='2','actual original H kernel boundary')
def grant(pin,operation,program,cpu,remote=0):
    kernel(cpu);g=m.linked(pin)
    m.closed(g,{'schema','status','scope','ledger','operation','source_publication','program','output_root',
      'CPU_reservation','remote_unknown_CPU_reservation','maximum_calls','issued_epoch','expires_epoch'},'one immutable Root administrative delegation')
    m.require(g['schema']=='r203_root_delegated_administrative_action_v1'
      and g['status']=='ROOT_DELEGATED_ONE_R203_METADATA_ACTION'
      and g['operation']==operation and g['program']==program and g['CPU_reservation']==cpu
      and g['remote_unknown_CPU_reservation']==remote and type(g['maximum_calls']) is int and g['maximum_calls']==1,'fixed program/role/whole fee once')
    for key in ('CPU_reservation','remote_unknown_CPU_reservation'):m.integer(g[key],key,0)
    s=m.linked(g['scope']);l=m.linked(g['ledger']);previous=m.linked(s['previous_ledger'])
    pub=m.linked(g['source_publication'])
    m.require(pub.get('schema')=='r203_control_source_publication_v1' and pub.get('status')=='PASS_PUBLISHED_R203_CONTROL_SOURCE_PREPARATION'
      and pub.get('commit')==pub.get('remote_readback') and pub.get('runtime_admitted') is False
      and program['sha256'] in pub['files'].values(),'actual reviewed source publication, no runtime transfer')
    stage=s.get('status')=='ROOT_FUNDED_R203_CONTROL_STAGE_NO_TARGETS'
    prep=s.get('status')=='ROOT_FUNDED_R203_METADATA_PREPARATION_ONLY'
    m.require(stage or prep,'source448 and all old fees are not a future administrative action grant')
    m.require(type(s.get('new_administrative_CPU_reservation')) is int and s['new_administrative_CPU_reservation']>=cpu+remote,'fresh whole administrative funds')
    if stage:
        m.require(s.get('schema')=='r203_funded_control_stage_scope_v1' and type(s.get('compute_CPU_reservation')) is int,'actual typed funded stage scope')
        m.require(s['control_publication']==g['source_publication'] and s['compute_CPU_reservation']>0,'exact separately funded stage')
        q=m.linked(s['quote'])
        m.require(q['administrative_CPU_reservation']>=192 and q['remote_unknown_CPU_reservation']>=64
          and q['administrative_CPU_reservation']>=cpu and q['remote_unknown_CPU_reservation']>=remote,'complete finite fixed administrative route reservation')
    else:
        m.require(s.get('schema')=='r203_metadata_preparation_scope_v1'
          and s.get('source_publication')==g['source_publication'] and s.get('operation')==operation
          and s.get('maximum_calls')==1 and s.get('new_compute_CPU_reservation')==0
          and s.get('scientific_target_data_read') is False,'separate fresh static-plan metadata preparation only')
    m.require(set(l)==set(previous)|{'previous','created_epoch'} and l['previous']==s['previous_ledger'],'exact append keys and previous pointer')
    counters={'total_administrative_reservation','total_new_administrative_reservation','total_qualification_compute_reservation','total_new_qualification_compute_reservation'}
    for key,value in previous.items():
        if key in {'scopes','compute_roles','previous','created_epoch',*counters}:continue
        m.require(l[key]==value,'all previous fields/nulls unchanged')
    m.require(l['scopes'][:-1]==previous['scopes'] and len(l['scopes'])==len(previous['scopes'])+1
      and l['scopes'][-1]==dict(purpose=s['purpose'],scope=g['scope'],
        administrative_CPU_reservation=s['new_administrative_CPU_reservation'],
        compute_CPU_reservation=s.get('compute_CPU_reservation',0)),'one exact primary scope fee')
    for key in counters:
        delta=s['new_administrative_CPU_reservation'] if 'administrative' in key else s.get('compute_CPU_reservation',0)
        m.require(l[key]==previous[key]+delta,'complete ledger counters, no refund/reset')
    if not stage:m.require(l['compute_roles']==previous['compute_roles'],'metadata preparation adds no compute role')
    else:m.require(l['compute_roles'][:-1]==previous['compute_roles'] and len(l['compute_roles'])==len(previous['compute_roles'])+1
      and l['compute_roles'][-1]['scope']==g['scope'] and l['compute_roles'][-1]==dict(purpose=s['purpose'],stage=s['stage'],scope=g['scope'],compute_CPU_reservation=s['compute_CPU_reservation'],primary_actual_CPU=None),'one primary compute role retained')
    for key in ('issued_epoch','expires_epoch'):m.finite(s[key],key);m.finite(g[key],key)
    m.require(s['issued_epoch']<=g['issued_epoch']<=time.time()<g['expires_epoch']<=s['expires_epoch'],'one original finite grant clock')
    m.require(re.fullmatch('[0-9a-f]{32}',s['nonce']) and re.fullmatch('[A-Z0-9_]{1,80}',operation),'fixed namespace labels')
    root=m.physical(g['output_root'])
    m.require(root==HOME_PARENT/('R203_'+s['nonce']+'_'+operation),'one deterministic spent directory; a repeated grant cannot get another path')
    return g,root
