"""Prepare a bounded Jerez metadata observation; never a numerical launcher.

The existing Muscat-only r164/R157 authority is not reused on another host.
The remote program reads exact installed runtime files and redacted process
identities intersecting the candidate physical pair, without executing R.
"""
from __future__ import annotations

import json
import shlex

from .local_readiness import require, runtime_targets

REMOTE = r'''import hashlib,json,os,pathlib,resource,signal,socket,stat,time
resource.setrlimit(resource.RLIMIT_CPU,(8,8));signal.alarm(60)
assert os.sched_getaffinity(0)=={31}
started=time.monotonic();targets=__TARGETS__
rows=[];errors=[];total=0
for name,expected in sorted(targets.items()):
 p=pathlib.Path(name)
 try:
  assert p.is_absolute() and not any(q.is_symlink() for q in [p]+list(p.parents))
  before=p.stat();assert stat.S_ISREG(before.st_mode) and before.st_size<=512*1024**2
  total+=before.st_size;assert total<=1024**3
  h=hashlib.sha256()
  with p.open('rb') as f:
   for block in iter(lambda:f.read(1024**2),b''):h.update(block)
  after=p.stat();assert (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)==(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns)
  rows.append({'path':name,'sha256':h.hexdigest(),'expected_sha256':expected,'matches':h.hexdigest()==expected,'bytes':before.st_size})
 except Exception as e:errors.append({'path':name,'error_type':type(e).__name__,'error':str(e)})
mem={line.split(':',1)[0]:int(line.split()[1])*1024 for line in pathlib.Path('/proc/meminfo').read_text().splitlines() if line.startswith(('MemAvailable:','MemTotal:'))}
disk_root='/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm'
v=os.statvfs(disk_root);free=v.f_bavail*v.f_frsize
topology={}
for cpu in [30,31,62,63]:
 p=pathlib.Path('/sys/devices/system/cpu/cpu%d/topology/thread_siblings_list'%cpu)
 topology[str(cpu)]=p.read_text().strip() if p.exists() else None
intersect=[];proc_errors=[];seen=0
for proc in pathlib.Path('/proc').iterdir():
 if not proc.name.isdigit():continue
 try:
  if proc.stat().st_uid!=os.getuid():continue
  seen+=1;assert seen<=1024
  raw=(proc/'stat').read_text();f=raw[raw.rfind(')')+2:].split();pid=int(proc.name);birth=int(f[19])
  if f[0] in ['Z','X','x']:continue
  masks=[]
  for t in (proc/'task').iterdir():
   if t.name.isdigit():
    try:masks.append(sorted(os.sched_getaffinity(int(t.name))))
    except (FileNotFoundError,ProcessLookupError):pass
  if not any(set(x)&{30,62} for x in masks):continue
  cmd=(proc/'cmdline').read_bytes();exe=os.path.basename(os.readlink(str(proc/'exe'))) if cmd else ''
  argv=[x.decode(errors='replace') for x in cmd.split(b'\0') if x]
  numeric='python' in exe.lower() or exe in ['R','Rscript'] or any(x.endswith(('.py','.R','.r')) for x in argv)
  if not numeric:continue
  after=(proc/'stat').read_text();after=after[after.rfind(')')+2:].split();assert int(after[19])==birth
  intersect.append({'pid':pid,'start_ticks':birth,'uid':os.getuid(),'state':f[0],'cmdline_sha256':hashlib.sha256(cmd).hexdigest(),'affinities':masks,'pricefm_path_present':any('/pricefm/' in x for x in argv),'reviewed_or_allowed_for_science':False})
 except (FileNotFoundError,ProcessLookupError):pass
 except Exception as e:proc_errors.append({'pid':int(proc.name),'error_type':type(e).__name__})
u=resource.getrusage(resource.RUSAGE_SELF)
print(json.dumps({'schema':'r178_jerez_metadata_observation_v1','host':socket.gethostname(),'observed_epoch':time.time(),'affinity':sorted(os.sched_getaffinity(0)),'runtime_files':rows,'runtime_errors':errors,'runtime_total_bytes':total,'memory':mem,'disk_free_bytes':free,'topology':topology,'same_UID_numerical_intersections_pair30_62':intersect,'process_observation_errors':proc_errors,'all_process_arguments_redacted':True,'new_peer_allowances':[],'R_started':False,'numerical_admission':False,'source_or_runtime_changes':0,'signals':0,'SELF_CPU':u.ru_utime+u.ru_stime,'wall_seconds':time.monotonic()-started},sort_keys=True))
'''


