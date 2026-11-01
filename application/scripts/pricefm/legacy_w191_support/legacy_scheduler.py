"""Native UTC scheduler evidence and final admission for exact W191 node13.

No Python/R or payload runs remotely. Initial forecast is resource equivalent;
the final forecast is the exact staged sbatch argv with only --test-only added.
Raw Slurm replies remain unchanged. UTC derivation requires native env TZ=UTC,
integer date bounds and an actual healthy original H8 receipt.
"""
import argparse,datetime,hashlib,importlib.util,json,math,os,re,resource,shlex,signal,stat,subprocess,sys,time
from pathlib import Path
BASE=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers')
W=BASE/'worktrees/pricefm_r191_independent_watch_peer_20261031'
S=W/'application/scripts/pricefm/pricefm_hb'
H_SHA='7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1'
HELPER_SHA='8833cb4af5c8e5037ad6ed9e86dbed7955a8cbbe77d97c72dd7d74ca733f882b'
ROLE='ZERO_UPDATE_BRIDGE'
DATE_FORMAT='+%Y-%m-%dT%H:%M:%SZ|%s|%z|%Z'
SLURM_FORMAT='SLURM_TIME_FORMAT=%Y-%m-%dT%H:%M:%S%z'
ROLE_SECONDS=7200;RESERVE_SECONDS=3600
def require(ok,why):
 if not ok:raise ValueError(why)
def physical(p):
 p=Path(p).absolute();require(not any(x.is_symlink() for x in (p,*p.parents)),'physical source/metadata path');return p
def data(p):
 p=physical(p);require(p.suffix in {'.json','.py','.md'} and 'target_cache' not in p.parts,'source or JSON metadata only')
 fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 with os.fdopen(fd,'rb') as f:
  before=os.fstat(f.fileno())
  require(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid in {0,os.getuid()} and before.st_size<=32*2**20,'bounded regular single-link owned source/metadata')
  raw=f.read(32*2**20+1);after=os.fstat(f.fileno())
 ident=lambda x:(x.st_dev,x.st_ino,x.st_size,x.st_mtime_ns,x.st_ctime_ns,x.st_mode,x.st_uid)
 require(ident(before)==ident(after)==ident(p.stat()) and len(raw)==before.st_size,'stable complete bounded source/metadata')
 return raw
def pin(p):return dict(path=str(physical(p)),sha256=hashlib.sha256(data(p)).hexdigest())
def finite_float(text):
 value=float(text);require(math.isfinite(value),'nonfinite JSON float');return value
def strict(raw):
 def pairs(xs):
  out={}
  for k,v in xs:require(k not in out,'duplicate JSON key');out[k]=v
  return out
 return json.loads(raw,object_pairs_hook=pairs,parse_float=finite_float,parse_constant=lambda x:(_ for _ in ()).throw(ValueError('nonfinite JSON')))
def read(p):return strict(data(p))
def linked(x):
 require(type(x) is dict and set(x)=={'path','sha256'} and re.fullmatch('[0-9a-f]{64}',x['sha256']),'strict pin')
 require(pin(x['path'])==x,'pinned source/metadata changed');return read(x['path'])
def write(p,v):
 p=physical(p)
 with p.open('x') as f:json.dump(v,f,indent=2,sort_keys=True,allow_nan=False);f.write('\n')
