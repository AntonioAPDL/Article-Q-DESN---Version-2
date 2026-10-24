"""Finite orchestration gates and accounting; no service or DATA mutations."""
import importlib.util
import json
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT=Path(__file__).resolve().parents[1]
ENTRY=ROOT/'scripts/pricefm/503_orchestrate_pricefm_stage_r151.py'


def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


@pytest.fixture
def m():return load(ENTRY,'test_finite_r151')


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))


def test_frozen_total_lifetime_is_not_a_renewal(m):
    c=m.config()
    assert c['outer_seconds']==630*60
    assert c['EE_coordinator_seconds']+c['regional_benchmark_seconds']+3*c['regional_wave_seconds']+300==c['outer_seconds']
    assert c['regional_admissions']==['benchmark','1','2','3']
    assert c['new_model_fits']==0 and c['max_workers']==2 and not c['renewals_authorized']


@pytest.mark.parametrize('key,value',[('outer_seconds',37801),('regional_admissions',['benchmark','1','2','3','4']),
    ('new_model_fits',1),('max_workers',3),('cpus',list(range(30))),('AL_authorized',True)])
def test_configuration_cannot_expand(m,monkeypatch,key,value):
    c=m.read(m.CONFIG);c[key]=value;monkeypatch.setattr(m,'read',lambda _:c)
    with pytest.raises(RuntimeError):m.config()


def terminal(**kwargs):
    return dict(status='R151_REGION_WAVE_DEFERRED',cleanup_verified=True,
                cleanup_errors=[],strict_new_components=2,**kwargs)


def test_finite_admissions_order(m):
    assert m.allowed_next_admission([],{})=='benchmark'
    assert m.allowed_next_admission(['benchmark'],{'benchmark':terminal()})=='1'
    assert m.allowed_next_admission(['benchmark','1'],{'1':terminal()})=='2'
    assert m.allowed_next_admission(['benchmark','1','2'],{'2':terminal()})=='3'
    assert m.allowed_next_admission(['benchmark','1','2','3'],{'3':terminal()}) is None


@pytest.mark.parametrize('existing',[['1'],['benchmark','2'],['benchmark','1','1'],['benchmark','1','2','3','4']])
def test_out_of_order_or_duplicate_admissions_refused(m,existing):
    with pytest.raises(RuntimeError):m.allowed_next_admission(existing,{})


@pytest.mark.parametrize('change',[{'cleanup_verified':False},{'cleanup_errors':['lost owner']},
    {'strict_new_components':0},{'status':'R151_REGION_GUARD_STOPPED'},
    {'resource_unfunded_pending':['whole matched set']}])
def test_bad_terminal_cannot_consume_another_wave(m,change):
    v=terminal();v.update(change)
    assert m.allowed_next_admission(['benchmark'],{'benchmark':v}) is None


def test_missing_terminal_is_not_automatic_continuation(m):
    assert m.allowed_next_admission(['benchmark'],{}) is None


def test_remaining_capacity_discards_spent_tails(m):
    assert m.regional_remaining_capacity({},.5,now=0)==16200
    leases={'1':{'expires_epoch':2000}}
    assert m.regional_remaining_capacity(leases,.5,now=100)==10900
    assert m.regional_remaining_capacity(leases,.5,{'1':{}},now=100)==10800
    assert m.regional_remaining_capacity(leases,.5,now=5000)==10800
    leases.update({'2':{'expires_epoch':3000},'3':{'expires_epoch':4000}})
    assert m.regional_remaining_capacity(leases,.5,now=5000)==0


@pytest.mark.parametrize('share',[0,-.1,1.01,float('nan'),float('inf')])
def test_invalid_delivery_share_refused(m,share):
    with pytest.raises(ValueError):m.regional_remaining_capacity({},share,now=0)


def ee_fixture():
    prep=dict(control='C0',nominees_for_gate=['A','B'],all_D_for_gate=['D0','D1'],all_S0_for_gate=['S0','SA','SB'])
    q=dict(terminal=False,scientific_complete=False,phase='MATCHED_MC_UNFUNDED_PENDING',unfunded_pending=['X1','X2'],pending=['X1','X2'])
    t=dict(status='R151_RECOVERY_DEFERRED',cleanup_verified=True,cleanup_errors=[],resource_unfunded_pending=['X1','X2'])
    return prep,q,t


