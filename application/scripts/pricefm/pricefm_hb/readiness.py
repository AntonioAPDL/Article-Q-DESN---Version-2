"""Read-only, finite future COST_ONLY request/proof refresh; never submits work.

Run on Muscat administrative31 with the pinned Python and -B. Configuration
contains evidence locations, not positive gate overrides. Each run writes only
one fresh output directory. A failed observation emits BLOCKED, never authority.
"""
from __future__ import annotations
import argparse
import datetime as dt
import inspect
import json
import math
import os
from pathlib import Path
import re
import resource
import shlex
import signal
import socket
import subprocess
import sys
import time
import uuid
from . import cost_control as cost, control as ctl, registry as r

SCHEMA = 'r156_readiness_operator_v1'
RESULT_SCHEMA = 'r156_readiness_refresh_v1'
PYTHON = '/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
TRACKERS = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers')
R155 = TRACKERS/'pricefm_chat_continuation_20261021/r155_screening_recovery_20261027'
EE_COMMAND = [PYTHON, '-B', str(TRACKERS/'worktrees/pricefm_r155_qualified_seeds_cold_floor_20261027/application/scripts/pricefm/529_run_pricefm_stage_r155_qualified_seeds.py'), '--inspect', '--preparation', str(R155/'qualified_seed_runtime_preparation_20261027/prepared_01/preparation.json'), '--authority', str(R155/'qualified_seed_runtime_preparation_20261027/ROOT_A12_AUTHORITY_ADMITTED_01.json'), '--authority-sha256', 'd7604eb38a00194d569a5f9ee65ed8e63cd42750f4438b1dffeea0b816710df3']
TERMINAL = {'COLLECTED', 'FAILED_RECONCILED', 'COLLECTED_COST_ONLY', 'COMPLETE', 'CLOSED', 'RETIRED', 'CLOSED_NO_NEW_WORK'}


class Blocked(ValueError):
    pass


def metadata(path):
    path = r.no_links(path)
    if not path.is_file() or path.stat().st_size > 16*1024**2 or path.suffix != '.json':
        raise Blocked('bounded regular JSON metadata required: '+str(path))
    return r.read(path)


class Budget:
    def __init__(self):
        self.start = time.monotonic(); self.remote_cpu = 0.0
    def used_cpu(self):
        a=resource.getrusage(resource.RUSAGE_SELF); b=resource.getrusage(resource.RUSAGE_CHILDREN)
        return a.ru_utime+a.ru_stime+b.ru_utime+b.ru_stime+self.remote_cpu
    def check(self):
        if time.monotonic()-self.start >= 60 or self.used_cpu() >= 10:
            raise Blocked('60wall/10CPU whole metadata observer allowance exhausted')
    def timeout(self, maximum):
        self.check(); return max(.1,min(maximum,59-(time.monotonic()-self.start)))
    def receipt(self):
        return {'allowance_wall_seconds':60,'allowance_CPU_seconds':10,'wall_seconds':time.monotonic()-self.start,
                'CPU_seconds':self.used_cpu(),'remote_CPU_seconds':self.remote_cpu,'affinity':[31]}


def run(argv, budget, *, stdin=None, maximum=12):
    budget.check()
    remaining=max(1,int(9-budget.used_cpu()))
    def limits(): resource.setrlimit(resource.RLIMIT_CPU,(remaining,remaining))
    result=subprocess.run(argv,input=stdin,text=True,capture_output=True,timeout=budget.timeout(maximum),preexec_fn=limits)
    budget.check()
    if result.returncode: raise Blocked('read-only observer failed: '+result.stderr[-1200:])
    return result.stdout