def helper():
 p=S/'startup_helper.py';require(pin(p)['sha256']==HELPER_SHA,'unchanged helper before import')
 spec=importlib.util.spec_from_file_location('_legacy_scheduler_helper',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
h=helper()
def epoch(text):
 require(type(text) is str and re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:?\d\d)',text),'explicit UTC/offset timestamp')
 return datetime.datetime.fromisoformat(text.replace('Z','+00:00')).timestamp()
def healthy(g,cpu=8,wall=180):
 require(type(g.get('returncode')) is int and type(g.get('command_returncode')) is int and g['returncode']==g.get('command_returncode')==0
  and g.get('CPU_limit')==cpu and type(g.get('CPU_limit')) is int and g.get('cap_reason') is None
  and type(g.get('aggregate_CPU_seconds')) in (int,float) and math.isfinite(g['aggregate_CPU_seconds']) and 0<=g['aggregate_CPU_seconds']<cpu
  and type(g.get('complete_lifecycle_wall_seconds')) in (int,float) and math.isfinite(g['complete_lifecycle_wall_seconds']) and 0<=g['complete_lifecycle_wall_seconds']<=wall
  and g.get('guardian_forced_monitor_stop') is False
  and all(g.get(k) is True for k in ['all_owned_descendants_reaped','independent_guardian','kernel_escape_filter','orphan_subreaper','guardian_included_in_CPU','inherited_waited_history_included_once']),'healthy original whole-action guard')
def support(review_pin,pub_pin,source):
 r=linked(review_pin);p=linked(pub_pin)
 require(r.get('status')=='PASS_REVIEWED_LEGACY_NODE13_SUPPORT_SOURCE'
  and p.get('status')=='PASS_PUBLISHED_LEGACY_NODE13_SUPPORT_SOURCE'
  and p.get('independent_review')==review_pin and p.get('source_files')==r.get('source_files')
  and p.get('source_files',{}).get(Path(source['path']).name)==source['sha256']
  and re.fullmatch('[0-9a-f]{40}',p.get('commit','')) and p.get('remote_readback')==p['commit']
  and p.get('branch') not in {'main','master',''} and p.get('branch','').startswith('work/'),'published independently reviewed support source')
 require(pin(source['path'])==source,'current support bytes')
 return r,p
def parent_fields(parent):
 require(parent.get('schema')=='legacy_node13_scheduler_parent_v1' and parent.get('status')=='PROSPECTIVE_NATIVE_SCHEDULER_PARENT_NOT_JOB_AUTHORITY','new prospective descriptor')
 require(re.fullmatch('[A-Za-z0-9_]{1,64}',parent.get('purpose','')) and parent.get('node')=='node-13'
  and (parent.get('account'),parent.get('partition'),parent.get('qos'))==('128x24','128x24','normal'),'one exact legacy association/node')
 ns=parent['remote_namespace']
 require(re.fullmatch('/mnt/beegfs/home/jaguir26/pricefm_r182_LEGACY_[A-Za-z0-9_]{1,64}_[0-9a-f]{32}',ns),'unique closed remote namespace')
 start=epoch(parent['not_before_at']);expiry=epoch(parent['expires_at']);cutoff=epoch(parent['role_submit_cutoffs'][ROLE])
 require(parent['role_slot_seconds']==7200 and type(parent['role_slot_seconds']) is int
  and parent['final_reserve_seconds']==3600 and type(parent['final_reserve_seconds']) is int
  and parent['startup_budget_seconds']==300 and type(parent['startup_budget_seconds']) is int
  and start<cutoff<=expiry,'fixed complete calendar')
 phase=linked(parent['phase_scope'])
 require(phase['issued_epoch']<=start and expiry==phase['expires_epoch'] and cutoff==phase['fixed_latest_first_submit_epoch'],'parent cannot extend actual phase window or cutoff')
 return start,expiry,cutoff
def base_argv(p):
 return ['sbatch','--parsable','--export=NONE','--propagate=NONE','--mail-type=NONE','--account='+p['account'],
 '--partition='+p['partition'],'--qos='+p['qos'],'--nodelist=node-13','--nodes=1','--ntasks=1',
 '--cpus-per-task=1','--hint=nomultithread','--mem=8192M','--time=00:20:00','--no-requeue']
def expected_test_argv(parent,mode,packet=None):
 args=base_argv(parent)
 if mode=='initial':args+=['--wrap=:']
 else:
  require(mode=='final' and packet is not None and packet['role']==ROLE,'final exact packet')
  require(packet['remote_root']==parent['remote_namespace']+'/'+packet['scope_id'],'exact staged namespace')
  args+=['--job-name='+packet['scope_id'],'--output='+packet['remote_root']+'/slurm-%j.out',
   '--error='+packet['remote_root']+'/slurm-%j.err',packet['remote_root']+'/job.sbatch']
 return args[:1]+['--test-only']+args[1:]
def ssh_options(site):
 opts={'BatchMode':'yes','StrictHostKeyChecking':'yes','UpdateHostKeys':'no','CheckHostIP':'no','ControlMaster':'no','ControlPath':'none',
 'IdentitiesOnly':'yes','IdentityAgent':'none','ForwardAgent':'no','ClearAllForwardings':'yes','PreferredAuthentications':'publickey',
 'PasswordAuthentication':'no','KbdInteractiveAuthentication':'no','ConnectTimeout':'10','ConnectionAttempts':'1','UserKnownHostsFile':site['known_hosts_file']}
 return [v for k,x in opts.items() for v in ('-o',k+'='+x)]+['-i',site['ssh_identity_file']]
def native(site,argv):
 require(argv and argv[0] in {'env','test','squeue','scontrol'} and all(type(x) is str and '\x00' not in x for x in argv),'closed native argv')
 if argv[0]=='env':
  require((argv[:3]==['env','TZ=UTC','date']) or (argv[:4]==['env','TZ=UTC',SLURM_FORMAT,'sbatch']),'explicit UTC/Slurm-offset native only')
 r=subprocess.run(['/usr/bin/ssh','-T',*ssh_options(site),site['user']+'@'+site['host'],shlex.join(argv)],capture_output=True,text=True,preexec_fn=lambda:None)
 require(len(r.stdout.encode())+len(r.stderr.encode())<=2**20,'bounded native reply')
 return dict(argv=argv,returncode=r.returncode,stdout=r.stdout,stderr=r.stderr)
def raw_ok(raw,argv,rc=0):
 require(set(raw)=={'argv','returncode','stdout','stderr'} and raw['argv']==argv and type(raw['returncode']) is int and raw['returncode']==rc,'native command/exit provenance')
 return raw
def clock(raw):
 raw_ok(raw,['env','TZ=UTC','date','--utc',DATE_FORMAT]);require(raw['stderr']=='','UTC date stderr')
 parts=raw['stdout'].strip().split('|')
 require(len(parts)==4 and parts[2:]==['+0000','UTC'] and re.fullmatch('[0-9]+',parts[1]),'native explicit UTC date+offset')
 t=epoch(parts[0]);require(t==int(parts[1]),'native UTC civil/epoch equality');return t
def verify_candidate(c,now=None):
 now=time.time() if now is None else now
 require(c.get('schema')=='legacy_node13_native_scheduler_candidate_v1' and c.get('status')=='OBSERVED_NATIVE_LEGACY_NODE13_SCHEDULER_NOT_AUTHORITY','native observation candidate')
 scope=linked(c['observation_scope']);parent=linked(c['parent']);start,expiry,cutoff=parent_fields(parent)
 require(scope['parent']==c['parent'] and scope['mode']==c['mode'] and scope['source']==c['source']
  and scope['phase_scope']==parent['phase_scope'] and c['source']==pin(__file__),'exact native observation scope/source')
 phase=linked(scope['phase_scope'])
 require(phase['issued_epoch']<=scope['issued_epoch']<=c['started_epoch']<=c['observed_epoch']<=now<scope['expires_epoch']<=phase['expires_epoch']
  and scope['allocations']=={'local_originalH8':8,'remote_unknown8':8} and type(scope['maximum_calls']) is int and scope['maximum_calls']==1
  and c['purpose']==parent['purpose'] and c['node']=='node-13' and c['remote_namespace']==parent['remote_namespace']
  and c['known_jobs_registry']==parent['known_jobs_registry'],'prospectively priced exact one-shot current observation')
 support(scope['support_review'],scope['support_publication'],c['source'])
 ledger=linked(scope['funding_ledger'])
 if c['mode']=='initial':
  rows=[x for x in ledger['scopes'] if x.get('scope')==scope['phase_scope']]
  require(len(rows)==1 and rows[0]['administrative_CPU_reservation']==528 and rows[0]['compute_CPU_reservation']==0
   and phase['allocations']['fresh_capacity_and_admission32']==32
   and scope['funding_kind']=='PREPARATION_INITIAL_NATIVE16','prospective initial native16 within phase528')
 else:
  rows=[x for x in ledger['scopes'] if x.get('scope')==scope['runtime_scope']]
  runtime=linked(scope['runtime_scope'])
  require(len(rows)==1 and rows[0]['administrative_CPU_reservation']==300 and rows[0]['compute_CPU_reservation']==600
   and runtime['extra_setup_forecast_tail']['scheduler_evidence_CPU']==16
   and scope['funding_kind']=='RUNTIME_FINAL_NATIVE16','one completely funded final native16')
 packet=None
 if c['mode']=='final':
  packet=linked(c['packet']);cfg=linked(c['config']);g=linked(c['actual_stage_guard']);healthy(g,18,300)
  require(scope['packet']==c['packet'] and scope['config']==c['config'] and scope['actual_stage_guard']==c['actual_stage_guard']
   and cfg['scope']==scope['runtime_scope'] and cfg['remote_namespace']==parent['remote_namespace'] and cfg['known_jobs_registry']==parent['known_jobs_registry']
   and packet['role']==ROLE and g['stdout'] and strict(g['stdout'])['status']=='STAGED_NOT_SUBMITTED'
   and strict(g['stdout'])['scope_id']==packet['scope_id'],'actual current stage/config/packet before final forecast')
 raws={k:linked(v) for k,v in c['raw'].items()}
 before=clock(raws['clock_before']);after=clock(raws['clock_after'])
 require(before<=after and c['started_epoch']-5<=before and after<=c['observed_epoch']+5
  and after-before<=120,'bounded UTC native observation interval/clock skew')
 argv=expected_test_argv(parent,c['mode'],packet);test=raw_ok(raws['test_only'],['env','TZ=UTC',SLURM_FORMAT,*argv])
 combined=test['stdout']+'\n'+test['stderr']
 times=re.findall(r'\bto start at ([^\s,]+)',combined);nodes=re.findall(r'\bon nodes? (node-[0-9]{2})(?:\s|$)',combined)
 require(len(times)==1 and nodes==['node-13'],'one native predicted timestamp and exact node')
 text=times[0]
 predicted=epoch(text);basis='RAW_NATIVE_EXPLICIT_OFFSET_WITH_SLURM_TIME_FORMAT'
 require(predicted>=before,'reject stale prediction older than native integer before clock')
 queue=raw_ok(raws['queue'],['squeue','--noheader','--user','jaguir26','--format','%i'])
 require(queue['stdout'].strip()==queue['stderr']=='','no existing user queue before single-job admission')
 namespace=raw_ok(raws['namespace'],['test','-e',parent['remote_namespace']],1 if c['mode']=='initial' else 0)
 require(namespace['stdout']==namespace['stderr']=='','native namespace absence/presence')
 if c['mode']=='final':
  script=raw_ok(raws['script'],['test','-f',packet['remote_root']+'/job.sbatch'])
  require(script['stdout']==script['stderr']=='','actual staged script exists')
 raw_ok(raws['node'],['scontrol','show','node','node-13','--oneliner'])
 require('NodeName=node-13' in raws['node']['stdout'] and raws['node']['stderr']=='','native exact node facts retained')
 require(type(c['observed_epoch']) in (int,float) and math.isfinite(c['observed_epoch']) and 0<=now-c['observed_epoch']<=60,'fresh<=60 native evidence')
 effective=max(predicted,now)
 require(start<=now<cutoff and predicted<=cutoff and effective-now<=255
  and effective+ROLE_SECONDS+RESERVE_SECONDS<=expiry,'255 second horizon+45 envelope and complete fixed calendar')
 return dict(parent=c['parent'],purpose=parent['purpose'],node='node-13',remote_namespace=parent['remote_namespace'],
 known_jobs_registry=parent['known_jobs_registry'],observed_epoch=c['observed_epoch'],predicted_start_epoch=predicted,
 effective_start_epoch=effective,raw_predicted_start=text,derived_predicted_start_at=datetime.datetime.fromtimestamp(predicted,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
 prediction_UTC_basis=basis,not_before_epoch=start,expires_epoch=expiry,role_submit_cutoff_epoch=cutoff,mode=c['mode'],
 namespace_absent=c['mode']=='initial',packet=c.get('packet'),config=c.get('config'),actual_stage_guard=c.get('actual_stage_guard'))
def verify_root_admission(native_pin,now=None):
 now=time.time() if now is None else now;a=linked(native_pin)
 require(a.get('status')=='PASS_ACTUAL_GUARDED_LEGACY_NODE13_SCHEDULER_ADMISSION','actual ROOT native admission')
 c=a['candidate'];facts=verify_candidate(c,now);g=linked(a['actual_guard']);healthy(g)
 require(a['collector_source']==c['source'] and strict(g['stdout'])==c
  and g['session_id']==c['command_pid'] and g['leader_start_ticks']==c['command_birth_ticks']
  and c['observed_epoch']<=a['issued_epoch']<=now<a['expires_epoch']<=facts['expires_epoch'],'actual guard stdout/PID/birth and ROOT after observation')
 for k in ['parent','purpose','node','remote_namespace','known_jobs_registry','observed_epoch']:
  require(a[k]==facts[k],'exact ROOT native binding '+k)
 require(a['namespace_absent']==facts['namespace_absent'],'exact initial/final namespace state')
 return facts
def collect(scope_pin):
 fields=dict(x.split(':',1) for x in Path('/proc/self/status').read_text().splitlines() if ':' in x)
 require(os.getpid()==os.getsid(0)==os.getpgrp() and os.sched_getaffinity(0)=={31}
  and fields['NoNewPrivs'].strip()=='1' and fields['Seccomp'].strip()=='2' and resource.getrlimit(resource.RLIMIT_CPU)==(8,8),'unchanged original H8 collector context')
 s=linked(scope_pin);p=linked(s['parent']);parent_fields(p);phase=linked(s['phase_scope']);now=time.time()
 require(s.get('schema')=='legacy_node13_scheduler_observation_scope_v1' and s['source']==pin(__file__)
  and s['phase_scope']==p['phase_scope'] and phase['issued_epoch']<=s['issued_epoch']<=now<s['expires_epoch']<=phase['expires_epoch'],'fresh exact native source scope')
 support(s['support_review'],s['support_publication'],s['source'])
 require(s['allocations']=={'local_originalH8':8,'remote_unknown8':8} and type(s['maximum_calls']) is int and s['maximum_calls']==1,'funded one native observation')
 funding=linked(s['funding_ledger'])
 if s['mode']=='initial':
  rows=[x for x in funding['scopes'] if x.get('scope')==s['phase_scope']]
  require(len(rows)==1 and rows[0]['administrative_CPU_reservation']==528 and rows[0]['compute_CPU_reservation']==0
   and phase['allocations']['fresh_capacity_and_admission32']==32 and s['funding_kind']=='PREPARATION_INITIAL_NATIVE16','funded initial before network')
 else:
  require(s['mode']=='final','closed observation mode')
  rows=[x for x in funding['scopes'] if x.get('scope')==s['runtime_scope']]
  runtime=linked(s['runtime_scope'])
  require(len(rows)==1 and rows[0]['administrative_CPU_reservation']==300 and rows[0]['compute_CPU_reservation']==600
   and runtime['extra_setup_forecast_tail']['scheduler_evidence_CPU']==16 and s['funding_kind']=='RUNTIME_FINAL_NATIVE16','funded final before network')
 out=physical(s['output_root']);require(out.is_dir() and out.stat().st_uid==os.getuid() and out.stat().st_mode&0o077==0,'private existing native output')
 site=linked(s['site']);require((site['host'],site['user'],site['account'],site['partition'],site['qos'])==('hb.ucsc.edu','jaguir26','128x24','128x24','normal'),'exact trusted HB site')
 for key in ['known_hosts_file','ssh_identity_file']:require(physical(site[key]).is_file(),'physical enrolled SSH key/trust')
 write(out/'INTENT.json',dict(status='NATIVE_FORECAST_STARTED_NO_REPLAY',scope=scope_pin,issued_epoch=now))
 packet=linked(s['packet']) if s['mode']=='final' else None
 qs=[('clock_before',['env','TZ=UTC','date','--utc',DATE_FORMAT]),('queue',['squeue','--noheader','--user','jaguir26','--format','%i']),
 ('namespace',['test','-e',p['remote_namespace']]),('node',['scontrol','show','node','node-13','--oneliner'])]
 if packet:qs.append(('script',['test','-f',packet['remote_root']+'/job.sbatch']))
 qs += [('test_only',['env','TZ=UTC',SLURM_FORMAT,*expected_test_argv(p,s['mode'],packet)]),('clock_after',['env','TZ=UTC','date','--utc',DATE_FORMAT])]
 refs={}
 for label,args in qs:
  r=native(site,args);write(out/(label+'.json'),r);refs[label]=pin(out/(label+'.json'))
 c=dict(schema='legacy_node13_native_scheduler_candidate_v1',status='OBSERVED_NATIVE_LEGACY_NODE13_SCHEDULER_NOT_AUTHORITY',
 observation_scope=scope_pin,parent=s['parent'],purpose=p['purpose'],node='node-13',remote_namespace=p['remote_namespace'],
 known_jobs_registry=p['known_jobs_registry'],source=pin(__file__),mode=s['mode'],started_epoch=now,observed_epoch=time.time(),
 command_pid=os.getpid(),command_birth_ticks=h.process_birth_ticks(),raw=refs)
 if packet:c.update(packet=s['packet'],config=s['config'],actual_stage_guard=s['actual_stage_guard'])
 # Persist all raw evidence even when the eligibility decision fails.
 write(out/'CANDIDATE.json',c)
 try:
  facts=verify_candidate(c);write(out/'EVALUATION.json',dict(status='NATIVE_OBSERVATION_PLANNING_ELIGIBLE_AWAIT_ACTUAL_GUARD',facts=facts))
 except (ValueError,KeyError,TypeError) as exc:
  write(out/'EVALUATION.json',dict(status='NATIVE_OBSERVATION_INELIGIBLE_NO_GRANT',error=type(exc).__name__+': '+str(exc)))
 return c
def exec_driver(config_path,authority_pin,native_pin):
 facts=verify_root_admission(native_pin);cfg=read(config_path);auth=linked(authority_pin)
 require(facts['mode']=='final' and facts['config']==pin(config_path) and facts['actual_stage_guard']==auth['actual_stage_guard']
  and cfg['scope']==auth['scope'] and cfg['critical_driver']==auth['driver_source']
  and auth['config']==pin(config_path),'exact final native admission before original driver')
 packet=linked(facts['packet'])
 require(Path(facts['packet']['path']).parent==Path(cfg['registry'])/ROLE and packet['role']==ROLE,'exact current staged role')
 require(not (Path(cfg['registry'])/ROLE/'JOB.json').exists() and not (Path(cfg['registry'])/ROLE/'ROLE_FAILED_SPENT.json').exists(),'unsubmitted unspent role')
 driver=S/'numerical_critical_driver.py';require(pin(driver)==auth['driver_source'],'unchanged original W191 driver')
 require(resource.getrlimit(resource.RLIMIT_CPU)[1]==136,'original inherited hard136 permits bounded native children; soft8/SELF10 reservation includes wrapper')
 os.execv(sys.executable,[sys.executable,'-I','-B',str(driver),'--config',config_path,'--authority',authority_pin['path'],'--authority-sha256',authority_pin['sha256']])
def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('action',choices=['collect','exec-driver']);a.add_argument('--scope');a.add_argument('--scope-sha256');a.add_argument('--config');a.add_argument('--authority');a.add_argument('--authority-sha256');a.add_argument('--native');a.add_argument('--native-sha256');x=a.parse_args()
 if x.action=='collect':
  require(x.scope is not None and x.scope_sha256 is not None,'complete observation scope pin')
  print(json.dumps(collect(dict(path=x.scope,sha256=x.scope_sha256)),sort_keys=True,allow_nan=False))
 else:
  require(os.sched_getaffinity(0)=={31},'CPU31 driver metadata')
  signal.signal(signal.SIGXCPU,signal.SIG_DFL)
  resource.setrlimit(resource.RLIMIT_CPU,(8,136));resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.alarm(1200)
  exec_driver(x.config,dict(path=x.authority,sha256=x.authority_sha256),dict(path=x.native,sha256=x.native_sha256))
if __name__=='__main__':main()