def test_complete_EE_assessment_permits_one_region(m):
    p,q,t=ee_fixture();q.update(terminal=True,scientific_complete=True);t['status']='R151_RECOVERY_COMPLETE'
    assert m.EE_disposition(t,q,p,lambda _:True,{'sha256':'verified'})['proceed']


def test_explicit_unfunded_MC_permits_only_complete_D_and_S0(m):
    p,q,t=ee_fixture()
    assert m.EE_disposition(t,q,p,lambda _:True)['proceed']
    assert not m.EE_disposition(t,q,p,lambda n:n!='D1')['proceed']
    assert not m.EE_disposition(t,q,p,lambda n:n!='SB')['proceed']
    q.update(phase='MATCHED_FULL_MC',unfunded_pending=[])
    assert m.EE_disposition(t,q,p,lambda _:True)['proceed']


@pytest.mark.parametrize('change',[{'status':'R151_RECOVERY_GUARD_STOPPED'},
    {'original_stop_reason':'CPU starvation'},{'cleanup_verified':False},
    {'cleanup_errors':['ownership replaced']},{'resource_unfunded_pending':[]}])
def test_operational_stop_never_opens_region(m,change):
    p,q,t=ee_fixture();t.update(change)
    assert not m.EE_disposition(t,q,p,lambda _:True)['proceed']


def test_EE_mismatched_unfunded_list_or_missing_assessment_fails(m):
    p,q,t=ee_fixture();q['unfunded_pending']=['other']
    assert not m.EE_disposition(t,q,p,lambda _:True)['proceed']
    t['status']='R151_RECOVERY_COMPLETE';q.update(terminal=True,scientific_complete=True)
    assert not m.EE_disposition(t,q,p,lambda _:True)['proceed']


class Science:
    def __init__(self,tmp):
        self.OUT=tmp/'out';self.PREP=tmp/'prep'
        self.prices={n:dict(estimated_cpu_seconds=10.,estimated_wall_seconds=20.,estimated_max_chunk_wall_seconds=3.)
                     for n in ['D0','D1']+[f'{p}{s}' for p in ('C0','A','B') for s in range(3)]}
    def pricing(self):return dict(task_estimates=self.prices,all_prospective_seed0_scenarios=[dict(A='A',B='B')],
        replacement_reserve_CPU_seconds=10.,benchmark_adjusted_available_CPU_seconds=1000.,
        resource_projection=dict(conservative_idle_share=.5))
    def read_preparation(self):return dict(control='C0',source=dict(head='head'))
    def task_complete(self,name):return False
    def names_for(self,packages,mode,seeds):return [f'{p}{s}' for p in packages for s in range(3)]
    def estimate_task(self,name):return dict(name=name,**self.prices[name])
    def task_by_name(self,name,prep=None):return dict(mode='D' if name.startswith('D') else 'S')


def test_projection_funds_full_D_and_worst_nine_S0_not_D_only(m,tmp_path,monkeypatch):
    science=Science(tmp_path)
    resource=load(ROOT/'scripts/pricefm/501_recover_pricefm_stage_r150.py','test_pack_only')
    monkeypatch.setattr(m,'apis',lambda:(resource,science));monkeypatch.setattr(m,'regional_attempts',lambda _:[])
    q=dict(phase='DETERMINISTIC_POOL',pending=['D0','D1'])
    v=m.regional_projection(science,q,{}, {},now=0)
    assert len(v['future_components'])==11
    assert v['cumulative_projected_CPU_seconds']==120.
    assert v['fits']
    science.pricing=lambda:dict(task_estimates=science.prices,
        all_prospective_seed0_scenarios=[dict(A='A',B='B')],replacement_reserve_CPU_seconds=10.,
        benchmark_adjusted_available_CPU_seconds=119.,resource_projection=dict(conservative_idle_share=.5))
    assert not m.regional_projection(science,q,{}, {},now=0)['fits']