def metadata_snapshot(spec):
    """Stdlib-only read observer, also serialized verbatim to approved SSH hosts."""
    import hashlib, json, os, pathlib, re, resource, socket, subprocess, time
    if spec.get('remote_observer'): resource.setrlimit(resource.RLIMIT_CPU,(3,3))
    start=time.monotonic(); now=time.time(); rows=[]; unreadable=[]; registry=[]; uid=os.getuid()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit(): continue
        try:
            if proc.stat().st_uid != uid or int(proc.name)==os.getpid(): continue
            fields=(proc/'stat').read_text().rsplit(')',1)[1].split()
            if fields[0]=='Z': continue
            raw=(proc/'cmdline').read_bytes()
            if len(raw)>131072: raise ValueError('oversized own command line')
            argv=raw.decode(errors='replace').rstrip('\0').split('\0')
            if not raw: raise PermissionError('empty live own command line')
            direct=[a for a in argv if not any(ch.isspace() for ch in a) and len(a)<4096]
            module=direct[direct.index('-m')+1] if '-m' in direct and direct.index('-m')+1<len(direct) else ''
            readonly=module in {'pricefm_hb.readiness','pricefm_hb.benchmark_plan'}
            if module=='pricefm_hb.cost_control':
                readonly='cost-worker' not in direct
            if '--inspect' in direct and any('529_run_pricefm_stage_r155_qualified_seeds.py' in a for a in direct): readonly=True
            if readonly: continue
            relevant=any(spec['exclusion_key'] in a for a in direct)
            region_re=re.compile(r'(?:^|[/_:=-])(?:FI|DK_2|DK2)(?:$|[/_:=-])')
            relevant=relevant or any(region_re.search(a) for a in direct)
            scientific=module in {'pricefm_hb.benchmark'} or (module=='pricefm_hb.cost_control' and 'cost-worker' in direct)
            scientific=scientific or any(re.match(r'(?:50[25679]|49[457])_.*\.py$',pathlib.Path(a).name) for a in direct)
            if relevant or scientific:
                rows.append({'pid':int(proc.name),'start_ticks':int(fields[19]),'argv':argv,'matching_region_or_key':relevant,
                             'scientific_runner':scientific,'state':fields[0]})
        except (FileNotFoundError,ProcessLookupError): continue
        except (OSError,ValueError,IndexError) as exc: unreadable.append({'pid':int(proc.name),'error':type(exc).__name__})
    for entry in spec.get('registries',[]):
        path=pathlib.Path(entry['path'])
        try:
            if path.is_symlink() or any(p.is_symlink() for p in path.parents): raise ValueError('symlink registry')
            if path.stat().st_size>16*1024**2: raise ValueError('oversized registry')
            data=json.loads(path.read_text());held=[]
            capsule=data.get('publisher_capsule',{}) if isinstance(data,dict) else {}
            old=capsule.get('process',{})
            if old.get('pid') and old.get('start_ticks'):
                try:
                    current=(pathlib.Path('/proc')/str(old['pid'])/'stat').read_text().rsplit(')',1)[1].split()
                    boot=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
                    held.append({'pid':old['pid'],'same_exact_lifetime':int(current[19])==old['start_ticks'] and boot==old.get('boot_id')})
                except (FileNotFoundError,ProcessLookupError):held.append({'pid':old['pid'],'same_exact_lifetime':False})
            registry.append({'path':str(path),'value':data,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                             'present':True,'recorded_lifetimes':held})
        except FileNotFoundError:registry.append({'path':str(path),'present':False})
        except (OSError,ValueError) as exc:registry.append({'path':str(path),'error':str(exc)})
    for logical in spec.get('legacy_outputs',[]):
        path=pathlib.Path(logical)
        # Enumerate only top-level descriptors. Never recurse into arrays/banks.
        try:registry.append({'path':str(path),'output_descriptor_only':True,'present':path.is_dir(),
                             'entries':sorted(p.name for p in path.iterdir()) if path.is_dir() else []})
        except OSError as exc:registry.append({'path':str(path),'error':str(exc)})
    result={'observed_epoch':now,'host':socket.getfqdn(),'pid_namespace':os.readlink('/proc/self/ns/pid'),
            'visible_processes':sum(p.name.isdigit() for p in pathlib.Path('/proc').iterdir()),
            'matching_processes':rows,'unreadable_own_processes':unreadable,'registries':registry}
    if spec.get('slurm'):
        commands={'queue':['squeue','-h','-u','jaguir26','-o','%i|%j|%T|%R'],
                  'node':['scontrol','show','node','node-07','-o'],
                  'partition':['scontrol','show','partition','128x24','-o']}
        result['slurm']={}
        for label,args in commands.items():
            value=subprocess.run(args,capture_output=True,text=True,timeout=10)
            if value.returncode:raise ValueError('Slurm metadata query failed: '+value.stderr[-400:])
            result['slurm'][label]=value.stdout
        stat=os.statvfs(spec['disk_path']);result['free_disk_bytes']=stat.f_bavail*stat.f_frsize
    own=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
    result['CPU_seconds']=own.ru_utime+own.ru_stime+children.ru_utime+children.ru_stime
    result['wall_seconds']=time.monotonic()-start
    return result


