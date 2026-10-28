"""Offline-prepared startup primitives; no grant, replacement or automatic CLI.

A separately reviewed authoritative replacement protocol must supply routing.
This kit never makes the stock spent-region/reservation/overlap gates disappear.
"""
import ast
import copy
import inspect
import math
from pathlib import Path
import resource
import time
from pricefm_hb import activation as a,lifecycle as l,operation_budget as ob,registry as r
from authorized_admission_bridge import refresh_authorized_request

SCHEMA='r160_future_cost_startup_ticket_v1'
DECISION='ROOT_ADMITTED_SEPARATE_FINITE_COST_REPLACEMENT'
PROTOCOL='ROOT_REVIEWED_AUTHORITATIVE_COST_REPLACEMENT_PROTOCOL'
OLD_KEYS={'8309cff635d90324c0a630458c8f5b003d43ad36aacc1cb171003992d38d406f',
          '7d33f867c4f26d8c7a9a158d499087d3ee58ddf2a2323ad04b8deffd9ab0aa7b'}
OLD_SCOPES={'r157_fi_cost_20261028_01','r157_dk2_cost_20261028_01','r158_initial_recovery_20261028_03'}
OLD_JOBS={'869420'}
ROUTES={'reserve','canonical_claims','overlap','transition','collect'}
LIFETIMES=('stage1','stage2','authority_and_authorized_observer','release_only',
           'watch_and_activate','status','collect')

def require(ok,message):
    if not ok:raise ValueError(message)

def pin(path):return {'path':str(r.no_links(path)),'sha256':r.digest(path)}

def validate_future_ticket(ticket,decision,protocol_review,release,*,now=None):
    """Pure future-only gate. No current grant can be repaired or reused here."""
    now=time.time() if now is None else now;study=release.get('study');key=release.get('task_key')
    require(ticket.get('schema')==SCHEMA and ticket.get('status')=='ROOT_ADMITTED_FUTURE_COST_STARTUP'
        and ticket.get('controller')==a.OWNER,'explicit future startup ticket required')
    require(study in {'FI','DK2'} and release.get('purpose')=='COST_ONLY'
        and ticket.get('study')==study and ticket.get('task_key')==key,'exact future FI/DK2 COST intent required')
    require(key not in OLD_KEYS and ticket.get('scope_id') not in OLD_SCOPES
        and release.get('scope_id')==ticket.get('scope_id')
        and release.get('control_cpu_scope',{}).get('scope_id') not in OLD_SCOPES
        and str(ticket.get('job_id')) not in OLD_JOBS,'old spent FI/DK2 intent/job/control scope prohibited')
    require(decision.get('schema')=='r160_future_cost_replacement_decision_v1'
        and decision.get('status')==DECISION and decision.get('controller')==a.OWNER
        and decision.get('study')==study and decision.get('replacement_task_key')==key
        and decision.get('scope_id')==ticket.get('scope_id')
        and decision.get('new_intents_maximum')==1
        and decision.get('old_charges_refunded') is False
        and decision.get('real_FI_overrun_cleared') is False
        and decision.get('old_spent_regions_preserved') is True
        and decision.get('scientific_protocol_unchanged') is True,'new finite root replacement decision required')
    require(protocol_review.get('status')==PROTOCOL and protocol_review.get('controller')==a.OWNER
        and protocol_review.get('study')==study and protocol_review.get('replacement_task_key')==key
        and protocol_review.get('authoritative_routes')==sorted(ROUTES)
        and protocol_review.get('preserves_all_old_claims_charges_and_violations') is True
        and protocol_review.get('source17')==release.get('source_hashes'),
        'authoritative replacement reserve/overlap/transition/collect protocol is a separate prerequisite')
    require(type(ticket.get('created_epoch')) in (int,float) and type(ticket.get('expires_epoch')) in (int,float)
        and math.isfinite(ticket['created_epoch']) and math.isfinite(ticket['expires_epoch'])
        and ticket['created_epoch']<=now<ticket['expires_epoch']
        and decision.get('expires_epoch')==ticket['expires_epoch'],'one explicit original nonrenewing calendar required')
    require(ticket.get('budget')=={'science_CPU':1200,'science_wall':1200,'control_CPU':230,
        'priced_maximum_CPU':217,'parent_CPU':60,'parent_slice_CPU':8,'lifetimes':7,
        'parent_reservations_CPU':56,'transfers':6,'metadata':20,'refreshes':1,'ready_watches':1},
        'unchanged complete217/230,seven8CPU lifetimes and original1200 budget required')
    resources=release.get('resources',{})
    require(resources.get('cpus')==1 and resources.get('cpu_seconds')==1200
        and resources.get('wall_seconds')==1200 and resources.get('memory_MiB')==4096,
        'unchanged oneCPU1200 cost resources required')
    return ticket

