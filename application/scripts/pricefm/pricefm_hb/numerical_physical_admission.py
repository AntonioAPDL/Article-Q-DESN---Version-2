"""Numerical physical-core admission, separate from metadata one-CPU checks.

Capture does not grant execution. An affinity of length one, Slurm hint or
metadata namespace PASS never proves SMT ownership. Missing current Slurm
core-allocation policy, peer/drain evidence or independent review fails closed.
Only current-job scheduler and exact CPU topology are queried here.
"""
import os
import ctypes
import resource
from pathlib import Path
import re
import subprocess
import time
from . import startup_helper as h
from . import scientific_allocation as allocation

MINIMUM_AVAILABLE_BYTES=80*1024**3


def filesystem_facts(path):
    """Reported filesystem capacity only; no inference about the user's quota."""
    root=h.physical(path);stat=root.stat();facts=os.statvfs(root)
    value=dict(status='OBSERVED_NUMERICAL_FILESYSTEM_STAT_NOT_USER_QUOTA',path=str(root),device=stat.st_dev,
        fragment_bytes=facts.f_frsize,available_blocks=facts.f_bavail,
        available_bytes=facts.f_bavail*facts.f_frsize,free_bytes=facts.f_bfree*facts.f_frsize,
        minimum_available_bytes=MINIMUM_AVAILABLE_BYTES,quota_status='UNKNOWN',observed_epoch=time.time())
    validate_filesystem(value,str(root),now=time.time());return value


def validate_filesystem(value,path,*,now):
    fields=['device','fragment_bytes','available_blocks','available_bytes','free_bytes','minimum_available_bytes']
    h.require(value.get('status')=='OBSERVED_NUMERICAL_FILESYSTEM_STAT_NOT_USER_QUOTA'
              and value.get('path')==path and all(type(value.get(k)) is int and value[k]>=0 for k in fields)
              and value['fragment_bytes']>0 and value['available_bytes']==value['available_blocks']*value['fragment_bytes']
              and value['free_bytes']>=value['available_bytes']>=value['minimum_available_bytes']==MINIMUM_AVAILABLE_BYTES
              and value.get('quota_status')=='UNKNOWN' and type(value.get('observed_epoch')) in (int,float)
              and now-150<=value['observed_epoch']<=now,
              'fresh typed filesystem stat with original80GiB available floor; user quota remains UNKNOWN')
    return True


def cpu_list(text):
    result=set()
    for item in text.strip().split(','):
        match=re.fullmatch(r'(\d+)(?:-(\d+))?',item)
        h.require(match is not None,'exact kernel CPU list')
        first=int(match[1]);last=int(match[2] or match[1]);h.require(first<=last,'ordered CPU range')
        result.update(range(first,last+1))
    return sorted(result)


def topology(cpu):
    h.require(type(cpu) is int and cpu>=0,'exact assigned logical CPU')
    root=Path('/sys/devices/system/cpu')/('cpu'+str(cpu))/'topology'
    return dict(cpu=cpu,physical_package_id=int((root/'physical_package_id').read_text()),
                core_id=int((root/'core_id').read_text()),
                thread_siblings=cpu_list((root/'thread_siblings_list').read_text()))


def job_cpuset(job_id,cgroup_text=None,mount_text=None,reader=None):
    """Read the job ancestor's kernel CPU set, never infer it from task affinity."""
    cgroup_text=Path('/proc/self/cgroup').read_text() if cgroup_text is None else cgroup_text
    mount_text=Path('/proc/self/mountinfo').read_text() if mount_text is None else mount_text
    reader=(lambda path:Path(path).read_text()) if reader is None else reader
    memberships=[]
    for line in cgroup_text.splitlines():
        fields=line.split(':',2);h.require(len(fields)==3,'well-formed kernel cgroup membership')
        controllers=fields[1].split(',') if fields[1] else []
        if 'cpuset' in controllers or (fields[0]=='0' and fields[1]==''):
            parts=Path(fields[2]).parts
            positions=[i for i,part in enumerate(parts) if part=='job_'+str(job_id)]
            if positions:
                h.require(len(positions)==1,'one exact job ancestor in CPU membership')
                memberships.append((2 if fields[0]=='0' and fields[1]=='' else 1,Path(*parts[:positions[0]+1])))
    found=[]
    for version,job_path in memberships:
        for line in mount_text.splitlines():
            left,separator,right=line.partition(' - ')
            if not separator:continue
            before=left.split();after=right.split()
            if len(before)<5 or len(after)<3:continue
            if (version==2 and after[0]!='cgroup2') or (version==1 and not(after[0]=='cgroup' and 'cpuset' in after[2].split(','))):continue
            mount_root=Path(before[3]);mountpoint=Path(before[4])
            h.require('\\' not in str(mount_root)+str(mountpoint),'escaped cgroup mount paths require explicit review')
            try:relative=job_path.relative_to(mount_root)
            except ValueError:continue
            filesystem=mountpoint/relative
            effective=None;source=None
            options=['cpuset.cpus.effective'] if version==2 else ['cpuset.effective_cpus','cpuset.cpus']
            for name in options:
                try:raw=reader(str(filesystem/name))
                except (FileNotFoundError,KeyError):continue
                h.require(len(raw)<=4096,'bounded current-job CPU set')
                if raw.strip():effective=cpu_list(raw);source=str(filesystem/name);break
            h.require(effective is not None,'actual job-ancestor effective CPU set unavailable')
            found.append(dict(version=version,job_cgroup_path=str(job_path),job_filesystem_path=str(filesystem),
                              effective_file=source,effective_cpus=effective))
    h.require(len(found)==1,'one resolved actual current-job cpuset controller required')
    return found[0]