def observe(host, spec, site, budget):
    if host==cost.OWNER:
        value=metadata_snapshot(spec)
    else:
        if host=='hb.ucsc.edu': argv=ctl.ssh(site)
        elif host=='jerez.be.ucsc.edu':
            argv=['ssh','-T','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ForwardAgent=no',
                  '-o','ForwardX11=no','-o','ClearAllForwardings=yes','-o','ConnectTimeout=10',
                  '-o','ConnectionAttempts=1','-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no','jerez']
        else: raise Blocked('unknown observation host')
        spec=dict(spec,remote_observer=True)
        script='import json\n'+inspect.getsource(metadata_snapshot)+'\nprint(json.dumps(metadata_snapshot('+repr(spec)+')))\n'
        remote_python=PYTHON if host=='jerez.be.ucsc.edu' else '/usr/bin/python3'
        remote_timeout=38 if host=='hb.ucsc.edu' else 16
        value=json.loads(run(argv+['timeout '+str(remote_timeout)+'s '+shlex.quote(remote_python)+' -B -'],budget,stdin=script,
                             maximum=42 if host=='hb.ucsc.edu' else 22))
        cpu=value.get('CPU_seconds')
        if type(cpu) not in (float,int) or not math.isfinite(cpu) or cpu<0:raise Blocked('remote observer CPU not accounted')
        budget.remote_cpu+=cpu
    budget.check()
    expected={'muscat.be.ucsc.edu':{cost.OWNER},'jerez.be.ucsc.edu':{'jerez.be.ucsc.edu'},
              'hb.ucsc.edu':{'hb.ucsc.edu','rit-prd-clusterlogin-1.ucsc.edu','rit-prd-clusterlogin-2.ucsc.edu'}}
    if value.get('host') not in expected[host] or not cost.fresh(value,time.time()): raise Blocked('host identity/freshness not established')
    if host!= 'hb.ucsc.edu' and (value.get('pid_namespace')!='pid:[4026531836]' or value.get('visible_processes',0)<100):
        raise Blocked('full actual host process namespace required')
    return value


def save(directory,name,value):
    path=directory/name
    if path.exists():raise FileExistsError('fresh proof file required')
    r.write(path,value);return cost.pin(path)


def normalized_ee(observation, delivered_report, directory):
    if (observation.get('complete_components')!=12 or observation.get('required_components')!=12 or
            observation.get('remaining_components')!=0 or observation.get('scientifically_complete_and_physically_drained') is not True or
            observation.get('same_original_flock_free') is not True or observation.get('phase')!='COMPLETED_RETAINED_UNIT_FULL_MATCHED_SET_DRAINED' or
            {p.get('role') for p in observation.get('processes',[])}!={'guardian.json','payload_identity.json'} or
            any(p.get('live_exact_lifetime') is not False for p in observation.get('processes',[]))):
        raise Blocked('source529 does not establish complete12, assessment and exact physical drain')
    records=observation['records'];assessment=records['assessment.json'];seal=records['assessment_seal.json']
    if not assessment or not seal or seal['value'].get('assessment')!=assessment['pin']:
        raise Blocked('source529 assessment seal binding absent')
    cost.pinned(assessment['pin']);cost.pinned(delivered_report,parse=False)
    drain=save(directory,'EE_physical_drain.json',{'status':'DRAINED','observed_epoch':observation['epoch'],
        'live_worker_pids':[],'live_job_ids':[],'active_scientific_claims':[],
        'source':'source529 --inspect','observation':cost.pin(directory/'EE_source529.json'),
        'same_original_flock_free':True,'actual_unit':observation['actual_unit']})
    names=assessment['value']['required_task_names']
    return save(directory,'EE_completion_receipt.json',{'status':'COMPLETE_EE_DISPOSITION_DELIVERED_DRAINED',
        'required_task_names':names,'completed_task_names':names,'assessment_accepted':True,
        'scientific_assessment':assessment['pin'],'assessment_seal':seal['pin'],'delivered_report':delivered_report,'physical_drain':drain})