def test_no_expired_capacity_credit_even_when_cumulative_budget_fits(m,tmp_path,monkeypatch):
    science=Science(tmp_path);resource=load(ROOT/'scripts/pricefm/501_recover_pricefm_stage_r150.py','test_pack_expiry')
    monkeypatch.setattr(m,'apis',lambda:(resource,science));monkeypatch.setattr(m,'regional_attempts',lambda _:[])
    leases={str(w):dict(expires_epoch=100) for w in range(1,4)}
    v=m.regional_projection(science,dict(phase='MATCHED_FULL_MC',pending=['A0']),leases,{},now=200)
    assert v['remaining_capacity_CPU_seconds']==0 and not v['fits']


def test_S27_extra_bundle_uses_shared_control_once(m,monkeypatch):
    def names(packages,mode,seeds):return [f'{p}_s{s}_seed{seed}' for p in packages for s in (1,2,3) for seed in seeds]
    science=SimpleNamespace(read_preparation=lambda:dict(control='C0'),
        read_decision=lambda _:dict(nominees=['A','B']),component_loss=lambda p,m:{'C0':10.,'A':9.,'B':9.5}[p],
        producer=lambda:SimpleNamespace(practical_margin=lambda _: .1),names_for=names)
    extras=m.prospective_extras(science)
    assert len(extras)==18 and len(set(extras))==18
    assert len([n for n in extras if n.startswith('C0_')])==6
    assert 9+len(extras)==27


def test_completed_charge_once_and_partial_reservation(m,tmp_path,monkeypatch):
    science=Science(tmp_path);calls=[]
    science.task_complete=lambda n:n=='D0'
    science.completed_CPU_charge=lambda n,p:(calls.append(n) or dict(charged_CPU_seconds=15.))
    for invocation in ('i1','i2'):
        write(science.OUT/'cpu_accounting/D0'/invocation/'started.json',{})
    saves=[dict(task='D0',attested=dict(InvocationID=v)) for v in ('i1','i2')]
    saves += [dict(task='D1',attested=dict(InvocationID='unknown'))]
    monkeypatch.setattr(m,'attempt_charge',lambda *_:1.)
    charge,details=m.charge_components(science,saves,science.read_preparation())
    assert calls==['D0'] and details==dict(D0=15.,D1=10.) and charge==25.


def test_missing_ownership_started_attempt_keeps_reservation(m,tmp_path,monkeypatch):
    science=Science(tmp_path);write(science.OUT/'cpu_accounting/D1/orphan/started.json',{})
    saves=[dict(task='D1',attested=dict(InvocationID='known'))]
    monkeypatch.setattr(m,'attempt_charge',lambda *_:1.)
    assert m.charge_components(science,saves,science.read_preparation())[0]==20.


def test_benchmark_and_finalizer_are_separate_from_numerical_budget(m,tmp_path):
    science=Science(tmp_path)
    assert m.charge_components(science,[dict(task='__benchmark__'),dict(task='__finalize__')],{})==(0.,{})


def test_wait_missing_terminal_still_drains_exact_owned_lifetime(m,monkeypatch):
    drained=[]
    resource=SimpleNamespace(load_legacy=lambda:SimpleNamespace(verify_owned=lambda *_:None),
        drain_exact=lambda system,saved:drained.append(saved['unit']) or dict(drained=True))
    monkeypatch.setattr(m,'apis',lambda:(resource,None))
    system=SimpleNamespace(unit=lambda _:dict(ActiveState='inactive'))
    assert m.wait_owned(system,dict(unit='owned'),0,1)==dict(drained=True)
    assert drained==['owned']


def test_wait_active_deadline_cannot_poll_forever(m,monkeypatch):
    resource=SimpleNamespace(load_legacy=lambda:SimpleNamespace(verify_owned=lambda *_:None))
    monkeypatch.setattr(m,'apis',lambda:(resource,None))
    system=SimpleNamespace(unit=lambda _:dict(ActiveState='active'))
    with pytest.raises(RuntimeError,match='deadline'):m.wait_owned(system,dict(unit='owned'),0,1)