def remote_program(runtime_binding):
    targets=runtime_targets(runtime_binding)
    require(all("\n" not in path for path in targets),"canonical single-line runtime paths required")
    return REMOTE.replace("__TARGETS__",repr(targets))


def ssh_argv(runtime_binding):
    command=shlex.join(['taskset','-c','31','nice','-n','19','ionice','-c','3','/usr/bin/python3','-B','-c',remote_program(runtime_binding)])
    return ['/usr/bin/ssh','-T','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','IdentitiesOnly=yes',
            '-o','ControlMaster=no','-o','ControlPath=none','-o','ForwardAgent=no','-o','ForwardX11=no',
            '-o','ClearAllForwardings=yes','-o','ConnectTimeout=15','-o','ConnectionAttempts=1',
            '-i','/home/jaguir26/.ssh/id_ed25519_muscat_jerez','jerez',command]


def summarize(observation):
    require(observation.get('schema')=='r178_jerez_metadata_observation_v1' and observation.get('host','').split('.')[0]=='jerez',
            'actual Jerez metadata required')
    require(observation.get('affinity')==[31] and observation.get('R_started') is False and observation.get('numerical_admission') is False
            and observation.get('signals')==0 and observation.get('source_or_runtime_changes')==0 and observation.get('new_peer_allowances')==[],
            'metadata-only unchanged host observation required')
    require(observation.get('all_process_arguments_redacted') is True,'unrelated process arguments must be redacted')
    matched=not observation['runtime_errors'] and bool(observation['runtime_files']) and all(x['matches'] for x in observation['runtime_files'])
    blockers=['EXISTING_R164_NUMERICAL_LAUNCHER_IS_MUSCAT_ONLY',
              'NEW_JEREZ_NUMERICAL_GUARD_OWNER_SOURCE_RUNTIME_AND_TARGET_AUTHORITY_REQUIRED']
    if not matched:blockers.append('PINNED_REQUIRED_RUNTIME_BYTES_MISSING_OR_DIFFERENT')
    if observation['same_UID_numerical_intersections_pair30_62'] or observation['process_observation_errors']:
        blockers.append('UNREVIEWED_PHYSICAL_PAIR_PROCESS_IDENTITIES')
    if observation['disk_free_bytes']<80*1024**3:blockers.append('UNCHANGED_MUSCAT_GUARD_DISK80_FLOOR_WOULD_FAIL_ON_JEREZ')
    return {'schema':'r178_jerez_preparation_result_v1','status':'PREPARED_UNADMITTED_DISTINCT_HOST_ROUTE',
            'observed_epoch':observation['observed_epoch'],'runtime_bytes_match_Muscat_binding':matched,
            'disk_floor50_GiB_preserved':observation['disk_free_bytes']>=50*1024**3,
            'memory192_GiB_floor_preserved':observation['memory']['MemAvailable']>=192*1024**3,
            'candidate_pair_topology':observation['topology'],
            'unreviewed_numerical_intersections':len(observation['same_UID_numerical_intersections_pair30_62']),
            'blockers':blockers,'numerical_admission':False,'existing_Muscat_guard_or_policy_modified':False,
            'Jerez_floor50_not_a_relabelled_Muscat_floor80':True,'requires_independent_host_guard_qualification_and_policy_review':True}