def qualification(publication, prefix):
    root=r.no_links(publication); outputs=root/'outputs'
    outer=metadata(outputs/'completed_evidence.json');accounting=metadata(root/'accounting.json')
    result=outputs/('environment-evidence/runtime-verification.json' if prefix=='runtime' else 'TEST/parity/parity.json')
    if outer.get('application_passed') is not True or outer.get('files',{}).get(str(result.relative_to(outputs)))!=r.digest(result):
        raise Blocked('published '+prefix+' result missing its accepted hash seal')
    if accounting.get('job_id')!=outer.get('job_id') or accounting.get('complete') is not True or accounting.get('squeue','').strip():
        raise Blocked('published '+prefix+' lacks completed accounting')
    if not ctl.accounting(accounting['sacct'],outer['job_id'],{'cpus':1,'wall_seconds':1800,'memory_MiB':8192})['complete']:
        raise Blocked('qualification scheduler accounting is not complete')
    return {prefix+'_result':cost.pin(result),prefix+'_qualification_seal':cost.pin(outputs/'completed_evidence.json'),
            prefix+'_accounting':cost.pin(root/'accounting.json')}


def fields(text):
    return dict(re.findall(r'(\w+)=([^\s]+)',text))


def duration(value):
    if value=='UNLIMITED':return 365*86400
    days,_,clock=value.partition('-') if '-' in value else ('0','',value)
    pieces=[int(x) for x in clock.split(':')]
    return int(days)*86400+sum(v*factor for v,factor in zip(reversed(pieces),(1,60,3600)))


def registry_overlaps(value, exclusion):
    if value.get('error'):raise Blocked('unreadable registry: '+value['path'])
    if not value.get('present'):return ['UNKNOWN_MISSING_REGISTRY:'+value['path']]
    document=value.get('value',{})
    if not isinstance(document,dict):raise Blocked('unknown registry format')
    if 'claims' not in document:
        status=str(document.get('status',''))
        if any(item.get('same_exact_lifetime') is not False for item in value.get('recorded_lifetimes',[])):
            return ['LIVE_RETAINED_LIFETIME:'+value['path']]
        if (document.get('future_admissions_closed') is True and document.get('cleanup_verified') is True and
                isinstance(document.get('scope_id'),str) and cost.SHA.fullmatch(str(document.get('master_sha256',''))) and
                cost.SHA.fullmatch(str(document.get('terminal_sha256','')))):
            return []
        if (status=='R152_GUARD_STOPPED' and document.get('cleanup_verified') is True and document.get('fanout_stop') is True and
                document.get('cleanup_errors')==[] and document.get('owned_pids')==[] and
                isinstance(document.get('scope_id'),str) and cost.SHA.fullmatch(str(document.get('master_sha256',''))) and
                cost.SHA.fullmatch(str(document.get('final_control_charge_sha256','')))):
            return []
        if (status in TERMINAL or status.startswith(('CLOSED_','RETIRED_'))) and not document.get('active'):
            return []
        raise Blocked('legacy document does not establish its terminal state: '+value['path'])
    claims=document['claims']
    if isinstance(claims,dict):
        return [str(key) for key,claim in claims.items() if claim.get('state') not in TERMINAL]
    raise Blocked('unknown claim registry format')