def test_projection_pins_active_slot_and_orders_D_before_S(m,tmp_path,monkeypatch):
    science=Science(tmp_path);resource=load(ROOT/'scripts/pricefm/501_recover_pricefm_stage_r150.py','test_barrier')
    observed=[]
    def packing(tasks,current,future):
        observed.extend(tasks)
        return resource.scheduling_projection(tasks,current,future)
    fake=SimpleNamespace(scheduling_projection=packing)
    monkeypatch.setattr(m,'apis',lambda:(fake,science));monkeypatch.setattr(m,'regional_attempts',lambda _:[])
    active=[dict(task='D0',resource_slot=1)]
    m.regional_projection(science,dict(phase='DETERMINISTIC_POOL',pending=['D0','D1']),{}, {},active,now=0)
    assert next(t for t in observed if t['name']=='D0')['fixed_slot']==1
    assert {t['phase'] for t in observed if t['name'].startswith('D')}=={0}
    assert {t['phase'] for t in observed if not t['name'].startswith('D')}=={1}


def test_token_without_valid_exact_drain_does_not_release_reserve(m,tmp_path):
    science=Science(tmp_path);base=science.PREP/'muscat_resources'
    token=dict(old_unit='old',old_invocation_id='invocation',lease_id='lease')
    write(base/'replacement_token.json',token)
    saved=dict(unit='old',attested=dict(InvocationID='invocation',ControlGroup='/group'))
    assert m.replacement_reserve(science,[saved],science.pricing())==10.
    proof=dict(token_sha256=m.digest(base/'replacement_token.json'),old_unit='old',lease_id='lease',
        predecessor_cgroup='/group',drain=dict(cleanup_verified=True,cleanup_errors=[],cleanup=[dict(drained=True)]))
    write(base/'replacement_drain.json',proof)
    assert m.replacement_reserve(science,[saved],science.pricing())==0.
    proof['predecessor_cgroup']='/replacement';write(base/'replacement_drain.json',proof)
    assert m.replacement_reserve(science,[saved],science.pricing())==10.


def test_orphaned_prior_attempt_cannot_disappear_from_charge(m,tmp_path,monkeypatch):
    science=Science(tmp_path)
    write(science.OUT/'cpu_accounting/D1/known/started.json',dict(prior_started_invocations=['missing']))
    monkeypatch.setattr(m,'attempt_charge',lambda *_:10.)
    amount,_=m.charge_components(science,[dict(task='D1',attested=dict(InvocationID='known'))],{})
    assert amount==20.


def test_known_live_overrun_increases_unknown_attempt_reservation(m,tmp_path,monkeypatch):
    science=Science(tmp_path)
    current=dict(pid=5,start_ticks=8,boot_id='boot')
    legacy=SimpleNamespace(process=lambda _:current,cpu_seconds=lambda _:50.)
    resource=SimpleNamespace(load_legacy=lambda:legacy)
    monkeypatch.setattr(m,'apis',lambda:(resource,science))
    saved=dict(task='D1',process=current,attested=dict(InvocationID='invocation'))
    assert m.attempt_charge(science,saved,science.read_preparation(),10.)==55.
    current['start_ticks']=9;saved['process']=dict(pid=5,start_ticks=8,boot_id='boot')
    assert m.attempt_charge(science,saved,science.read_preparation(),10.)==10.


def test_lower_CPU_scenario_can_fail_packing_and_blocks_prefix(m,tmp_path,monkeypatch):
    science=Science(tmp_path);resource=load(ROOT/'scripts/pricefm/501_recover_pricefm_stage_r150.py','test_every_scenario')
    price=science.pricing();price['replacement_reserve_CPU_seconds']=0.
    for i in range(3):science.prices['Z'+str(i)]=dict(estimated_cpu_seconds=1.,estimated_wall_seconds=6000.,estimated_max_chunk_wall_seconds=3.)
    price['all_prospective_seed0_scenarios'].append(dict(A='Z',B='B'))
    science.pricing=lambda:price
    monkeypatch.setattr(m,'apis',lambda:(resource,science));monkeypatch.setattr(m,'regional_attempts',lambda _:[])
    value=m.regional_projection(science,dict(phase='DETERMINISTIC_POOL',pending=['D0','D1']),{}, {},now=0)
    assert value['packing']['fits']
    assert not value['all_prospective_seed0_scenarios_fit'] and not value['fits']
    assert len(value['all_prospective_seed0_packing'])==2