def own_children():
    return sorted({int(pid) for path in Path('/proc/self/task').glob('*/children') for pid in path.read_text().split()})


def begin_ownership():
    h.require(own_children()==[],'no predecessor children may enter numerical startup ownership')
    libc=ctypes.CDLL(None,use_errno=True)
    h.require(libc.prctl(36,1,0,0,0)==0,'exclusive startup child-subreaper required')


def observed_native(argv):
    h.require(argv[:2] in [['/usr/bin/scontrol','show'],['/usr/bin/squeue','--noheader']],
              'allowlisted native metadata query only')
    before=resource.getrusage(resource.RUSAGE_CHILDREN)
    with subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,preexec_fn=lambda:None) as child:
        pid=child.pid;path=Path('/proc')/str(pid)
        stat=path.joinpath('stat').read_text().rsplit(')',1)[1].split()
        status=path.joinpath('status').read_text().splitlines()
        identity=dict(pid=pid,start_ticks=int(stat[19]),uid=int(next(line.split()[1] for line in status if line.startswith('Uid:'))))
        h.require(identity['uid']==os.getuid(),'fresh own native startup child UID')
        try:stdout,stderr=child.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            # Popen's exact still-owned child only; retain failure, never launch R.
            child.kill();stdout,stderr=child.communicate();raise ValueError('bounded own native startup query timed out')
        result=dict(argv=argv,identity=identity,returncode=child.returncode,stdout=stdout,stderr=stderr,
                    exact_child_reaped=child.returncode is not None)
    after=resource.getrusage(resource.RUSAGE_CHILDREN)
    result['reaped_CPU_delta_attribution_only']=(after.ru_utime+after.ru_stime)-(before.ru_utime+before.ru_stime)
    h.require(len(stdout.encode())<=256*1024 and len(stderr.encode())<=4096,'bounded native startup metadata')
    return result