def never_admitted_absence(study,path,plan,snapshots,closure,closure_hashes):
    """A missing canonical descriptor is absence, never an invented closure.

    This exception is specific to the sealed R152 never-admitted FI/DK2 studies.
    It requires the current exact terminal and later complete closed-pool audit.
    Fresh process/registry overlap checks remain independent and mandatory.
    """
    config=metadata(plan['canonical_config']['path'])
    expected=cost.p.DATA/'campaigns'/config['tag']
    if Path(path)!=expected:raise Blocked('missing legacy descriptor is not the exact canonical campaign path')
    closed=closure.get('closed_scope',{});drain=closed.get('actual_drain',{});master=closure.get('master',{})
    cleanup=drain.get('cleanup',[])
    if (closure.get('status')!='PASS_CLOSED_CACHED_SCOPE_PRESERVED' or closure.get('errors') or
            closed.get('baseline_only') is not True or closed.get('cached_restart_authorized') is not False or
            closed.get('manifest_mismatches')!=[] or drain.get('cleanup_verified') is not True or drain.get('owned_pids')!=[] or
            len(cleanup)!=8 or any(row.get('drained') is not True or row.get('pids')!=[] for row in cleanup) or
            not cost.SHA.fullmatch(str(master.get('sha256',''))) or not isinstance(master.get('scope_id'),str) or
            not isinstance(closure.get('attempts'),list) or
            any(str(row.get('task','')).startswith(('FI_','DK2_','DK_2_')) for row in closure['attempts'])):
        raise Blocked('pinned legacy audit does not prove the FI/DK2 studies were never admitted and fully drained')
    for item in snapshots[cost.OWNER]['registries']:
        terminal=item.get('value',{});dispositions=terminal.get('study_dispositions',{})
        if (terminal.get('status')=='R152_GUARD_STOPPED' and study in dispositions and dispositions[study] is None and
                terminal.get('cleanup_verified') is True and terminal.get('fanout_stop') is True and
                terminal.get('cleanup_errors')==[] and terminal.get('owned_pids')==[] and
                terminal.get('master_sha256')==master.get('sha256')==drain.get('master_sha256') and
                terminal.get('scope_id')==master.get('scope_id')==drain.get('scope_id') and
                item.get('sha256')==closure_hashes.get(item.get('path')) and item.get('sha256') is not None):
            return {'status':'ABSENT_CANONICAL_DESCRIPTOR_STUDY_NEVER_ADMITTED','study':study,'path':str(expected),
                    'terminal':{'path':item['path'],'sha256':item['sha256']},'closed_scope_id':master['scope_id']}
    raise Blocked('current pinned legacy terminal does not prove the requested study was never admitted')


def new_window(plan_path, config_path, output_path, new_config_path, seconds=7200):
    """Create only a fresh unclaimed proposal and a newly pinned operator config."""
    cost.owner()
    if os.sched_getaffinity(0)!={31}:raise Blocked('administrative31 is mandatory')
    if type(seconds) is not int or not 1260<=seconds<=7200:raise Blocked('proposal window must be1260..7200seconds')
    plan=cost.load_plan(plan_path);study=plan['study'];config=metadata(config_path)
    if config.get('schema')!=SCHEMA:raise Blocked('unknown operator configuration schema')
    path=cost.CENTRAL/'cost_only_registry.json'
    state=metadata(path) if path.exists() else {'schema':cost.SCHEMA,'owner':cost.OWNER,'claims':{},'spent_regions':{}}
    if state.get('schema')!=cost.SCHEMA or state.get('owner')!=cost.OWNER:raise Blocked('canonical cost registry identity differs')
    if study in state.get('spent_regions',{}) or any(x.get('state') not in cost.FINAL for x in state.get('claims',{}).values()):
        raise Blocked('claimed/spent or unresolved cost work forbids a new calendar proposal')
    output_path=r.no_links(output_path);new_config_path=r.no_links(new_config_path)
    if output_path==new_config_path or output_path.exists() or new_config_path.exists():raise FileExistsError('new proposal and new configuration files required')
    now=time.time();proposal={'schema':'r156_proposed_cost_window_v1','status':'PROPOSED_FINITE_COST_WINDOW_NOT_AUTHORITY',
        'proposal_id':uuid.uuid4().hex,'study':study,'plan_sha256':r.digest(plan_path),'created_epoch':now,
        'expires_epoch':now+seconds,'authority_issued':False,'claim_created':False,
        'canonical_registry_path':str(path),'canonical_registry_snapshot_sha256':r.identity(state),
        'grant_expiry_or_spent_budget_reset':False}
    output_path.parent.mkdir(parents=True,exist_ok=True);r.write(output_path,proposal)
    updated=dict(config);updated['calendar_evidence']=dict(config.get('calendar_evidence',{}),**{study:cost.pin(output_path)})
    new_config_path.parent.mkdir(parents=True,exist_ok=True);r.write(new_config_path,updated)
    return {'status':'PROPOSED_WINDOW_ONLY_NO_AUTHORITY_NO_CLAIM','proposal':cost.pin(output_path),'config':cost.pin(new_config_path)}