def test_benchmark_unfunded_prefix_is_owned_finalized_without_scientific_claim(m,tmp_path,monkeypatch):
    science=Science(tmp_path);folder=tmp_path/'run';folder.mkdir()
    write(folder/'release.json',dict(source=dict(head='frozen')))
    runtime=science.PREP/'muscat_resources/wave_benchmark'
    write(runtime/'lease.json',dict(wave='benchmark',expires_epoch=9999999999))
    write(science.PREP/'muscat_resources/outer_context.json',dict(EE_recovery_id='recovery'))
    q=dict(phase='DEFERRED_UNFUNDED_PREFIX',complete=[],terminal=True,scientific_complete=False)
    science.queue_state=lambda:q;science.task_complete=lambda n:n=='__benchmark__'
    legacy=SimpleNamespace(System=lambda:object(),discover_workers=lambda _:[])
    resource=SimpleNamespace(load_legacy=lambda:legacy,verify_release=lambda _:(None,dict(cooperative_grace_seconds=0)),
        await_capsule=lambda p:dict(unit='controller' if p.name=='controller' else 'outer'),
        canonical_lock=lambda _:nullcontext(),CANONICAL=tmp_path/'canonical',
        cooperative_drain=lambda *_args,**_kwargs:dict(cleanup_verified=True,cleanup_errors=[],cleanup=[]),
        immutable=write)
    monkeypatch.setattr(m,'apis',lambda:(resource,science));monkeypatch.setattr(m,'run_folder',lambda _:folder)
    monkeypatch.setattr(m,'regional_attempts',lambda _:[])
    monkeypatch.setattr(m,'guard',lambda *_:dict(handoff={}))
    monkeypatch.setattr(m.signal,'signal',lambda *_:None)
    finalized=[];monkeypatch.setattr(m,'finalize_owned',lambda *_:finalized.append(True))
    assert m.regional_wave('run','benchmark','controller')==0
    result=m.read(runtime/'terminal.json')
    assert finalized==[True] and result['status']=='R151_REGION_WAVE_COMPLETE'
    assert result['scientific_complete'] is False and result['strict_new_components']==1


def lease_fixture(m,tmp_path,monkeypatch):
    science=Science(tmp_path);base=science.PREP/'muscat_resources'
    write(science.PREP/'preparation.json',dict(source='source'))
    outer=dict(unit='outer',attested=dict(InvocationID='outer-invocation'))
    capsule=tmp_path/'outer.json';write(capsule,outer)
    write(base/'outer_context.json',dict(run_id='run',outer_capsule_path=str(capsule)))
    lease=dict(stage='R151_REGION',region='DK_2',wave='1',seconds=7200,started_epoch=100.,expires_epoch=7300.,
        nonrenewing=True,source_head='source',boot_id='boot',preparation_sha256=m.digest(science.PREP/'preparation.json'),
        orchestration_config_sha256=m.digest(m.CONFIG),outer_context_sha256=m.digest(base/'outer_context.json'),
        outer_run_id='run',outer_unit='outer',outer_invocation_id='outer-invocation')
    write(base/'wave_1/lease.json',lease)
    monkeypatch.setattr(m,'apis',lambda:(SimpleNamespace(boot=lambda:'boot'),science))
    return science,outer,lease,base


def test_regional_epoch_mutation_rejected_before_dispatch(m,tmp_path,monkeypatch):
    science,outer,lease,base=lease_fixture(m,tmp_path,monkeypatch)
    release=dict(source=dict(head='source'))
    assert m.verify_regional_lease(lease,science,release,outer)
    mutated=dict(lease,expires_epoch=7400.);write(base/'wave_1/lease.json',mutated)
    with pytest.raises(RuntimeError,match='immutable lease'):m.verify_regional_lease(lease,science,release,outer)


@pytest.mark.parametrize('change',[dict(seconds=7300),dict(outer_invocation_id='replacement'),
    dict(source_head='changed'),dict(stage='other'),dict(nonrenewing=False)])
def test_regional_lease_contract_backlinks_enforced(m,tmp_path,monkeypatch,change):
    science,outer,lease,base=lease_fixture(m,tmp_path,monkeypatch)
    lease.update(change);write(base/'wave_1/lease.json',lease)
    with pytest.raises(RuntimeError):m.verify_regional_lease(lease,science,dict(source=dict(head='source')),outer)


