"""Live one-job Slurm/cgroup evidence for data-free scientific qualification."""
import os
from pathlib import Path
import re
import subprocess
import time

from . import profile_admission as admission
from .startup_helper import require


def exact_cgroup(text, job_id, uid):
    require(str(job_id).isdigit() and type(uid) is int, 'exact numeric job and UID required')
    paths=[]
    for line in text.splitlines():
        fields=line.split(':',2)
        require(len(fields)==3 and fields[2].startswith('/'), 'well-formed cgroup record required')
        parts=fields[2].split('/')
        jobs=[part for part in parts if part.startswith('job_')]
        users=[part for part in parts if part.startswith('uid_')]
        if users:require(users==['uid_'+str(uid)],'contradictory Slurm UID membership forbidden')
        if jobs:
            require(jobs==['job_'+str(job_id)] and users in ([],['uid_'+str(uid)]),
                    'contradictory Slurm job/UID membership forbidden')
        if 'job_'+str(job_id) in parts:
            # Slurm v1 can name uid_N; v2 can omit it. A label is not UID
            #authority: live() separately requires kernelUID/scontrol.UserId.
            paths.append(fields[2])
    require(paths, 'exact owned Slurm job cgroup component required')
    return paths


def live(job_id, node, affinity, *, minimum_remaining=0):
    require(os.environ.get('SLURM_JOB_ID')==job_id and os.environ.get('SLURMD_NODENAME')==node
            and os.environ.get('SLURM_CPUS_PER_TASK')=='1' and len(affinity)==1
            and os.sched_getaffinity(0)==set(affinity), 'live one-CPU environment and affinity required')
    cgroups=exact_cgroup(Path('/proc/self/cgroup').read_text(),job_id,os.getuid())
    result=subprocess.run(['/usr/bin/scontrol','show','job','-o',job_id],text=True,capture_output=True,timeout=10,check=True)
    fields=dict(re.findall(r'(\S+?)=(\S*)',result.stdout))
    require(fields.get('JobId')==job_id and fields.get('JobState')=='RUNNING'
            and fields.get('NumCPUs')==fields.get('NumTasks')==fields.get('NumNodes')=='1'
            and fields.get('Requeue')=='0' and fields.get('NodeList')==node
            and fields.get('Partition')==fields.get('Account')=='128x24' and fields.get('QOS')=='normal',
            'live exact one-node/CPU/task non-requeueing allocation class required')
    require(re.fullmatch(r'[A-Za-z0-9_.-]+\('+str(os.getuid())+r'\)',fields.get('UserId','')),
            'live scheduler job UID required')
    memory=admission._memory_MiB(fields.get('MinMemoryNode') or fields.get('MinMemoryCPU',''))
    wall=admission._wall_seconds(fields.get('TimeLimit',''))
    require(os.environ.get('TZ')=='UTC', 'UTC scheduler clock required')
    end=time.mktime(time.strptime(fields.get('EndTime',''),'%Y-%m-%dT%H:%M:%S'))
    cgmem=admission.cgroup_memory_limit()
    require(memory==8192 and 0<cgmem<=8192*1024**2 and 0<wall<=1200
            and end>time.time()+minimum_remaining, 'complete8GiB/1200wall live resource window required')
    return dict(job_id=job_id,node=node,uid=os.getuid(),cpus=1,tasks=1,nodes=1,requeue=False,
                memory_MiB=memory,wall_seconds=wall,end_epoch=end,cgroup_memory_limit_bytes=cgmem,cgroups=cgroups)