def refresh(plan_path, config_path, output):
    cost.owner()
    if os.sched_getaffinity(0)!={31}:raise Blocked('administrative31 is mandatory')
    budget=Budget();resource.setrlimit(resource.RLIMIT_CPU,(10,10))
    output=r.no_links(output)
    if not output.is_absolute() or output.exists():raise FileExistsError('new absolute proof directory required')
    output.mkdir(parents=True)
    previous_alarm=signal.getsignal(signal.SIGALRM)
    def expired(signum,frame):raise Blocked('60wall metadata observer deadline reached')
    signal.signal(signal.SIGALRM,expired);signal.setitimer(signal.ITIMER_REAL,60)
    result={'schema':RESULT_SCHEMA,'status':'BLOCKED','observed_epoch':time.time(),'new_fits':0,'new_forecasts':0,
            'claims_created':0,'authorities_created':0,'jobs_submitted':0,'array_loads':0,'next_steps':[]}
    try:
        config=metadata(config_path)
        if config.get('schema')!=SCHEMA:raise Blocked('unknown operator configuration schema')
        plan=cost.load_plan(plan_path);study=plan['study'];plan_pin=cost.pin(plan_path);site=ctl.config(config['site_config'])
        request={'schema':cost.REQUEST_SCHEMA,'plan':plan_pin,'study':study,'full_prefix_admitted':False,'automatic_retry':False}
        request.update(qualification(config['runtime_publication'],'runtime'))
        request.update(qualification(config['parity_publication'],'parity'))
        parity_root=r.no_links(config['parity_publication'])/'outputs'
        request['parity_seal']=cost.pin(parity_root/'TEST/parity/completed_evidence.json')
        request['parity_runtime_result']=cost.pin(parity_root/'environment-runtime.json')
        runtime=cost.pinned(request['runtime_result']); parity=cost.pinned(request['parity_result'])
        request['runtime_python']=runtime['executable']
        # The environment bundle lives beside the verified runtime prefix.
        request['environment_bundle']=str(Path(runtime['executable']).parents[3]/'env')
        request['accepted_parity_fixture_manifest_sha256']=parity['execution']['fixture_manifest_sha256']
        request['adapter_review']=config['adapter_reviews'][study];cost.pinned(request['adapter_review'])
        ee=json.loads(run(EE_COMMAND,budget,maximum=8));save(output,'EE_source529.json',ee)
        request['EE_completion_receipt']=normalized_ee(ee,config['delivered_EE_report'],output)
        legacy=config.get('legacy_registries',[])
        if not legacy:raise Blocked('known legacy closed-scope registry locations are required')
        closure_hashes={};closure={}
        if config.get('known_legacy_closure_audit'):
            closure=cost.pinned(config['known_legacy_closure_audit'])
            if closure.get('status')!='PASS_CLOSED_CACHED_SCOPE_PRESERVED' or closure.get('errors'):
                raise Blocked('known legacy closure audit is not a successful retained scope proof')
            def collect_hashes(value):
                if isinstance(value,dict):
                    for key,item in value.items():
                        if key.startswith('/') and isinstance(item,str) and cost.SHA.fullmatch(item):closure_hashes[key]=item
                        collect_hashes(item)
                elif isinstance(value,list):
                    for item in value:collect_hashes(item)
            collect_hashes(closure)
        snapshots={}
        for host in (cost.OWNER,'jerez.be.ucsc.edu','hb.ucsc.edu'):
            registries=[entry for entry in legacy if entry['host']==host]
            if host==cost.OWNER:registries=registries+[{'path':str(cost.CENTRAL/'cost_only_registry.json'),'canonical_new_cost_registry':True}]
            location=config.get('legacy_outputs',{}).get(study)
            if isinstance(location,dict):location=location.get(host)
            spec={'exclusion_key':plan['claim']['scientific_exclusion_key'],'registries':registries,
                  'legacy_outputs':[location] if location and host!= 'hb.ucsc.edu' else [],
                  'slurm':host=='hb.ucsc.edu','disk_path':site['remote_root']}
            snapshot=observe(host,spec,site,budget);snapshots[host]=snapshot;save(output,host.split('.')[0]+'_observation.json',snapshot)
        overlap=[];unknown=[];absences=[]
        for host,snapshot in snapshots.items():
            overlap.extend(host+':pid'+str(x['pid']) for x in snapshot['matching_processes'])
            unknown.extend(host+':unreadable_pid'+str(x['pid']) for x in snapshot['unreadable_own_processes'])
            for item in snapshot['registries']:
                if item.get('output_descriptor_only'):
                    if not item.get('present'):
                        proof=never_admitted_absence(study,item['path'],plan,snapshots,closure,closure_hashes)
                        absences.append(dict(proof,host=host))
                    if any(name.startswith(('benchmark','tasks_done','components','claim')) for name in item.get('entries',[])):
                        unknown.append(host+':legacy_output_requires_review:'+item['path'])
                    continue
                if item['path'] in closure_hashes and item.get('sha256')!=closure_hashes[item['path']]:
                    raise Blocked('legacy registry differs from pinned closed-scope audit: '+item['path'])
                if item['path']==str(cost.CENTRAL/'cost_only_registry.json') and not item.get('present') and not item.get('error'):continue
                if item['path']==str(cost.CENTRAL/'cost_only_registry.json'):
                    central=item.get('value',{})
                    if central.get('schema')!=cost.SCHEMA or central.get('owner')!=cost.OWNER:raise Blocked('canonical cost registry identity differs')
                    if study in central.get('spent_regions',{}):overlap.append(host+':COST_STUDY_ALREADY_SPENT:'+study)
                overlap.extend(host+':'+x for x in registry_overlaps(item,plan['claim']['scientific_exclusion_key']))
        queue=snapshots['hb.ucsc.edu']['slurm']['queue']
        if queue.strip():overlap.extend('HBjob:'+line.split('|')[0] for line in queue.splitlines())
        if overlap or unknown:raise Blocked('overlap or unknown ownership: '+json.dumps(overlap+unknown))
        hosts=save(output,'all_hosts_observation.json',{'schema':'r156_hb_all_hosts_cost_observation_v1','status':'NO_OVERLAP',
            'controller':cost.OWNER,'hosts':sorted(cost.HOSTS),'observed_epoch':min(x['observed_epoch'] for x in snapshots.values()),
            'scientific_exclusion_key':plan['claim']['scientific_exclusion_key'],'overlapping_scientific_claims':[],
            'live_cost_jobs':[],'snapshots':{h:cost.pin(output/(h.split('.')[0]+'_observation.json')) for h in snapshots},
            'known_legacy_closure_audit':config.get('known_legacy_closure_audit'),
            'canonical_legacy_descriptor_absences':absences,
            'scope':'canonical cost ledger, configured legacy registries/output descriptors and matching own process labels; unrelated baseline preserved'})
        request['all_hosts_observation']=hosts
        sizing=cost.pinned(config['sizing_evidence'][study]);calendar=cost.pinned(config['calendar_evidence'][study])
        for proof in (sizing,calendar):
            if proof.get('study')!=study or proof.get('plan_sha256')!=plan_pin['sha256']:raise Blocked('sizing/calendar plan binding differs')
        if (calendar.get('status')!='PROPOSED_FINITE_COST_WINDOW_NOT_AUTHORITY' or calendar.get('authority_issued') is not False or
                calendar.get('claim_created') is not False or not cost.fresh({'observed_epoch':calendar.get('created_epoch')},time.time())):
            raise Blocked('fresh finite unclaimed calendar proposal required')
        hb=snapshots['hb.ucsc.edu'];node=fields(hb['slurm']['node']);partition=fields(hb['slurm']['partition'])
        available_memory=min(int(node['FreeMem']),int(node['RealMemory'])-int(node['AllocMem']))
        available_cpus=int(node.get('CPUEfctv',node['CPUTot']))-int(node['CPUAlloc'])
        if (node.get('NodeName')!='node-07' or any(flag in node.get('State','') for flag in ('DOWN','DRAIN','FAIL','MAINT')) or
                '128x24' not in node.get('Partitions','').split(',') or partition.get('State')!='UP' or duration(partition['MaxTime'])<1260):
            raise Blocked('node/partition is not currently eligible for the complete1200+60 window')
        admission={'schema':'r156_hb_cost_site_admission_v1','status':'ADMITTED_COST_ONLY_RESOURCES','study':study,
            'plan_sha256':plan_pin['sha256'],'account':site['account'],'partition':site['partition'],'qos':site['qos'],
            'node':'node-07','observed_epoch':hb['observed_epoch'],'memory_mib':sizing['memory_mib'],
            'minimum_required_memory_mib':sizing['minimum_required_memory_mib'],'maximum_parent_p':sizing['maximum_parent_p'],
            'available_memory_mib':available_memory,'available_cpus':available_cpus,'free_disk_bytes':hb['free_disk_bytes'],
            'calendar_expires_epoch':calendar['expires_epoch'],'sizing_evidence':config['sizing_evidence'][study],
            'calendar_evidence':config['calendar_evidence'][study],'observation':cost.pin(output/'hb_observation.json')}
        request['site_admission']=save(output,'site_admission.json',admission)
        cost.validate_gates(request,plan,plan_pin['sha256'])
        budget.check();request_pin=save(output,'launch-request.json',request)
        result.update(status='READY_FOR_PREPARE_ONLY_NOT_ADMITTED',request=request_pin,study=study,plan=plan_pin,
                      next_steps=['Run cost_control prepare-launch with this fresh request within300seconds; no authority or job is created here.'])
    except (OSError,ValueError,KeyError,TypeError,subprocess.SubprocessError) as exc:
        result['reason']=str(exc);result['next_steps']=['Resolve the reported missing, stale or conflicting observation and regenerate a new proof directory.']
    finally:
        signal.setitimer(signal.ITIMER_REAL,0);signal.signal(signal.SIGALRM,previous_alarm)
    result['observer_budget']=budget.receipt();result['completed_epoch']=time.time()
    save(output,'readiness-result.json',result)
    return result


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='action',required=True)
    for action in ('refresh','new-window'):
        command=sub.add_parser(action);command.add_argument('--plan',required=True);command.add_argument('--config',required=True);command.add_argument('--output',required=True)
        if action=='new-window':command.add_argument('--new-config',required=True);command.add_argument('--seconds',type=int,default=7200)
    argv=list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0].startswith('--'):argv.insert(0,'refresh')
    args=parser.parse_args(argv)
    result=(new_window(args.plan,args.config,args.output,args.new_config,args.seconds) if args.action=='new-window'
            else refresh(args.plan,args.config,args.output))
    print(json.dumps(result,sort_keys=True,allow_nan=False))
    return 0 if result['status'] in ('READY_FOR_PREPARE_ONLY_NOT_ADMITTED','PROPOSED_WINDOW_ONLY_NO_AUTHORITY_NO_CLAIM') else 2


if __name__=='__main__':raise SystemExit(main())