@pytest.mark.parametrize('failure',['baseline_guard','controller_conflict'])
def test_regional_admission_not_consumed_when_fresh_preflight_fails(m,tmp_path,monkeypatch,failure):
    science=Science(tmp_path);base=science.PREP/'muscat_resources';folder=tmp_path/'outerrun'
    write(base/'outer_context.json',dict(run_id='run',EE_recovery_id='EE'))
    write(folder/'context.json',dict(expires_epoch=m.ORIGINAL_EXPIRES))
    resource=SimpleNamespace(CANONICAL=tmp_path/'canonical',load_legacy=lambda:SimpleNamespace(System=lambda:object()),
        immutable=write,canonical_lock=lambda *_args,**_kwargs:nullcontext())
    if failure=='controller_conflict':
        def lock(path,**kwargs):
            if path.name=='controller.lock':raise RuntimeError('controller conflict')
            return nullcontext()
        resource.canonical_lock=lock
    monkeypatch.setattr(m,'apis',lambda:(resource,science));monkeypatch.setattr(m,'run_folder',lambda _:folder)
    def guard(*_):raise RuntimeError('fresh baseline guard failed')
    monkeypatch.setattr(m,'guard',guard)
    with pytest.raises(RuntimeError):m.claim_regional_lease(science,'benchmark',{}, {})
    assert not (base/'wave_benchmark/lease.json').exists()


def test_successor_carries_original_parent_deadline_without_reset(m):
    c=m.config();deadline=1792858323.6072176
    assert c['original_global_expires_epoch']==deadline
    assert m.remaining_outer_seconds(c,now=deadline-12000)==12000
    assert m.remaining_outer_seconds(c,now=deadline-12000)<c['outer_seconds']
    with pytest.raises(RuntimeError):m.remaining_outer_seconds(c,now=deadline)
    with pytest.raises(RuntimeError):m.remaining_outer_seconds(c,now=deadline-c['outer_seconds']-1)
    assert 'retirement_aware_orchestration' in str(m.RUNTIME)


def test_whole_future_waves_must_fit_after_active_lease(m):
    leases={'1':dict(expires_epoch=7200)}
    assert m.funded_unused_windows(leases,{},21605,now=0)==['2','3']
    assert m.funded_unused_windows(leases,{},21604,now=0)==['2']
    assert m.funded_unused_windows(leases,{},14404,now=0)==[]
    assert m.regional_remaining_capacity(leases,.5,{},now=0,outer_expires=14404)==5400


def test_benchmark_and_terminal_tails_do_not_create_parent_capacity(m):
    leases={'benchmark':dict(expires_epoch=1200)}
    assert m.funded_unused_windows(leases,{},22805,now=0)==['1','2','3']
    assert m.funded_unused_windows(leases,{},22804,now=0)==['1','2']
    # Once drained early, only unused numerical admissions remain; benchmark
    # time has no compute credit and a terminal numerical tail is discarded.
    leases['1']=dict(expires_epoch=8400)
    assert m.regional_remaining_capacity(leases,.5,{'benchmark':{},'1':{}},now=2000,outer_expires=16404)==5400


def test_existing_lease_cannot_cross_carried_parent_deadline(m):
    with pytest.raises(RuntimeError,match='exceeds original'):
        m.regional_remaining_capacity({'1':dict(expires_epoch=7200)},.5,now=0,outer_expires=7199)


def test_failed_predecessor_identity_and_global_deadline_are_pinned(m,tmp_path,monkeypatch):
    c=m.config();pred=tmp_path/'run';pred.mkdir();monkeypatch.setattr(m,'PREDECESSOR',pred)
    context=dict(run_id='run',expires_epoch=c['original_global_expires_epoch'],
        started_epoch=c['original_global_expires_epoch']-c['outer_seconds'])
    term=dict(status='R151_FINITE_WORKFLOW_GUARD_STOPPED',cleanup_verified=True,cleanup_errors=[],
        source_head='90ff802d09ca9b6712ccaae052d327fb23beaede',new_model_fits=0,baseline_worker_signals=0,AL_launched=False)
    write(pred/'context.json',context);write(pred/'terminal.json',term)
    c.update(failed_predecessor_context_sha256=m.digest(pred/'context.json'),
        failed_predecessor_terminal_sha256=m.digest(pred/'terminal.json'))
    assert m.verify_predecessor(c)==context
    context['expires_epoch']+=60;write(pred/'context.json',context)
    with pytest.raises(RuntimeError,match='predecessor'):m.verify_predecessor(c)