def capture(job_id,node,known_prior_jobs=(),output=None,*,disk_root=None):
    affinity=sorted(os.sched_getaffinity(0));h.require(len(affinity)==1,'one assigned CPU before metadata capture')
    h.require(disk_root is not None or output is not None,'actual numerical filesystem path required')
    filesystem=filesystem_facts(disk_root if disk_root is not None else Path(output).parent)
    live=allocation.live(job_id,node,affinity,minimum_remaining=300)
    job=observed_native(['/usr/bin/scontrol','show','job','-o',job_id])
    config=observed_native(['/usr/bin/scontrol','show','config'])
    partition=observed_native(['/usr/bin/scontrol','show','partition','-o','128x24'])
    h.require(job['returncode']==config['returncode']==partition['returncode']==0,'actual current Slurm job/configuration/partition facts required')
    fields=dict(re.findall(r'^\s*(SelectType(?:Parameters)?|TaskPlugin|ProctrackType)\s*=\s*(\S+)',config['stdout'],re.M))
    partition_fields=dict(re.findall(r'(\S+?)=(\S*)',partition['stdout']))
    h.require(partition_fields.get('PartitionName')=='128x24','current exact admitted partition')
    fields['PartitionOverSubscribe']=partition_fields.get('OverSubscribe','UNKNOWN')
    h.require(type(known_prior_jobs) in (list,tuple) and 1<=len(known_prior_jobs)<=32,'finite exact prior PriceFM jobs required')
    known={}
    for row in known_prior_jobs:
        h.require(re.fullmatch('[1-9][0-9]*',row['job_id']) and re.fullmatch(r'r[0-9]+-[A-Za-z0-9_-]+',row['job_name'])
                  and row['job_id']!=job_id and row['job_name'] not in known and row.get('terminal') is True,
                  'exact previously terminal PriceFM identity, never current or unrelated job')
        known[row['job_name']]=row['job_id']
    queue=observed_native(['/usr/bin/squeue','--noheader','--user','jaguir26','--name',','.join(sorted(known)),'--format','%i|%128j|%T'])
    h.require(queue['returncode']==0,'known PriceFM queue query must succeed')
    queue_rows=[]
    for line in queue['stdout'].splitlines():
        fields_row=[value.strip() for value in line.split('|')];h.require(len(fields_row)==3 and fields_row[1] in known,'exact known-name queue rows only')
        queue_rows.append(dict(job_id=fields_row[0],job_name=fields_row[1],state=fields_row[2],expected_id=known[fields_row[1]]))
    children=own_children();now=time.time();topo=topology(affinity[0]);cgroups=allocation.exact_cgroup(Path('/proc/self/cgroup').read_text(),job_id,os.getuid())
    cpuset=job_cpuset(job_id);online_raw=Path('/sys/devices/system/cpu/online').read_text();online=cpu_list(online_raw)
    online_siblings=sorted(set(topo['thread_siblings'])&set(online))
    supervisor=dict(pid=os.getpid(),start_ticks=h.process_birth_ticks(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),affinity=affinity,uid=os.getuid())
    common=dict(job_id=job_id,node=node,uid=os.getuid(),observed_epoch=now)
    witnesses=dict(
        allocation_witness=dict(common,status='OBSERVED_CURRENT_JOB_SLURM_CORE_POLICY_NOT_ADMISSION',scheduler=live,topology=topo,Slurm_core_policy=fields,
            job_cpuset=cpuset,online_thread_siblings=online_siblings),
        peer_ownership_witness=dict(common,status='OBSERVED_OWN_CGROUP_AND_STARTUP_TREE_NOT_ADMISSION',supervisor=supervisor,cgroups=cgroups,
            pending_owned_children=children,all_declared_native_helpers_reaped=all(r['exact_child_reaped'] and r['returncode']==0 for r in [job,config,partition,queue]),
            unrelated_projects_censused=False,core_exclusivity_requires_actual_Slurm_policy_review=True),
        priority_drain_witness=dict(common,status='OBSERVED_KNOWN_PRICEFM_QUEUE_AND_OWN_STARTUP_DRAIN_NOT_ADMISSION',known_prior_jobs=list(known_prior_jobs),
            observed_queue_rows=queue_rows,all_known_PriceFM_jobs_absent=queue_rows==[],pending_owned_children=children,
            no_production_processes_signalled=True))
    witness_pins={};native_pin=None
    native_value=dict(common,status='ACTUAL_OWN_NATIVE_STARTUP_OBSERVATIONS_NOT_ADMISSION',records=[job,config,partition,queue],
        own_startup_helpers_reaped=children==[],counters_are_attribution_not_additional_charges=True)
    if output is not None:
        folder=h.physical(output);folder.mkdir(mode=0o700)
        for key,value in witnesses.items():
            path=folder/(key.upper()+'.json');h.write_new(path,value);witness_pins[key]=h.pin(path)
        h.write_new(folder/'NATIVE_OBSERVATIONS.json',native_value);native_pin=h.pin(folder/'NATIVE_OBSERVATIONS.json')
    h.require(children==[],'own startup helper tree not drained; no numerical release')
    return dict(status='OBSERVED_NUMERICAL_CORE_METADATA_NOT_ADMISSION',job_id=job_id,node=node,
                uid=os.getuid(),observed_epoch=time.time(),affinity=affinity,topology=topology(affinity[0]),
                scheduler=live,Slurm_core_policy=fields,raw_scheduler_configuration=config['stdout'],
                job_cpuset=cpuset,online_thread_siblings=online_siblings,
                online_cpu_list_raw=online_raw,
                supervisor=supervisor,witnesses=witnesses,witness_pins=witness_pins,
                native_observations_value=native_value,native_observations=native_pin,
                filesystem=filesystem,
                unreviewed_peer_and_priority_drain_status='UNPROVED_REQUIRES_EXACT_INDEPENDENT_WITNESS',
                physical_numerical_admission=False)