def role_complete_authority_factory(stock_issue=None,*,routing=None):
    """Only role/root pins and a downward180-second queue clamp alter stock AST."""
    stock=l.issue_authority if stock_issue is None else stock_issue
    tree=ast.parse(inspect.getsource(stock));fn=tree.body[0]
    require(isinstance(fn,ast.FunctionDef) and fn.name=='issue_authority' and not fn.decorator_list,
            'exact stock authority function required')
    fn.name='issue_future_cost_authority';fn.args.args.extend(ast.arg(arg=n) for n in ('startup_ticket_pin','factory_pin'))
    count=0
    for node in ast.walk(fn):
        if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='queue' for t in node.targets):
            node.value=ast.Call(func=ast.Name(id='min',ctx=ast.Load()),args=[ast.Constant(value=180),node.value],keywords=[]);count+=1
    require(count==1,'exact stock queue calculation required')
    index=next(i for i,node in enumerate(fn.body) if isinstance(node,ast.Expr) and isinstance(node.value,ast.Call)
               and isinstance(node.value.func,ast.Attribute) and node.value.func.attr=='validate_authority')
    fn.body[index:index]=ast.parse("""if release['purpose']!='COST_ONLY' or release['study'] not in {'FI','DK2'}:
 raise a.ActivationError('future cost role factory only')
authority.update(role=release['study']+'_COST_ONLY_BENCHMARK',root_cost_startup_ticket=startup_ticket_pin,root_metadata_factory=factory_pin)
""").body
    namespace=dict(stock.__globals__)
    if routing:
        require(set(routing)=={'_bound_claim','_cost_transition'},'only separately reviewed metadata routing allowed')
        namespace.update(routing)
    exec(compile(ast.fix_missing_locations(tree),'<versioned-role-complete-cost-authority>','exec'),namespace)
    return namespace[fn.name]

def stock_api_factory(name,*,routing=None):
    """Unchanged stock API body; one call, no caller-added _bound_claim."""
    require(name in {'release_job','watch_ready','activate'},'reviewed stock startup API only')
    stock=getattr(l,name);tree=ast.parse(inspect.getsource(stock));namespace=dict(stock.__globals__)
    if routing:
        require(set(routing)=={'_bound_claim','_cost_transition'},'only reviewed replacement metadata routing allowed')
        namespace.update(routing)
    exec(compile(ast.fix_missing_locations(tree),'<unchanged-stock-'+name+'>','exec'),namespace)
    result=namespace[name]
    result.stock_source_AST=ast.dump(tree,include_attributes=False)
    return result

def require_fresh_after_authority(request,authority,*,now=None):
    """All three proof observations follow authority; full queue fits their TTL."""
    now=time.time() if now is None else now
    require(0<authority.get('max_queue_seconds',0)<=180,'queue must be shortened, never extended')
    epochs=[]
    for key in ('handoff_receipt','all_hosts_observation','site_admission'):
        value=a.read_pin(request[key]);epoch=value.get('observed_epoch')
        require(a.fresh(value,now) and type(epoch) in (int,float) and epoch>=authority['issued_epoch'],
                'fresh post-authority held observation required')
        epochs.append(epoch)
    require(now<authority['issued_epoch']+authority['max_queue_seconds']
        and authority['issued_epoch']+authority['max_queue_seconds']-min(epochs)<300,
        'original queue must fit existing proof freshness')
    return min(epochs)

def _context(ticket_path,protocol):
    """Protocol binding is mandatory; this kit supplies no reservation bypass."""
    require(protocol is not None,'separately reviewed replacement protocol binding required')
    l.owner()
    ticket=a.read_pin(pin(ticket_path));decision=a.read_pin(ticket['replacement_decision_pin'])
    review=a.read_pin(ticket['replacement_protocol_review_pin']);release=a.read_pin(ticket['release_pin'])
    validate_future_ticket(ticket,decision,review,release)
    require(ticket['helper_pin']==pin(__file__)
        and ticket['bridge_pin']==pin(Path(__file__).with_name('authorized_admission_bridge.py')),
        'versioned startup helper/bridge bytes changed')
    require(release['source_hashes']==a.executed_sources('COST_ONLY')
        and ticket['source17']==release['source_hashes'],'exact unchanged qualified17 sources required')
    require(protocol.review_pin==ticket['replacement_protocol_review_pin']
        and protocol.module_pin==review['protocol_module_pin']
        and pin(protocol.module_pin['path'])==protocol.module_pin,'reviewed metadata routing module required')
    require(set(protocol.routing)=={'_bound_claim','_cost_transition'},'explicit replacement routing required')
    protocol.validate_binding(ticket,release)
    return ticket,release

