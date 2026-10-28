"""Canonical Muscat scientific ledger and CLI for priced FI/DK2 HB prefixes.

Operational Slurm/activation/retrieval belongs to lifecycle.py. This ledger
separately conserves scientific CPU, complete-set decisions, three finite waves
and one explicitly reviewed replacement. It never mutates a legacy grant.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time
import uuid

from . import prefix as p, registry as r, control as ctl, cost_control as cost, policy

SCHEMA = "r157_hb_prefix_scientific_registry_v1"
MASTER_SCHEMA = "r157_hb_prefix_master_authority_v1"
WAVE_SCHEMA = "r157_hb_prefix_wave_authority_v1"
REVIEW_SCHEMA = "r157_hb_prefix_component_review_v1"
CENTRAL = p.bp.DATA / "hb_control_registry"
FINAL = {"COLLECTED_COMPONENT", "FAILED_COMPONENT_RECONCILED"}


def owner():
    if socket.getfqdn() != p.OWNER:
        raise p.PrefixError("only canonical Muscat owns prefix scientific claims")


def pin(path):
    path=r.no_links(path)
    return {"path":str(path),"sha256":r.digest(path)}


def pinned(value):
    return policy.pinned(value)


def create_only(path, value):
    path=r.no_links(path)
    if path.exists():raise FileExistsError("new immutable path required: "+str(path))
    path.parent.mkdir(parents=True,exist_ok=True);r.write(path,value)


def cost_basis(publication):
    """Require the real canonical successful cost claim and complete publication."""
    owner();publication=r.no_links(publication)
    ledger=r.read(CENTRAL/'cost_only_registry.json')
    claims=[v for v in ledger.get('claims',{}).values() if v.get('publication')==str(publication)]
    if len(claims)!=1 or claims[0].get('state')!='COLLECTED_COST_ONLY':
        raise p.PrefixError("one canonical accepted own-region cost publication required")
    claim=claims[0];release=cost.pinned_claim_release(claim)
    receipt=r.read(publication/'accounting.json')
    memory=release.get('memory_mib',release.get('resources',{}).get('memory_MiB'))
    if (receipt.get('task_key')!=claim.get('operational_task_key',claim['task_key']) or receipt.get('job_id')!=claim['job_id']
            or receipt.get('release_sha256')!=claim['release_sha256'] or receipt.get('squeue','').strip()
            or not cost.cost_accounting(receipt['sacct'],claim['job_id'],memory)['complete']
            or not cost.validate_results(publication/'outputs',claim,release)):
        raise p.PrefixError("complete scheduler/application cost acceptance required")
    plan_path=Path(claim['release_path'])/'plan.json';plan=r.read(plan_path)
    relative=Path('BENCHMARK_TEST')/release['study']/claim['task']['preparation_sha256'][:16]/claim['scope_id']
    result_path=publication/'outputs'/relative/'timings.json'
    return plan,r.read(result_path),pin(result_path),pin(publication/'accounting.json')


def create_plan(publication, destination):
    plan,timing,result_pin,accounting_pin=cost_basis(publication)
    value=p.build_plan(plan,timing,cost_publication=publication,cost_result_pin=result_pin,cost_accounting_pin=accounting_pin)
    claims=[v for v in r.read(CENTRAL/'cost_only_registry.json').get('claims',{}).values()
        if v.get('publication')==str(r.no_links(publication)) and v.get('state')=='COLLECTED_COST_ONLY']
    if len(claims)!=1:raise p.PrefixError('unique accepted original cost plan required')
    value['original_cost_plan']=pin(Path(claims[0]['release_path'])/'plan.json')
    if pinned(value['original_cost_plan'])!=plan:raise p.PrefixError('original cost plan bytes differ')
    create_only(destination,value)
    return {"status":"PRICED_NOT_ADMITTED","plan":pin(destination),"prefix_admitted_by_price":value['pricing']['prefix_admitted']}


def controller_price(price_pin, policy_packet):
    """Price the joint worst-case FI+DK2 administrative grid from measurements.

    This separate shared1800CPU pool never creates numerical authority and has
    no guessed per-task price. One5-case loss-blind measurement set must cover
    both complete component lifecycles, both assessment lifecycles, and joint
    preparation/cache/finalization. Replacement uses that region's full price.
    """
    if not isinstance(price_pin,dict):raise p.PrefixError('DEFERRED: explicit measured shared controller price required')
    value=pinned(price_pin)
    if (value.get('schema')!='r157_hb_prefix_controller_price_v1'
            or value.get('controller')!=p.OWNER or value.get('policy_scope_id')!=policy_packet['scope_id']
            or value.get('pool_id')!='r157-prefix-controller-'+policy_packet['scope_id']
            or value.get('ceiling_CPU_seconds')!=1800 or value.get('old_pool_reset') is not False
            or value.get('no_candidate_losses_used') is not True):
        raise p.PrefixError('explicit unchanged shared1800 controller pool and loss-blind price required')
    needed={'COMPONENT_LIFECYCLE_FI','COMPONENT_LIFECYCLE_DK2','ASSESSMENT_LIFECYCLE_FI',
        'ASSESSMENT_LIFECYCLE_DK2','JOINT_PREPARATION_CACHE_FINALIZATION'}
    measured={}
    for proof_pin in value.get('measurements',[]):
        proof=pinned(proof_pin);name=proof.get('operation')
        if (name not in needed or proof.get('status')!='ROOT_REVIEWED_MEASURED_CONTROLLER_OPERATION'
                or proof.get('controller')!=p.OWNER or proof.get('executed_sources')!=p.executed_sources()
                or proof.get('complete_operation_measured') is not True or proof.get('no_candidate_losses_used') is not True
                or proof.get('numerical_calls')!=0 or not p.finite(proof.get('aggregate_CPU_seconds'),positive=True)):
            raise p.PrefixError('complete source-bound loss-blind controller operation measurements required')
        measured[name]=max(measured.get(name,0),proof['aggregate_CPU_seconds'])
    if set(measured)!=needed:raise p.PrefixError('all five whole controller operation cases required')
    rates={name:math.ceil(1.5*amount) for name,amount in measured.items()}
    counts={'COMPONENT_LIFECYCLE_FI':88,'COMPONENT_LIFECYCLE_DK2':91,
        'ASSESSMENT_LIFECYCLE_FI':1,'ASSESSMENT_LIFECYCLE_DK2':1,'JOINT_PREPARATION_CACHE_FINALIZATION':1}
    total=sum(rates[name]*counts[name] for name in counts)
    return {'pool_id':value['pool_id'],'ceiling_CPU_seconds':1800,'rates':rates,'counts':counts,
        'whole_joint_grid_projected_CPU_seconds':total,'complete_joint_grid_fits':total<=1800,
        'contingency_factor':1.5,'old_pool_reset':False,'numerical_allowance_increased':False}


def draft_master(plan_path, policy_pin, *, expires_epoch, controller_price_pin=None, now=None):
    owner();now=time.time() if now is None else now
    plan=r.read(plan_path);p.validate_plan(plan)
    packet=policy.validate_policy(pinned(policy_pin),now=now)
    if not plan['pricing']['prefix_admitted']:
        raise p.PrefixError("full D/worst S0 price does not fit; no master admission")
    if not p.finite(expires_epoch,positive=True) or not now<expires_epoch<=min(now+43200,packet['expires_epoch']):
        raise p.PrefixError("finite new master must fit current policy and twelve-hour ceiling")
    control=controller_price(controller_price_pin,packet)
    if not control['complete_joint_grid_fits']:raise p.PrefixError('DEFERRED: complete joint controller grid exceeds shared1800CPU')
    return {"schema":MASTER_SCHEMA,"status":"DRAFT_NOT_ADMITTED","controller":p.OWNER,
        "scope_id":"r157-prefix-master-"+uuid.uuid4().hex,"study":plan['study'],"plan":pin(plan_path),
        "policy":policy_pin,"started_epoch":now,"expires_epoch":expires_epoch,
        "numerical_CPU_seconds":p.NUMERICAL_CPU_CEILING,"assessment_CPU_seconds":p.ASSESSMENT_CPU_CEILING,
        "max_waves":p.MAX_WAVES,"wave_lease_seconds":p.WAVE_LEASE,"wave_dispatch_seconds":p.WAVE_DISPATCH,
        "maximum_replacements":1,"executed_sources":p.executed_sources(),"authorization":None,
        'controller_price':controller_price_pin,'controller_pricing':control,
        "new_model_fits":0,"official_origins":0,"promotion_authorized":False,"automatic_retry":False,
        "old_qualifications_or_cost_attempts_refunded":False}


def validate_master(master, plan, *, now=None, require_admitted=True):
    now=time.time() if now is None else now
    wanted={'ADMITTED_COMPLETE_D_AND_WORST_S0_PREFIX'} if require_admitted else {'DRAFT_NOT_ADMITTED','ADMITTED_COMPLETE_D_AND_WORST_S0_PREFIX'}
    if (master.get('schema')!=MASTER_SCHEMA or master.get('status') not in wanted or master.get('controller')!=p.OWNER
            or master.get('study')!=plan['study'] or pinned(master.get('plan'))!=plan
            or master.get('numerical_CPU_seconds')!=32400 or master.get('assessment_CPU_seconds')!=1800
            or master.get('max_waves')!=3 or master.get('wave_lease_seconds')!=7200
            or master.get('wave_dispatch_seconds')!=5400 or master.get('maximum_replacements')!=1
            or master.get('executed_sources')!=p.executed_sources()
            or any(master.get(k) is not False for k in ('promotion_authorized','automatic_retry','old_qualifications_or_cost_attempts_refunded'))
            or master.get('new_model_fits')!=0 or master.get('official_origins')!=0):
        raise p.PrefixError("new exact fully priced source-bound prefix master required")
    start,end=master.get('started_epoch'),master.get('expires_epoch')
    if not p.finite(start) or not p.finite(end,positive=True) or not start<=now<end or not 0<end-start<=43200:
        raise p.PrefixError("new finite master clock is expired/invalid")
    packet=policy.validate_policy(pinned(master['policy']),now=now)
    control=controller_price(master.get('controller_price'),packet)
    if not control['complete_joint_grid_fits'] or master.get('controller_pricing')!=control:
        raise p.PrefixError('DEFERRED: exact measured joint controller price must fit shared1800CPU')
    if end>packet['expires_epoch']:raise p.PrefixError("master outlives explicit policy")
    if require_admitted:
        auth=pinned(master.get('authorization'));draft=dict(master,status='DRAFT_NOT_ADMITTED',authorization=None)
        if (auth.get('status')!='ROOT_REVIEWED_CACHED_NORMAL_PREFIX_AUTHORIZATION'
                or auth.get('master_draft_sha256')!=r.identity(draft) or auth.get('controller')!=p.OWNER
                or auth.get('actual_cost_publication_accepted') is not True or auth.get('user_requested_implementation') is not True
                or auth.get('all_original_scientific_bounds_preserved') is not True):
            raise p.PrefixError("independently reviewed complete master authorization required")
    return master


def adopt_master(draft, authorization_pin, plan):
    owner();validate_master(draft,plan,require_admitted=False)
    value=dict(draft,status='ADMITTED_COMPLETE_D_AND_WORST_S0_PREFIX',authorization=authorization_pin)
    validate_master(value,plan);return value


def empty():
    return {"schema":SCHEMA,"owner":p.OWNER,"studies":{},"operational_tasks":{},"policy":None,'controller_pool':None}


def budget_view(study):
    """Failed/unknown attempts retain full reservation; successful actual CPU is source-verified."""
    active=failed=completed=reserved_ever=0.0
    for claim in study['claims'].values():
        amount=claim['reserved_CPU_seconds'];reserved_ever+=amount
        if claim['state']=='COLLECTED_COMPONENT':completed+=claim['charged_CPU_seconds']
        elif claim['state']=='FAILED_COMPONENT_RECONCILED':failed+=max(amount,claim.get('charged_CPU_seconds',amount))
        else:active+=amount
    total=active+failed+completed
    return {"numerical_CPU_ceiling":32400,"active_reservations_CPU_seconds":active,
        "completed_charged_CPU_seconds":completed,"failed_spent_CPU_seconds":failed,
        "all_reservations_ever_CPU_seconds":reserved_ever,"conservatively_charged_CPU_seconds":total,
        "remaining_numerical_CPU_seconds":max(0.0,32400-total),"failed_attempts_refunded":False}


def active_count(state):
    return sum(c['state'] not in FINAL for e in state['studies'].values() for c in e['claims'].values()) + sum(
        bool(e.get('assessment')) and e['assessment']['state'] not in FINAL for e in state['studies'].values())


class Ledger:
    def __init__(self, root=None):
        owner();self.root=r.no_links(CENTRAL if root is None else root)
        if self.root!=r.no_links(CENTRAL):raise p.PrefixError("canonical Muscat prefix registry required")
        self.root.mkdir(parents=True,exist_ok=True)
        self.path=self.root/'prefix_registry.json';self.lock=self.root/'prefix_registry.lock'
    def _read(self):
        value=r.read(self.path) if self.path.exists() else empty()
        if value.get('schema')!=SCHEMA or value.get('owner')!=p.OWNER:raise p.PrefixError("prefix registry identity differs")
        return value
    def snapshot(self):
        with r.lock(self.lock):return self._read()
    def admit(self, plan_path, master_path):
        plan=r.read(plan_path);p.validate_plan(plan);master=r.read(master_path);validate_master(master,plan)
        # Recheck the true original cost acceptance before the first scientific journal write.
        c,t,_,_=cost_basis(plan['cost_publication'])
        if c!=plan['cost_plan'] or p.price_prefix(c,t)!=plan['pricing']:
            raise p.PrefixError("canonical cost lineage differs from proposed study")
        with r.lock(self.lock):
            state=self._read();study=plan['study']
            if study in state['studies']:raise p.PrefixError("study already admitted/spent; no reset")
            if state['policy'] is not None and state['policy']!=master['policy']:
                raise p.PrefixError("shared current resource policy differs")
            state['policy']=master['policy']
            pool={'price':master['controller_price'],'pricing':master['controller_pricing']}
            if state.get('controller_pool') not in (None,pool):raise p.PrefixError('FI+DK2 must share one unchanged controller pool')
            state['controller_pool']=pool
            state['studies'][study]={"plan":pin(plan_path),"master":pin(master_path),"scope_id":master['scope_id'],
                "waves":{},"claims":{},"results":{},"decisions":{},"replacements_used":0,"assessment":None}
            r.write(self.path,state)
            return {"status":"ADMITTED_CACHED_NORMAL_STUDY","study":study,"scope_id":master['scope_id']}
    def current(self, study, *, reconciliation=False):
        state=self.snapshot();entry=state['studies'][study]
        plan=pinned(entry['plan']);master=pinned(entry['master'])
        # Publication may finish after a finite scheduling clock. Reconcile
        # against the original immutable admission instant, without renewing it.
        epoch=master['started_epoch'] if reconciliation else time.time()
        validate_master(master,plan,now=epoch)
        p.validate_plan(plan)
        active=policy.validate_policy(pinned(state['policy']),now=epoch)
        return state,entry,plan,master,active
    def set_policy(self, new_pin):
        owner();new=policy.validate_policy(pinned(new_pin))
        with r.lock(self.lock):
            state=self._read();old=policy.validate_policy(pinned(state['policy']))
            unchanged=('scope_id','created_epoch','expires_epoch','legacy_contract','legacy_resource_policy','local_permit','execution_sources')
            if any(old[k]!=new[k] for k in unchanged) or new['scale_amendments'][:len(old['scale_amendments'])]!=old['scale_amendments']:
                raise p.PrefixError("scale cannot renew clocks, alter local permit or replace source")
            if new['HB_max_workers']<old['HB_max_workers']:raise p.PrefixError("scale contraction needs explicit drain disposition")
            state['policy']=new_pin;r.write(self.path,state);return {'status':'RESOURCE_POLICY_UPDATED','HB_max_workers':new['HB_max_workers']}
    def open_wave(self, study, wave_authority_path):
        _,_,plan,master,_=self.current(study);value=r.read(wave_authority_path);now=time.time()
        if (value.get('schema')!=WAVE_SCHEMA or value.get('status')!='ROOT_ADMITTED_FINITE_PREFIX_WAVE'
                or value.get('controller')!=p.OWNER or value.get('study')!=study
                or value.get('master')!=self.snapshot()['studies'][study]['master']
                or not p.finite(value.get('started_epoch')) or not p.finite(value.get('expires_epoch'))
                or not value['started_epoch']<=now<value['expires_epoch']<=master['expires_epoch']
                or not 0<value['expires_epoch']-value['started_epoch']<=7200
                or value.get('dispatch_expires_epoch')!=value['started_epoch']+5400
                or value.get('automatic_retry') is not False):
            raise p.PrefixError("new reviewed original-size wave authority required")
        with r.lock(self.lock):
            state=self._read();entry=state['studies'][study]
            if len(entry['waves'])>=3 or value['wave_id'] in entry['waves']:raise p.PrefixError("three-wave allowance exhausted or duplicate wave")
            if any(c['state'] not in FINAL for c in entry['claims'].values()):raise p.PrefixError("prior wave has unresolved scientific work")
            entry['waves'][value['wave_id']]={"authority":pin(wave_authority_path),"opened_epoch":now,"claims":[]}
            r.write(self.path,state);return value
    def advance(self, study):
        _,_,plan,_,_=self.current(study)
        prep,config=p.metadata(plan['cost_plan'])
        with r.lock(self.lock):
            state=self._read();entry=state['studies'][study];view=budget_view(entry)
            charges={name:{'charged_CPU_seconds':v['charged_CPU_seconds']} for name,v in entry['results'].items()}
            phase=p.manifest_state(prep,plan['pricing'],entry['results'],entry['decisions'])
            charges={n:charges[n] for n in phase['required'] if n in charges}
            key,value=p.advance_decision(prep,config,plan['pricing'],entry['results'],entry['decisions'],
                view['remaining_numerical_CPU_seconds'],charges)
            if key in entry['decisions']:raise p.PrefixError("scientific decision already frozen")
            entry['decisions'][key]=value;r.write(self.path,state);return {key:value}
    def queue(self, study):
        _,entry,plan,_,active=self.current(study);prep,_=p.metadata(plan['cost_plan'])
        value=p.manifest_state(prep,plan['pricing'],entry['results'],entry['decisions'])
        occupied={c['task'] for c in entry['claims'].values()}
        value.update(ready=[n for n in value['pending'] if n not in value['unfunded'] and n not in occupied],
            explicit_replacement_candidates=[c['task_key'] for c in entry['claims'].values()
                if c['state']=='FAILED_COMPONENT_RECONCILED' and c['task'] in value['pending']]
                if entry['replacements_used']==0 else [],
            budget=budget_view(entry),HB_max_workers=active['HB_max_workers'],new_model_fits=0)
        return value


def calendar_observation(study, output, *, wave_id=None):
    """Observe an existing finite authority; never create or extend a clock."""
    owner();ledger=Ledger();_,entry,plan,master,_=ledger.current(study)
    if not entry['waves']:raise p.PrefixError('an already admitted finite wave is required')
    wave_id=wave_id or next(reversed(entry['waves']))
    if wave_id not in entry['waves']:raise p.PrefixError('unknown canonical prefix wave')
    wave_pin=entry['waves'][wave_id]['authority'];wave=pinned(wave_pin);now=time.time()
    if not wave['started_epoch']<=now<min(wave['dispatch_expires_epoch'],wave['expires_epoch']):
        raise p.PrefixError('existing prefix wave is closed for dispatch')
    original=plan.get('original_cost_plan')
    if not isinstance(original,dict) or pinned(original)!=plan['cost_plan']:
        raise p.PrefixError('exact accepted original cost plan pin required')
    value={'schema':'r157_hb_prefix_calendar_observation_v1','status':'OBSERVED_ACTIVE_IMMUTABLE_PREFIX_CALENDAR',
        'controller':p.OWNER,'study':study,'resource_plan_sha256':original['sha256'],
        'execution_plan_sha256':entry['plan']['sha256'],'execution_plan_pin':entry['plan'],
        'original_cost_plan':original,'master':entry['master'],'wave':wave_pin,
        'observed_epoch':now,'started_epoch':wave['started_epoch'],'expires_epoch':wave['expires_epoch'],
        'dispatch_expires_epoch':wave['dispatch_expires_epoch'],'master_expires_epoch':master['expires_epoch'],
        'expires_reset':False,'new_authority_created':False}
    create_only(output,value);return value


def validate_calendar_observation(value, execution_plan_pin, resource_plan_pin, *, allow_stale=False):
    owner();now=time.time();plan=pinned(execution_plan_pin)
    _,entry,current,master,_=Ledger().current(plan['study'])
    observed=value.get('observed_epoch')
    if (value.get('schema')!='r157_hb_prefix_calendar_observation_v1'
            or value.get('status')!='OBSERVED_ACTIVE_IMMUTABLE_PREFIX_CALENDAR' or value.get('controller')!=p.OWNER
            or value.get('study')!=plan['study'] or entry['plan']!=execution_plan_pin or current!=plan
            or value.get('execution_plan_pin')!=execution_plan_pin
            or value.get('execution_plan_sha256')!=execution_plan_pin['sha256']
            or value.get('resource_plan_sha256')!=resource_plan_pin.get('sha256')
            or value.get('original_cost_plan')!=plan.get('original_cost_plan')
            or plan.get('original_cost_plan',{}).get('sha256')!=resource_plan_pin.get('sha256')
            or pinned(resource_plan_pin)!=plan['cost_plan'] or value.get('master')!=entry['master']
            or value.get('expires_reset') is not False or value.get('new_authority_created') is not False
            or not p.finite(observed) or observed>now or (not allow_stale and now-observed>300)):
        raise p.PrefixError('fresh observation must bind the same canonical immutable prefix calendar')
    wave_pin=value.get('wave')
    if not any(v['authority']==wave_pin for v in entry['waves'].values()):raise p.PrefixError('unknown observed prefix wave')
    wave=pinned(wave_pin)
    if (value.get('started_epoch')!=wave['started_epoch'] or value.get('expires_epoch')!=wave['expires_epoch']
            or value.get('dispatch_expires_epoch')!=wave['dispatch_expires_epoch']
            or value.get('master_expires_epoch')!=master['expires_epoch']
            or not wave['started_epoch']<=now<wave['expires_epoch']<=master['expires_epoch']
            or (not allow_stale and now>=wave['dispatch_expires_epoch'])):
        raise p.PrefixError('observation cannot renew or reopen its admitted wave')
    return value


def stage_original_inputs(plan, destination):
    """The complete original source/input/opaque-parent allowlist is retained."""
    destination=Path(destination);stage=destination/'stage'
    for logical,asset in plan['cost_plan']['input_allowlist'].items():
        src=r.no_links(logical);rel=Path(asset['staged_relative_path'])
        if rel.is_absolute() or '..' in rel.parts or rel!=Path('files')/src.relative_to('/'):
            raise p.PrefixError("unsafe original staging member")
        if {'.ssh','.git','.codex'} & set(src.parts):raise p.PrefixError("private/Git directories excluded")
        if src.stat().st_size!=asset['bytes'] or r.digest(src)!=asset['sha256']:raise p.PrefixError("original input changed")
        target=stage/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,target)
        if r.digest(target)!=asset['sha256']:raise p.PrefixError("copied scientific input differs")
    timing=destination/plan['cost_result_staged_relative_path'];timing.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(plan['cost_result']['path'],timing)
    if r.digest(timing)!=plan['cost_result']['sha256']:raise p.PrefixError("original cost evidence changed")


def request_proofs(destination, request, metadata_pins):
    from . import lifecycle
    roots={name:request[name] for name in ('runtime_result','runtime_qualification_seal','runtime_accounting',
        'parity_result','parity_seal','parity_runtime_result','parity_qualification_seal','parity_accounting',
        'policy_pin','handoff_receipt','all_hosts_observation','site_admission','adapter_review') if name in request}
    manifest=lifecycle.pack_proofs(destination,roots)
    for name,logical_pin in metadata_pins:
        target=Path(destination)/name
        if r.digest(target)!=logical_pin['sha256']:raise p.PrefixError('staged authority metadata changed')
        manifest[logical_pin['path']]={'relative_path':name,'sha256':logical_pin['sha256'],'bytes':target.stat().st_size}
    return manifest


def prepare_component_release(plan_path, master_path, wave_path, task_name, request_path, config_path, destination, *, replacement_of=None, cache_receipt=None):
    """Copy immutable original inputs before any scientific claim or network."""
    owner();ledger=Ledger();state,entry,plan,master,active=ledger.current(r.read(plan_path)['study'])
    if entry['plan']!=pin(plan_path) or entry['master']!=pin(master_path):raise p.PrefixError("admitted study identity differs")
    wave=r.read(wave_path)
    if wave['wave_id'] not in entry['waves'] or entry['waves'][wave['wave_id']]['authority']!=pin(wave_path):
        raise p.PrefixError("known finite wave required")
    prep,_=p.metadata(plan['cost_plan']);task=next((v for v in prep['tasks'] if v['name']==task_name),None)
    queue=ledger.queue(plan['study'])
    if task is None or task_name not in queue['pending'] or task_name in queue['unfunded']:
        raise p.PrefixError("task outside funded fixed current stage")
    previous=[v for v in entry['claims'].values() if v['task']==task_name]
    if previous:
        if (len(previous)!=1 or previous[0]['task_key']!=replacement_of
                or previous[0]['state']!='FAILED_COMPONENT_RECONCILED' or entry['replacements_used']!=0):
            raise p.PrefixError('duplicate task requires one explicit terminal replacement')
    elif replacement_of:raise p.PrefixError('unknown replacement lineage')
    price=plan['pricing']['task_estimates'][task_name]
    now=time.time();wall=math.ceil(price['estimated_wall_seconds']);cpu=math.ceil(price['estimated_cpu_seconds'])
    end=min(master['expires_epoch'],wave['expires_epoch'])
    max_queue=min(1800,math.floor(end-now-wall-60))
    if now>=wave['dispatch_expires_epoch'] or max_queue<1 or wall>5400 or cpu<=0 or cpu>wall:
        raise p.PrefixError("entire priced component/queue/drain cannot fit this wave")
    request=r.read(request_path);c=ctl.config(config_path)
    from . import lifecycle
    gate=lifecycle.validate_request(request)
    if request.get('execution_plan_sha256')!=r.digest(plan_path):
        raise p.PrefixError("fresh operational request refers to another plan")
    if (request.get('purpose')!='CACHED_NORMAL_COMPONENT'
            or request.get('scientific_exclusion_key')!=plan['cost_plan']['claim']['scientific_exclusion_key']+'|'+task_name):
        raise p.PrefixError('fresh request must bind this exact component exclusion key')
    # Root lifecycle performs full positive admission before any operational claim.
    node=gate['site']['node'];memory=gate['site']['memory_mib']
    runtime=request.get('runtime_python')
    if not isinstance(runtime,str) or not runtime.startswith('/mnt/beegfs/home/jaguir26/'):
        raise p.PrefixError("qualified physical runtime path required")
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError("fresh component release required")
    destination.mkdir(parents=True);shutil.copyfile(plan_path,destination/'plan.json')
    shutil.copyfile(master_path,destination/'master.json');shutil.copyfile(wave_path,destination/'wave.json')
    shutil.copyfile(request_path,destination/'launch-request.json')
    stage_original_inputs(plan,destination)
    create_only(destination/'component.json',task)
    backend={"study":plan['study'],"study_key":entry['scope_id'],"wave_key":wave['wave_id'],"component_name":task_name,
        "task_sha256":r.identity(task),"scientific_identity_sha256":task['scientific_identity_sha256'],
        "plan_path":str(r.no_links(plan_path)),"master":entry['master'],"wave":pin(wave_path),
        "price_reservation":price['estimated_cpu_seconds'],"replacement_of":replacement_of,
        "calendar_expires_epoch":end,"dispatch_expires_epoch":wave['dispatch_expires_epoch'],"max_queue_seconds":max_queue}
    backend.update(controller_CPU_pool=master['controller_pricing']['pool_id'],controller_CPU_ceiling=1800,
        controller_CPU_reservation=master['controller_pricing']['rates']['COMPONENT_LIFECYCLE_'+plan['study']],
        controller_price=master['controller_price'],controller_whole_grid_CPU_seconds=master['controller_pricing']['whole_joint_grid_projected_CPU_seconds'])
    if 'control_operation_price' in request:backend['operation_price_pin']=request['control_operation_price']
    if cache_receipt:
        cache=validate_cache_receipt(cache_receipt,plan_path,c)
        backend['rsync_link_dest']=cache['remote_root'];backend['shared_cache_receipt']=pin(cache_receipt)
    key=r.identity({'study':plan['study'],'scope_id':entry['scope_id'],'task':task_name,'replacement_of':replacement_of})
    backend['authority_fields']=lifecycle_authority_fields({'backend':backend,'purpose':'CACHED_NORMAL_COMPONENT'})
    create_only(destination/'preparation.json',{'remote_base':c['remote_root'],
        'scope_id':master['scope_id']+'-'+key[:12],'environment_bundle':request['environment_bundle'],
        'purpose':'CACHED_NORMAL_COMPONENT'})
    manifest=request_proofs(destination,request,[('master.json',entry['master']),('wave.json',pin(wave_path))])
    return lifecycle.seal_release(destination,purpose='CACHED_NORMAL_COMPONENT',study=plan['study'],task_key=key,
        scientific_exclusion_key=plan['cost_plan']['claim']['scientific_exclusion_key']+'|'+task_name,
        plan_sha256=r.digest(plan_path),resources={'cpus':1,'memory_MiB':memory,'wall_seconds':wall,'cpu_seconds':cpu},
        runtime_python=runtime,node=node,policy_pin=state['policy'],proof_manifest=manifest,backend=backend)


def prepare_assessment_release(plan_path, master_path, request_path, config_path, destination):
    """Freeze collected component bytes and decisions for independent replay."""
    owner();ledger=Ledger();state,entry,plan,master,_=ledger.current(r.read(plan_path)['study'])
    if entry['plan']!=pin(plan_path) or entry['master']!=pin(master_path):raise p.PrefixError('known immutable study required')
    queue=ledger.queue(plan['study'])
    if not queue['assessment_ready'] or entry['assessment'] is not None:
        raise p.PrefixError('complete scientific state and unspent assessment allowance required')
    from . import lifecycle
    request=r.read(request_path);gate=lifecycle.validate_request(request);c=ctl.config(config_path)
    exclusion=plan['cost_plan']['claim']['scientific_exclusion_key']+'|ASSESSMENT'
    if (request.get('purpose')!='PREFIX_ASSESSMENT' or request.get('scientific_exclusion_key')!=exclusion
            or request.get('execution_plan_sha256')!=r.digest(plan_path)):
        raise p.PrefixError('exact fresh assessment request required')
    now=time.time();end=master['expires_epoch'];queue_seconds=min(1800,math.floor(end-now-1800-60))
    if queue_seconds<1:raise p.PrefixError('whole assessment/queue/drain does not fit original master')
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('fresh independent assessment release required')
    destination.mkdir(parents=True)
    for src,name in [(plan_path,'plan.json'),(master_path,'master.json'),(request_path,'launch-request.json')]:shutil.copyfile(src,destination/name)
    stage_original_inputs(plan,destination)
    snapshot={'schema':'r157_hb_prefix_assessment_snapshot_v1','study':plan['study'],'plan_sha256':r.digest(plan_path),
        'master':entry['master'],'results':entry['results'],'decisions':entry['decisions'],
        'scientific_ledger_snapshot_sha256':r.identity(entry),'immutable_original_failures_preserved':True}
    create_only(destination/'assessment_snapshot.json',snapshot)
    for name,record in entry['results'].items():
        original=Path(record['publication'])/'outputs'/'PREFIX_TRAINING'/plan['study']/name
        if pin(original/'result.json')!=record['result_pin'] or pin(original/'completed_evidence.json')!=record['seal_pin']:
            raise p.PrefixError('canonical component publication changed')
        shutil.copytree(ctl.safe_tree(original),destination/'components'/name)
    key=r.identity({'study':plan['study'],'scope_id':master['scope_id'],'kind':'ASSESSMENT'})
    backend={'study':plan['study'],'study_key':master['scope_id'],'kind':'assessment','master':entry['master'],
        'plan_path':str(r.no_links(plan_path)),'assessment_snapshot_sha256':r.digest(destination/'assessment_snapshot.json'),
        'calendar_expires_epoch':end,'dispatch_expires_epoch':end-1800-60,'max_queue_seconds':queue_seconds}
    backend.update(controller_CPU_pool=master['controller_pricing']['pool_id'],controller_CPU_ceiling=1800,
        controller_CPU_reservation=master['controller_pricing']['rates']['ASSESSMENT_LIFECYCLE_'+plan['study']],
        controller_price=master['controller_price'],controller_whole_grid_CPU_seconds=master['controller_pricing']['whole_joint_grid_projected_CPU_seconds'])
    if 'control_operation_price' in request:backend['operation_price_pin']=request['control_operation_price']
    backend['authority_fields']=lifecycle_authority_fields({'purpose':'PREFIX_ASSESSMENT','backend':backend})
    create_only(destination/'preparation.json',{'remote_base':c['remote_root'],'scope_id':master['scope_id']+'-assessment',
        'environment_bundle':request['environment_bundle'],'purpose':'PREFIX_ASSESSMENT'})
    manifest=request_proofs(destination,request,[('master.json',entry['master'])])
    return lifecycle.seal_release(destination,purpose='PREFIX_ASSESSMENT',study=plan['study'],task_key=key,
        scientific_exclusion_key=exclusion,plan_sha256=r.digest(plan_path),resources={'cpus':1,
        'memory_MiB':gate['site']['memory_mib'],'wall_seconds':1800,'cpu_seconds':1800},runtime_python=request['runtime_python'],
        node=gate['site']['node'],policy_pin=state['policy'],proof_manifest=manifest,backend=backend)


def lifecycle_reserve(release, release_path, config):
    """Called only after the global operational claim is durably recorded."""
    owner();ledger=Ledger();backend=release.get('backend',{});study=release['study'];now=time.time()
    _,entry,plan,master,active=ledger.current(study);prep,_=p.metadata(plan['cost_plan'])
    if (release.get('plan_sha256')!=entry['plan']['sha256'] or backend.get('plan_path')!=entry['plan']['path']
            or backend.get('master')!=entry['master'] or backend.get('study_key')!=entry['scope_id']
            or release.get('policy_pin')!=ledger.snapshot()['policy']):
        raise p.PrefixError('release does not bind the admitted immutable study/master/policy')
    operation=('ASSESSMENT_LIFECYCLE_' if release.get('purpose')=='PREFIX_ASSESSMENT' else 'COMPONENT_LIFECYCLE_')+study
    control=master['controller_pricing']
    if (backend.get('controller_CPU_pool')!=control['pool_id'] or backend.get('controller_CPU_ceiling')!=1800
            or backend.get('controller_price')!=master['controller_price']
            or backend.get('controller_CPU_reservation')!=control['rates'][operation]
            or backend.get('controller_whole_grid_CPU_seconds')!=control['whole_joint_grid_projected_CPU_seconds']):
        raise p.PrefixError('release controller reservation must use the measured shared joint price')
    if release.get('purpose')=='PREFIX_ASSESSMENT':
        return reserve_assessment(ledger,release,release_path,plan,master,active)
    task=next(t for t in prep['tasks'] if t['name']==backend.get('component_name'))
    if (release.get('purpose')!='CACHED_NORMAL_COMPONENT' or release.get('plan_sha256')!=r.digest(backend['plan_path'])
            or backend.get('task_sha256')!=r.identity(task)):
        raise p.PrefixError("operational claim differs from reviewed scientific component")
    with r.lock(ledger.lock):
        state=ledger._read();entry=state['studies'][study];key=release['task_key']
        if key in state['operational_tasks']:raise p.PrefixError("component operational task already spent")
        wave_entry=entry['waves'][backend['wave_key']];wave=pinned(wave_entry['authority'])
        if now>=wave['dispatch_expires_epoch'] or now>=wave['expires_epoch']:raise p.PrefixError("wave dispatch closed")
        phase=p.manifest_state(prep,plan['pricing'],entry['results'],entry['decisions'])
        if task['name'] not in phase['pending'] or task['name'] in phase['unfunded']:
            raise p.PrefixError("component is not funded/ready in the fixed scientific stage")
        previous=[c for c in entry['claims'].values() if c['task']==task['name']]
        replacement=backend.get('replacement_of')
        if previous:
            if (not replacement or len(previous)!=1 or previous[0]['task_key']!=replacement
                    or previous[0]['state']!='FAILED_COMPONENT_RECONCILED' or entry['replacements_used']>=1):
                raise p.PrefixError("duplicate task; one explicit reviewed terminal replacement only")
        elif replacement:raise p.PrefixError("unknown replacement lineage")
        running=active_count(state)
        if running>=active['HB_max_workers']:raise p.PrefixError("aggregate admitted HB concurrency exhausted")
        reservation=release['resources']['cpu_seconds']
        if reservation!=plan['pricing']['rounded_task_CPU_reservations'][task['name']]:
            raise p.PrefixError('SlurmCPU reservation differs from complete prepriced integer cap')
        view=budget_view(entry)
        if not p.finite(reservation,positive=True) or reservation>view['remaining_numerical_CPU_seconds']:
            raise p.PrefixError("whole component reservation cannot fit remaining32400CPU")
        # The fixed one-replacement reserve is protected from ordinary components.
        reserve=plan['pricing']['rounded_replacement_CPU_reservation'] if not entry['replacements_used'] and not replacement else 0
        if reservation+reserve>view['remaining_numerical_CPU_seconds']:
            raise p.PrefixError("component would consume the protected priced replacement reserve")
        if previous:entry['replacements_used']+=1
        record={'task_key':key,'task':task['name'],'state':'RESERVED','reserved_CPU_seconds':reservation,
            'wave_key':backend['wave_key'],'release_path':str(Path(release_path).absolute()),
            'release_sha256':r.digest(Path(release_path)/'release.json'),'resources':release['resources'],
            'replacement_of':replacement,'created_epoch':now,'charged_CPU_seconds':None}
        entry['claims'][key]=record;wave_entry['claims'].append(key);state['operational_tasks'][key]=study
        r.write(ledger.path,state);return record


def reserve_assessment(ledger, release, release_path, plan, master, active):
    backend=release.get('backend',{});study=plan['study'];now=time.time()
    if (backend.get('kind')!='assessment' or release.get('plan_sha256')!=r.digest(backend['plan_path'])
            or backend.get('assessment_snapshot_sha256')!=r.digest(Path(release_path)/'assessment_snapshot.json')
            or release['resources'].get('cpu_seconds')!=1800 or release['resources'].get('wall_seconds')!=1800
            or now+1800+60>=master['expires_epoch']):
        raise p.PrefixError('complete original-size separately funded assessment required')
    with r.lock(ledger.lock):
        state=ledger._read();entry=state['studies'][study];key=release['task_key']
        if entry['assessment'] is not None or key in state['operational_tasks']:
            raise p.PrefixError('assessment attempt already spent; no retry/refund')
        phase=p.manifest_state(plan['scientific_manifest'],plan['pricing'],entry['results'],entry['decisions'])
        if not phase['assessment_ready']:raise p.PrefixError('partial scientific set cannot be assessed')
        if active_count(state)>=active['HB_max_workers']:raise p.PrefixError('aggregate HB capacity exhausted')
        record={'task_key':key,'task':'__assessment__','state':'RESERVED','reserved_CPU_seconds':1800,
            'release_path':str(Path(release_path).absolute()),'release_sha256':r.digest(Path(release_path)/'release.json'),
            'resources':release['resources'],'created_epoch':now,'charged_CPU_seconds':None}
        entry['assessment']=record;state['operational_tasks'][key]=study;r.write(ledger.path,state);return record


def lifecycle_authority_fields(release):
    backend=release['backend']
    if release.get('purpose')=='PREFIX_ASSESSMENT':
        return {'status':'ADMITTED_PREFIX_ASSESSMENT','assessment_snapshot_sha256':backend['assessment_snapshot_sha256'],
            'promotion_authorized':False,'new_model_fits':0,'official_origins':0,'automatic_retry':False,
            'master':backend['master'],'calendar_expires_epoch':backend['calendar_expires_epoch'],
            'max_queue_seconds':backend['max_queue_seconds']}
    return {'schema':p.AUTHORITY_SCHEMA,'status':'ADMITTED_CACHED_NORMAL_COMPONENT','task':backend['component_name'],
        'task_sha256':backend['task_sha256'],'scientific_identity_sha256':backend['scientific_identity_sha256'],
        'promotion_authorized':False,'new_model_fits':0,'official_origins':0,'automatic_retry':False,
        'master':backend['master'],'wave':backend['wave'],'calendar_expires_epoch':backend['calendar_expires_epoch'],
        'max_queue_seconds':backend['max_queue_seconds']}


def verify_component(outputs, plan, task, *, expected_execution=None, resolver=None):
    outputs=ctl.safe_tree(outputs);seal=r.read(outputs/'completed_evidence.json')
    if seal.get('status')!='COMPLETE_CACHED_NORMAL_COMPONENT_NOT_PROMOTED' or seal.get('certified') is not True:
        raise p.PrefixError("complete certified component seal required")
    if expected_execution is not None and seal.get('execution')!=expected_execution:
        raise p.PrefixError("component execution identity differs")
    found={str(q.relative_to(outputs)) for q in outputs.rglob('*') if q.is_file() and q!=outputs/'completed_evidence.json'}
    if found!=set(seal['artifacts']):raise p.PrefixError("partial/unsealed component outputs")
    for name,sha in seal['artifacts'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts or r.digest(outputs/name)!=sha:raise p.PrefixError("component artifact changed")
    result=r.read(outputs/'result.json');execution=r.read(outputs/'execution_identity.json')
    if (execution!=seal.get('execution') or execution.get('namespace')!='PREFIX_TRAINING'
            or execution.get('task')!=task['name'] or execution.get('task_sha256')!=r.identity(task)
            or execution.get('original_scientific_source')!=plan['scientific_manifest']['source']
            or execution.get('executed_sources')!=p.executed_sources()
            or execution.get('new_model_fits')!=0 or execution.get('official_origins')!=0):
        raise p.PrefixError("component result/outer execution differs")
    if (result.get('schema')!=p.RESULT_SCHEMA or result.get('name')!=task['name']
            or result.get('scientific_identity_sha256')!=task['scientific_identity_sha256']
            or result.get('task_sha256')!=r.identity(task) or result.get('source')!=plan['scientific_manifest']['source']
            or result.get('mode')!=task['mode'] or result.get('units')!='EUR/MWh'
            or result.get('origin_clock_windows')!=4*len(task['daily_origin_positions'])
            or result.get('new_model_fits')!=0 or result.get('posterior_updated') is not False
            or result.get('test_opened') is not False or result.get('promotion_authorized') is not False
            or not result.get('numerical_threadpools') or any(q.get('num_threads')!=1 for q in result['numerical_threadpools'])
            or not p.finite(result.get('metrics',{}).get('AQL'))):
        raise p.PrefixError("component scope/cohort/source/metrics differs")
    descriptors=p.original('chunks',resolver=resolver)(task)
    if result.get('chunk_count')!=len(descriptors):raise p.PrefixError("all original four-clock chunks required")
    prep=plan['scientific_manifest'];context=p.original('context_identity',resolver=resolver)(task,prep)
    if seal.get('context')!=context:raise p.PrefixError("original scientific context differs")
    for descriptor in descriptors:
        folder=outputs/'checkpoints'/descriptor['name'];chunk=r.read(folder/'completed_evidence.json')
        if chunk.get('identity')!={'context':context,'descriptor':descriptor} or chunk.get('certified') is not True:
            raise p.PrefixError("chunk identity/clock/origin differs")
        if set(chunk.get('artifacts',{}))!={'chunk.json','predictions.npz'}:
            raise p.PrefixError("complete original retained chunk required")
        for name,sha in chunk['artifacts'].items():
            if r.digest(folder/name)!=sha:raise p.PrefixError("chunk bytes changed")
    return result


def lifecycle_complete(task_key, result, publication, accounting):
    """Strict result/accounting callback after operational atomic publication."""
    owner();ledger=Ledger();state=ledger.snapshot();study=state['operational_tasks'][task_key]
    _,entry,plan,_,_=ledger.current(study,reconciliation=True)
    if entry.get('assessment') and entry['assessment']['task_key']==task_key:
        return complete_assessment(ledger,study,entry,plan,task_key,result,publication,accounting)
    claim=entry['claims'][task_key]
    release=r.read(Path(claim['release_path'])/'release.json')
    if r.digest(Path(claim['release_path'])/'release.json')!=claim['release_sha256']:
        raise p.PrefixError("scientific claim release changed")
    accepted=isinstance(result,dict) and result.get('application_passed') is True
    charge=claim['reserved_CPU_seconds'];component=None
    if accepted:
        task=next(t for t in plan['scientific_manifest']['tasks'] if t['name']==claim['task'])
        output=Path(publication)/'outputs'/'PREFIX_TRAINING'/study/task['name']
        component=verify_component(output,plan,task)
        execution=r.read(output/'execution_identity.json')
        if (execution.get('plan_sha256')!=entry['plan']['sha256'] or execution.get('allocation',{}).get('job_id')!=accounting.get('job_id')
                or execution.get('authority_sha256')!=r.digest(Path(publication)/'authority.json')
                or execution.get('activation_sha256')!=r.digest(Path(publication)/'activation.json')
                or accounting.get('task_key')!=task_key or accounting.get('release_sha256')!=claim['release_sha256']):
            raise p.PrefixError("accepted job/source does not match scientific claim")
        parsed=ctl.accounting(accounting['sacct'],accounting['job_id'],{'cpus':1,'wall_seconds':claim['resources']['wall_seconds'],'memory_MiB':claim['resources']['memory_MiB']})
        if accounting.get('squeue','').strip() or not parsed['complete']:raise p.PrefixError("successful exact scheduler accounting required for CPU credit")
        primary=next(row for row in parsed['rows'] if row[0]==accounting['job_id'])
        actual=ctl.cpu_seconds(primary[5])
        if actual>claim['resources']['cpu_seconds'] or int(primary[3])>claim['resources']['wall_seconds']:
            raise p.PrefixError("component exceeded whole CPU/wall scope")
        charge=actual # exact Slurm parent TotalCPU, no parent/step double count
    if not accepted and (accounting.get('terminal') is not True or accounting.get('squeue','').strip()):
        raise p.PrefixError('failed component still has unresolved execution')
    with r.lock(ledger.lock):
        state=ledger._read();entry=state['studies'][study];current=entry['claims'][task_key]
        if current['state'] in FINAL:raise p.PrefixError("scientific attempt completion already reconciled")
        current.update(state='COLLECTED_COMPONENT' if accepted else 'FAILED_COMPONENT_RECONCILED',
            charged_CPU_seconds=charge,publication=str(publication),accounting=copy.deepcopy(accounting),completed_epoch=time.time())
        if accepted:
            if current['task'] in entry['results']:raise p.PrefixError("duplicate scientific result")
            compact={name:component[name] for name in ('schema','name','source','mode','scientific_identity_sha256',
                'task_sha256','metrics','origin_clock_windows','chunk_count','new_model_fits','posterior_updated','test_opened','promotion_authorized')}
            entry['results'][current['task']]={**compact,'charged_CPU_seconds':charge,'task_key':task_key,'publication':str(publication),
                'result_pin':pin(output/'result.json'),'seal_pin':pin(output/'completed_evidence.json')}
        r.write(ledger.path,state);return current


def complete_assessment(ledger,study,entry,plan,task_key,result,publication,accounting):
    claim=entry['assessment'];accepted=isinstance(result,dict) and result.get('application_passed') is True
    release_path=Path(claim['release_path'])/'release.json'
    if r.digest(release_path)!=claim['release_sha256']:raise p.PrefixError('assessment release changed')
    charge=1800;assessment=None
    if accepted:
        output=ctl.safe_tree(Path(publication)/'outputs'/'PREFIX_ASSESSMENT'/study)
        seal=r.read(output/'completed_evidence.json');assessment=r.read(output/'assessment.json')
        observed={str(q.relative_to(output)) for q in output.rglob('*') if q.is_file() and q!=output/'completed_evidence.json'}
        if (seal.get('status')!='COMPLETE_PREFIX_ASSESSMENT_NOT_PROMOTED' or observed!=set(seal.get('artifacts',{}))
                or seal.get('execution')!=assessment.get('execution')
                or assessment.get('all_components_independently_revalidated') is not True
                or assessment.get('new_model_fits')!=0 or assessment.get('official_test_opened') is not False
                or assessment.get('promotion_authorized') is not False or assessment.get('automatic_followon_admitted') is not False
                or assessment.get('source')!=plan['scientific_manifest']['source']):
            raise p.PrefixError('complete independent source-bound assessment required')
        for name,sha in seal['artifacts'].items():
            if Path(name).is_absolute() or '..' in Path(name).parts or r.digest(output/name)!=sha:
                raise p.PrefixError('assessment output bytes changed')
        execution=assessment['execution']
        if (execution.get('plan_sha256')!=entry['plan']['sha256'] or execution.get('allocation',{}).get('job_id')!=accounting.get('job_id')
                or execution.get('executed_sources')!=p.executed_sources()
                or execution.get('authority_sha256')!=r.digest(Path(publication)/'authority.json')
                or execution.get('activation_sha256')!=r.digest(Path(publication)/'activation.json')
                or accounting.get('task_key')!=task_key or accounting.get('release_sha256')!=claim['release_sha256']):
            raise p.PrefixError('assessment job/plan differs')
        parsed=ctl.accounting(accounting['sacct'],accounting['job_id'],{'cpus':1,'wall_seconds':1800,'memory_MiB':claim['resources']['memory_MiB']})
        if accounting.get('squeue','').strip() or not parsed['complete']:raise p.PrefixError('exact successful assessment accounting required')
        primary=next(v for v in parsed['rows'] if v[0]==accounting['job_id']);charge=ctl.cpu_seconds(primary[5])
        if charge>1800 or int(primary[3])>1800:raise p.PrefixError('separate assessment cap exceeded')
    elif accounting.get('terminal') is not True or accounting.get('squeue','').strip():
        raise p.PrefixError('failed assessment still has unresolved execution')
    with r.lock(ledger.lock):
        state=ledger._read();saved=state['studies'][study]['assessment']
        if saved['state'] in FINAL:raise p.PrefixError('assessment already reconciled')
        saved.update(state='COLLECTED_COMPONENT' if accepted else 'FAILED_COMPONENT_RECONCILED',
            charged_CPU_seconds=charge,publication=str(publication),accounting=accounting,result=assessment)
        r.write(ledger.path,state);return saved


def validate_cache_receipt(receipt_path, plan_path, config):
    receipt=r.read(receipt_path);plan_sha=r.digest(plan_path)
    if (receipt.get('schema')!='r157_hb_shared_prefix_cache_v1' or receipt.get('status')!='VERIFIED_SHARED_PREFIX_CACHE'
            or receipt.get('plan')!=pin(plan_path) or receipt.get('config_sha256')!=r.identity(config)
            or receipt.get('remote_root')!=config['remote_root']+'/prefix-cache-'+plan_sha[:32]
            or receipt.get('remote_manifest_sha256')!=receipt.get('cache_manifest',{}).get('sha256')):
        raise p.PrefixError('verified content-bound shared cache receipt required')
    pinned(receipt['cache_manifest'])
    return receipt


def stage_cache(plan_path, config_path, destination, *, control_path=None):
    """One explicit metadata/file transfer, not a scientific task or grant.

    Generic lifecycle may use this as rsync --link-dest. Every worker still hash
    verifies its complete original input membership. Cache failures retain their
    intent and do not permit an implicit transfer/model retry.
    """
    owner();plan=r.read(plan_path);p.validate_plan(plan);config=ctl.config(config_path)
    if control_path is None:raise p.PrefixError('explicit prepriced shared cache control required')
    control=pinned(pin(control_path))
    if (control.get('status')!='ROOT_ADMITTED_EXACT_PREFIX_CACHE_CONTROL'
            or control.get('controller')!=p.OWNER or control.get('plan')!=pin(plan_path)
            or control.get('config_sha256')!=r.identity(config)
            or control.get('executed_sources')!=p.executed_sources()
            or control.get('model_calls')!=0 or control.get('automatic_retry') is not False):
        raise p.PrefixError('exact source/plan/site cache control required')
    from . import lifecycle,metered_io
    administrative=dict(task_key=control['task_key'],control_cpu_scope=control['control_cpu_scope'],
        backend=dict(operation_price_pin=control['operation_price_pin']))
    _budget,state=lifecycle.control_scope(administrative)
    if state['kind']!='PREFIX':raise p.PrefixError('cache belongs to the shared prefix control pool')
    budget=lifecycle.bind_control(config,administrative,reserve=True)
    destination=r.no_links(destination)
    if destination.exists():raise FileExistsError('new cache transfer scope required')
    destination.mkdir(parents=True);stage_original_inputs(plan,destination)
    manifest={'schema':'r157_hb_shared_prefix_cache_manifest_v1','plan':pin(plan_path),
        'files':{str(q.relative_to(destination)):{'sha256':r.digest(q),'bytes':q.stat().st_size}
            for q in sorted(destination.rglob('*')) if q.is_file()}}
    create_only(destination/'cache_manifest.json',manifest)
    remote_root=config['remote_root']+'/prefix-cache-'+r.digest(plan_path)[:32]
    intent={'schema':'r157_hb_shared_prefix_cache_v1','status':'TRANSFER_INTENT','plan':pin(plan_path),
        'config_sha256':control['config_sha256'],'remote_root':remote_root,'cache_manifest':pin(destination/'cache_manifest.json'),
        'control':pin(control_path),
        'model_calls':0,'new_scientific_claims':0,'transfer_attempts':1,'automatic_retry':False}
    create_only(destination/'cache_transfer_intent.json',intent)
    try:
        lifecycle.remote(config,['mkdir','-p',config['remote_root']]);lifecycle.remote(config,['mkdir',remote_root])
        lifecycle.transfer(config,destination,remote_root)
        # Bounded stdlib streaming hashes on the login host; no package imports,
        # scientific arrays deserialized, installation or model computation.
        script='''import pathlib,json,hashlib,resource,signal,time
resource.setrlimit(resource.RLIMIT_CPU,(8,8));signal.alarm(90)
root=pathlib.Path(__ROOT__)
manifest=root/'cache_manifest.json'
if hashlib.sha256(manifest.read_bytes()).hexdigest()!=__SHA__:raise RuntimeError('cache manifest differs')
data=json.loads(manifest.read_text())
for name,entry in data['files'].items():
 rel=pathlib.Path(name)
 if rel.is_absolute() or '..' in rel.parts:raise RuntimeError('unsafe cache member')
 path=root/rel
 if path.is_symlink() or any(p.is_symlink() for p in path.parents) or not path.is_file() or path.stat().st_size!=entry['bytes']:raise RuntimeError('cache membership/bytes differs')
 digest=hashlib.sha256()
 with path.open('rb') as stream:
  for block in iter(lambda:stream.read(1048576),b''):digest.update(block)
 if digest.hexdigest()!=entry['sha256']:raise RuntimeError('cache bytes differ')
r=resource.getrusage(resource.RUSAGE_SELF)
print(json.dumps({'status':'VERIFIED','files':len(data['files']),'CPU_seconds':r.ru_utime+r.ru_stime}))
'''.replace('__ROOT__',repr(remote_root)).replace('__SHA__',repr(intent['cache_manifest']['sha256']))
        raw=metered_io.watch(config,script,budget,control['task_key'],timeout=92)
        verified=json.loads(raw)
        if verified.get('status')!='VERIFIED' or verified.get('files')!=len(manifest['files']):
            raise p.PrefixError('cache verification receipt incomplete')
        receipt=dict(intent,status='VERIFIED_SHARED_PREFIX_CACHE',remote_manifest_sha256=intent['cache_manifest']['sha256'],
            remote_verification=verified,verified_epoch=time.time())
        create_only(destination/'cache_receipt.json',receipt);return receipt
    except Exception as exc:
        create_only(destination/'cache_failure.json',dict(intent,status='FAILED_OR_AMBIGUOUS_TRANSFER_NO_AUTOMATIC_RETRY',error=str(exc)))
        raise


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='action',required=True)
    q=sub.add_parser('create-plan');q.add_argument('--publication',required=True);q.add_argument('--output',required=True)
    q=sub.add_parser('draft-master');q.add_argument('--plan',required=True);q.add_argument('--policy',required=True);q.add_argument('--expires-epoch',type=float,required=True);q.add_argument('--controller-price',required=True);q.add_argument('--output',required=True)
    q=sub.add_parser('adopt-master');q.add_argument('--draft',required=True);q.add_argument('--authorization',required=True);q.add_argument('--plan',required=True);q.add_argument('--output',required=True)
    q=sub.add_parser('admit-study');q.add_argument('--plan',required=True);q.add_argument('--master',required=True)
    q=sub.add_parser('open-wave');q.add_argument('--study',required=True);q.add_argument('--authority',required=True)
    q=sub.add_parser('calendar-observation');q.add_argument('--study',required=True);q.add_argument('--output',required=True);q.add_argument('--wave-id')
    for action in ('queue','advance'):
        q=sub.add_parser(action);q.add_argument('--study',required=True)
    q=sub.add_parser('set-policy');q.add_argument('--policy',required=True)
    q=sub.add_parser('prepare-release')
    for k in ('plan','master','wave','task','request','config','destination'):q.add_argument('--'+k,required=True)
    q.add_argument('--replacement-of')
    q.add_argument('--cache')
    q=sub.add_parser('stage-cache')
    for k in ('plan','config','destination'):q.add_argument('--'+k,required=True)
    q.add_argument('--control',required=True)
    q=sub.add_parser('prepare-assessment')
    for k in ('plan','master','request','config','destination'):q.add_argument('--'+k,required=True)
    for action in ('submit-held','issue-authority','release-job','activate','status','collect'):
        q=sub.add_parser(action);q.add_argument('--config',required=True)
        if action=='submit-held':q.add_argument('--release',required=True)
        else:q.add_argument('--key',required=True)
        if action=='activate':q.add_argument('--request',required=True)
        if action in ('status','collect'):q.add_argument('--receipt',required=True)
        if action=='collect':q.add_argument('--incoming',required=True);q.add_argument('--destination',required=True)
    a=parser.parse_args(argv)
    if a.action=='create-plan':value=create_plan(a.publication,a.output)
    elif a.action=='draft-master':value=draft_master(a.plan,pin(a.policy),expires_epoch=a.expires_epoch,controller_price_pin=pin(a.controller_price));create_only(a.output,value)
    elif a.action=='adopt-master':value=adopt_master(r.read(a.draft),pin(a.authorization),r.read(a.plan));create_only(a.output,value)
    elif a.action=='admit-study':value=Ledger().admit(a.plan,a.master)
    elif a.action=='open-wave':value=Ledger().open_wave(a.study,a.authority)
    elif a.action=='calendar-observation':value=calendar_observation(a.study,a.output,wave_id=a.wave_id)
    elif a.action=='queue':value=Ledger().queue(a.study)
    elif a.action=='advance':value=Ledger().advance(a.study)
    elif a.action=='set-policy':value=Ledger().set_policy(pin(a.policy))
    elif a.action=='prepare-release':value=prepare_component_release(a.plan,a.master,a.wave,a.task,a.request,a.config,a.destination,replacement_of=a.replacement_of,cache_receipt=a.cache)
    elif a.action=='stage-cache':value=stage_cache(a.plan,a.config,a.destination,control_path=a.control)
    elif a.action=='prepare-assessment':value=prepare_assessment_release(a.plan,a.master,a.request,a.config,a.destination)
    else:
        from . import lifecycle
        if a.action=='submit-held':value=lifecycle.submit_component(a.release,a.config)
        elif a.action=='issue-authority':value=lifecycle.issue_authority(a.key,a.config)
        elif a.action=='release-job':value=lifecycle.release_job(a.key,a.config)
        elif a.action=='activate':value=lifecycle.activate(a.key,a.config,a.request)
        elif a.action=='status':value=lifecycle.status(a.key,a.config,a.receipt)
        else:value=lifecycle.collect(a.key,a.config,a.receipt,a.incoming,a.destination)
        lifecycle.finish_parent_contexts()
    print(json.dumps(value,sort_keys=True,allow_nan=False))


if __name__=='__main__':
    try:main()
    finally:
        from . import lifecycle
        lifecycle.finish_parent_contexts()