def validate(snapshot,proof,review,*,job_id,node,affinity,now):
    h.require(snapshot.get('status')=='OBSERVED_NUMERICAL_CORE_METADATA_NOT_ADMISSION'
              and snapshot.get('job_id')==job_id and snapshot.get('node')==node
              and snapshot.get('uid')==os.getuid() and snapshot.get('affinity')==affinity
              and now-150<=snapshot['observed_epoch']<=now,'fresh current-job physical snapshot')
    h.require(type(snapshot.get('filesystem')) is dict and type(snapshot['filesystem'].get('path')) is str,
              'actual typed filesystem observation required, never affinity-only admission')
    validate_filesystem(snapshot['filesystem'],snapshot['filesystem']['path'],now=now)
    policy=snapshot['Slurm_core_policy']
    parameters={p.upper() for p in policy.get('SelectTypeParameters','').split(',')}
    core_policy=bool(parameters & {'CR_CORE','CR_CORE_MEMORY'})
    singleton=bool(parameters & {'CR_CPU','CR_CPU_MEMORY'}) and snapshot['topology']['thread_siblings']==affinity
    h.require(policy.get('SelectType')=='select/cons_tres' and (core_policy or singleton)
              and 'task/cgroup' in policy.get('TaskPlugin','').split(',')
              and policy.get('ProctrackType')=='proctrack/cgroup'
              and policy.get('PartitionOverSubscribe') in {'NO','EXCLUSIVE'},
              'verified current whole-core allocation and kernel task/cgroup ownership policy required')
    h.require(snapshot['topology']==topology(affinity[0]) and affinity[0] in snapshot['topology']['thread_siblings'],
              'actual physical core and every SMT sibling must match')
    current_set=job_cpuset(job_id)
    current_online=sorted(set(topology(affinity[0])['thread_siblings'])&set(cpu_list(Path('/sys/devices/system/cpu/online').read_text())))
    h.require(snapshot.get('job_cpuset')==current_set and snapshot.get('online_thread_siblings')==current_online
              and current_online and sorted(current_set['effective_cpus'])==current_online
              and affinity[0] in current_set['effective_cpus'],
              'kernel job-ancestor CPU allocation must reserve exactly the observed online physical core/SMT siblings')
    h.require(proof.get('status')=='ROOT_ADMITTED_EXACT_SLURM_NUMERICAL_PHYSICAL_CORE'
              and proof.get('job_id')==job_id and proof.get('node')==node
              and proof.get('uid')==os.getuid() and proof.get('affinity')==affinity
              and proof.get('topology')==snapshot['topology']
              and proof.get('Slurm_core_policy')==policy
              and proof.get('all_SMT_siblings_reserved_to_this_job') is True
              and proof.get('unreviewed_numerical_peer_intersections')==[]
              and proof.get('priority_drain_complete') is True
              and proof.get('old_processes_signalled_or_peer_allowlist_broadened') is False
              and proof['issued_epoch']<=now<proof['expires_epoch']<=snapshot['scheduler']['end_epoch'],
              'fresh exact whole-core/SMT peer and priority-drain authority required')
    h.require(review.get('status')=='PASS_REVIEWED_EXACT_SLURM_NUMERICAL_CORE_AND_PEER_DRAIN'
              and review.get('job_id')==job_id and review.get('node')==node
              and review.get('topology')==snapshot['topology']
              and review.get('all_peer_and_drain_witnesses_bound') is True,
              'independently bound actual core/peer/drain proof required; no schema-only substitution')
    for key in ['allocation_witness','peer_ownership_witness','priority_drain_witness']:
        h.require(proof.get(key)==review.get(key),'physical proof and peer review witness disagreement')
        h.require(proof[key]==snapshot['witness_pins'][key],'actual before-READY producer witness required')
        witness=h.read(proof[key])
        h.require(witness.get('job_id')==job_id and witness.get('node')==node
                  and witness.get('observed_epoch',0)>=snapshot['observed_epoch']-30,
                  'actual current exact physical witness required')
        h.require(witness==snapshot['witnesses'][key],'witness bytes differ from current-job observation')
    peer_witness=snapshot['witnesses']['peer_ownership_witness'];drain=snapshot['witnesses']['priority_drain_witness']
    h.require(peer_witness['pending_owned_children']==[] and peer_witness['all_declared_native_helpers_reaped'] is True
              and peer_witness['unrelated_projects_censused'] is False and drain['all_known_PriceFM_jobs_absent'] is True
              and drain['pending_owned_children']==[] and drain['no_production_processes_signalled'] is True,
              'actual own startup tree and exact known PriceFM drain required')
    return True


ALLOWLISTED_QUERIES=(('/usr/bin/scontrol','show','config'),
                     ('/usr/bin/scontrol','show','job','-o','<ACTUAL_CURRENT_JOB_ID>'),
                     ('/usr/bin/scontrol','show','partition','-o','128x24'),
                     ('/usr/bin/squeue','--noheader','--user','jaguir26','--name','<EXACT_KNOWN_PRICEFM_NAMES>','--format','%i|%128j|%T'))