def authorize_and_observe(ticket_path,config_path,operator_config,resource_plan,output,*,protocol=None,owner_receipt_pin=None):
    """One8CPU parent: authority's one bound/hash, then authorized observer."""
    ticket,release=_context(ticket_path,protocol);output=r.no_links(output)
    require(not output.exists(),'new future startup audit required');output.mkdir(parents=True)
    # Factory's original _bound_claim is the sole full hash before observation.
    try:
        result=role_complete_authority_factory(routing=protocol.routing)(ticket['task_key'],config_path,pin(ticket_path),pin(__file__))
        claim,legacy,config=protocol.read_authorized_pair(ticket,release,result)
        require(claim['state']==legacy['state']=='AUTHORIZED' and claim['task_key']==ticket['task_key']
            and str(claim['job_id'])==str(ticket['job_id']),'exact future authorized held pair required')
        # Reuse the existing parent marker; no _bound_claim/full release hash.
        budget=l.bind_control(config,release);token=budget.start_operation(ticket['task_key'],'admission_refresh')
        before=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN);fresh=None
        try:
            fresh=refresh_authorized_request(resource_plan,operator_config,release['policy_pin'],output/'fresh',
                expected_claim=claim,expected_release=release,expected_legacy_claim=legacy,
                legacy_snapshot=protocol.legacy_snapshot,admission=protocol.admission,owner_receipt_pin=owner_receipt_pin)
        finally:
            after=resource.getrusage(resource.RUSAGE_SELF);child=resource.getrusage(resource.RUSAGE_CHILDREN)
            used=after.ru_utime+after.ru_stime+child.ru_utime+child.ru_stime-before.ru_utime-before.ru_stime-children.ru_utime-children.ru_stime
            budget.finish_operation(ticket['task_key'],token,local_CPU=used,
                remote_CPU=(fresh or {}).get('observer_budget',{}).get('remote_CPU_seconds'),
                outcome='AUTHORIZED_HELD_REFRESH_COMPLETE' if fresh and fresh.get('request') else 'AUTHORIZED_HELD_REFRESH_FAILED')
        require(fresh and fresh.get('status')=='READY_FOR_PREPARE_ONLY_NOT_ADMITTED','fresh authorized held observer blocked')
        request=a.read_pin(fresh['request']);l.validate_request(request,release)
        authority=protocol.read_authority(claim);require_fresh_after_authority(request,authority)
        record={'schema':SCHEMA,'status':'AUTHORIZED_WITH_ONE_FRESH_HELD_PROOF_NOT_RELEASED','ticket':pin(ticket_path),
            'claim':result,'fresh_request':fresh['request'],'authority_issued_epoch':authority['issued_epoch'],
            'max_queue_seconds':authority['max_queue_seconds'],'no_second_refresh':True}
        l.write_new(output/'AUTHORIZED_FRESH.json',record);return record
    finally:l.finish_parent_contexts()

def release_only(ticket_path,config_path,proof_pin,*,protocol=None):
    """Separate one8CPU stock release lifetime; no redundant outer bound."""
    ticket,release=_context(ticket_path,protocol);record=a.read_pin(proof_pin)
    require(record['ticket']==pin(ticket_path),'fresh proof belongs to another ticket')
    request=a.read_pin(record['fresh_request']);claim=protocol.current_claim(ticket)
    require(claim['state']=='AUTHORIZED' and str(claim['job_id'])==str(ticket['job_id']),'exact authorized job required')
    require_fresh_after_authority(request,protocol.read_authority(claim))
    try:return stock_api_factory('release_job',routing=protocol.routing)(ticket['task_key'],config_path)
    finally:l.finish_parent_contexts()

def watch_and_activate(ticket_path,config_path,proof_pin,output,*,protocol=None):
    """One8CPU parent: exactly two stock bounds/hashes; zero new observer."""
    ticket,release=_context(ticket_path,protocol);record=a.read_pin(proof_pin)
    require(record['ticket']==pin(ticket_path) and record['no_second_refresh'] is True,'one exact authorized proof required')
    request=a.read_pin(record['fresh_request']);claim=protocol.current_claim(ticket)
    require(claim['state']=='SUBMITTED' and str(claim['job_id'])==str(ticket['job_id']),'same released job required')
    require_fresh_after_authority(request,protocol.read_authority(claim))
    output=r.no_links(output);require(not output.exists(),'new READY audit required');output.mkdir(parents=True)
    try:
        stock_api_factory('watch_ready',routing=protocol.routing)(ticket['task_key'],config_path,output/'ready.json')
        return stock_api_factory('activate',routing=protocol.routing)(ticket['task_key'],config_path,record['fresh_request']['path'])
    finally:l.finish_parent_contexts()
