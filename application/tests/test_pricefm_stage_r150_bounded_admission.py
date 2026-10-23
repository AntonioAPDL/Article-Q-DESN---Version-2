"""Finite prefix admission, immutable benchmark reuse, and atomic MC budgets."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import sys
import types

import pytest

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/500_run_pricefm_stage_r150_bounded_admission.py'


@pytest.fixture
def m(tmp_path,monkeypatch):
    spec=importlib.util.spec_from_file_location('r150_bounded_test',ENTRY)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    monkeypatch.setattr(module,'OUT',tmp_path/'campaign')
    monkeypatch.setattr(module,'PREP',tmp_path/'prep')
    return module


def test_import_and_original_adapter_are_standard_library_only():
    code="import importlib.util,sys;s=importlib.util.spec_from_file_location('bounded',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.producer();assert not any(n in sys.modules for n in ('numpy','scipy','pandas'))"
    subprocess.run([sys.executable,'-B','-c',code,str(ENTRY)],check=True)


@pytest.mark.parametrize('field,value',[('new_benchmark_authorized',True),('new_model_fits',1),
    ('new_geometries',1),('AL_authorized',True),('official_evaluation_authorized',True),
    ('numerical_waves',['1','2','3','4']),('absolute_compute_CPU_ceiling',43200),('branch','B2')])
def test_successor_scope_cannot_expand_frozen_budget_or_science(m,field,value):
    config=m.read(m.CONFIG);config[field]=value
    with pytest.raises(ValueError):m.validate_config(config)


def test_actual_cached_benchmark_funds_entire_D_and_worst_locked_seed0_prefix(m):
    p=m.producer();prep=p.read_preparation();pricing=p.read(p.OUT/'benchmark/branch.json')
    result=m.prefix_contract(prep,pricing)
    assert result['prefix_admitted']
    assert result['D_CPU_seconds']==pytest.approx(7196.446389416988)
    assert result['worst_prefix_CPU_seconds']==pytest.approx(13073.001884687988)
    assert result['original_available_CPU_seconds']==pytest.approx(21786.141934839827)
    assert len(result['all_prospective_seed0_scenarios'])==25
    assert pricing['budget_disposition']=='DEFERRED_NEITHER_FULL_BRANCH_FITS'
    # The imported receipt remains an honest record of the original decision.
    assert prep['source']['head']=='add35d3ea5df7397122bedf6509799cce634538c'
    assert all(t['reuse']['producer']['head']=='0d562470f7112da0e94cc61b4bf18de8a93a5112'
               for t in prep['tasks'] if t['reuse'])


def toy_prices(m):
    prices={'D1':dict(estimated_cpu_seconds=4.),'D2':dict(estimated_cpu_seconds=6.)}
    for package,cost in [('C0',1.),('A',2.),('B',3.)]:
        for name in m.names_for([package],'S',[1,2]):prices[name]=dict(estimated_cpu_seconds=cost)
    return prices


def test_atomic_two_qualifier_extras_fit_at_exact_cumulative_boundary(m):
    decision=m.extra_admission(['D1','D2'],['A','B'],'C0',toy_prices(m),46.)
    assert decision['atomic_qualified_set_admitted']
    assert decision['prefix_projected_CPU_seconds']==10.
    assert decision['extra_projected_CPU_seconds']==36.
    assert decision['cumulative_projected_CPU_seconds']==46.
    assert len(decision['admitted_extra_components'])==18
    assert decision['unfunded_pending']==[]


def test_atomic_two_qualifier_extras_are_all_pending_when_whole_set_exceeds_budget(m):
    decision=m.extra_admission(['D1','D2'],['A','B'],'C0',toy_prices(m),45.)
    assert not decision['atomic_qualified_set_admitted']
    assert decision['qualified']==['A','B']
    assert decision['admitted_extra_components']==[]
    assert len(decision['unfunded_pending'])==18
    assert decision['status']=='DEFERRED_UNFUNDED_MATCHED_EXTRAS'
    # A cheaper single nominee fits, but the policy does not discard B to admit A.
    assert m.extra_admission(['D1','D2'],['A'],'C0',toy_prices(m),45.)['atomic_qualified_set_admitted']


def test_control_extra_seeds_are_shared_and_not_double_charged(m):
    decision=m.extra_admission(['D1','D2'],['A','B'],'C0',toy_prices(m),100.)
    assert len(set(decision['required_extra_components']))==18
    assert sum('_C0_' in n for n in decision['required_extra_components'])==6
    assert decision['extra_projected_CPU_seconds']==6*1.+6*2.+6*3.


def test_no_qualifiers_means_no_extra_compute_or_control_seed_work(m):
    decision=m.extra_admission(['D1','D2'],[],'C0',toy_prices(m),10.)
    assert decision['atomic_qualified_set_admitted']
    assert decision['required_extra_components']==[]
    assert decision['extra_projected_CPU_seconds']==0.


def test_full_required_but_unfunded_MC_never_reports_completion(m,monkeypatch):
    packages=[dict(package_id=p) for p in ('C0','A','B')]
    prefix=m.names_for(['C0','A','B'],'D',[0])+m.names_for(['C0','A','B'],'S',[0])
    extra=m.extra_admission(['D1','D2'],['A','B'],'C0',toy_prices(m),45.)
    prep=dict(packages=packages,control='C0',pricing=dict(task_estimates={},resource_projection={}))
    monkeypatch.setattr(m,'read_preparation',lambda:prep)
    monkeypatch.setattr(m,'task_complete',lambda n:n in prefix)
    m.write(m.OUT/'decisions/nominees.seal.json',{})
    m.write(m.OUT/'decisions/extra_seeds.seal.json',{})
    monkeypatch.setattr(m,'read_decision',lambda n:dict(nominees=['A','B']) if n=='nominees' else extra)
    state=m.queue_state()
    assert state['phase']=='MATCHED_MC_UNFUNDED_PENDING'
    assert state['ready']==[] and not state['terminal'] and not state['scientific_complete']
    assert len(state['pending'])==18 and len(state['unfunded_pending'])==18
    with pytest.raises(RuntimeError,match='incomplete'):m.finalize()


def test_new_benchmark_is_refused_before_guard_import_or_unit_work(m,monkeypatch):
    monkeypatch.setattr(m,'guard',lambda *args:pytest.fail('no benchmark admission allowed'))
    with pytest.raises(RuntimeError,match='forbids a new benchmark'):m.worker('__benchmark__',15,'missing')


def test_numerical_worker_guard_still_precedes_import_or_model_access(m,monkeypatch):
    def refused(*args):raise RuntimeError('actual policy gate')
    monkeypatch.setattr(m,'guard',refused)
    monkeypatch.setattr(m,'read_preparation',lambda:pytest.fail('must guard first'))
    with pytest.raises(RuntimeError,match='actual policy gate'):m.worker('task',15,'missing')


def test_changed_import_receipt_is_refused_before_preparation(m,tmp_path,monkeypatch):
    config=m.read(m.CONFIG);bad=tmp_path/'changed_import.json';m.write(bad,{})
    config['benchmark_import']=str(bad);config['benchmark_import_pins']={str(bad):'wrong-hash'}
    path=tmp_path/'config.json';m.write(path,config);monkeypatch.setattr(m,'CONFIG',path)
    with pytest.raises(RuntimeError,match='pinned original artifact'):m.build_preparation(dict(head='audit-only'))


def test_completed_actual_CPU_releases_unused_reservation_without_new_budget(m):
    prices=toy_prices(m)
    conservative=m.extra_admission(['D1','D2'],['A','B'],'C0',prices,40.)
    assert not conservative['atomic_qualified_set_admitted']
    actual={'D1':dict(charged_CPU_seconds=2.),'D2':dict(charged_CPU_seconds=2.)}
    released=m.extra_admission(['D1','D2'],['A','B'],'C0',prices,40.,actual)
    assert released['atomic_qualified_set_admitted']
    assert released['cumulative_projected_CPU_seconds']==40.
    assert released['original_available_CPU_seconds']==40.
    assert released['qualified']==conservative['qualified']


def test_actual_CPU_overrun_raises_charge_instead_of_capping_it(m):
    charge=m.charge_observations(100.,[120.])
    assert charge['charged_CPU_seconds']==125.
    assert charge['observed_overrun']
    assert not charge['hard_CPU_quota'] and not charge['exact_exit_CPU_measurement']


@pytest.mark.parametrize('observed',[[],[None],[float('nan')],[-1.],[True]])
def test_missing_or_malformed_observation_keeps_full_frozen_reservation(m,observed):
    charge=m.charge_observations(100.,observed)
    assert charge['charged_CPU_seconds']==100.
    assert charge['retained_full_frozen_reservation']


def CPU_fixture(m,tmp_path,monkeypatch):
    task=dict(name='task',scientific_identity_sha256='science-id',reuse=None)
    prep=dict(source=dict(head='bounded-source'),pricing=dict(task_estimates={'task':dict(estimated_cpu_seconds=100.)}))
    monkeypatch.setattr(m,'task_by_name',lambda *args:task)
    monkeypatch.setattr(m,'task_complete',lambda name:True)
    monkeypatch.setattr(m.time,'process_time',lambda:3.)
    monkeypatch.setattr(m.resource,'getrusage',lambda kind:types.SimpleNamespace(ru_utime=1.,ru_stime=1.))
    policy=tmp_path/'policy.json';m.write(policy,dict(owned=True))
    m.write(m.OUT/'tasks_done/task/completed_evidence.json',dict(scientific_packet='sealed'))
    return task,prep,policy


def begin_CPU(m,task,prep,policy,invocation):
    path=policy.with_name(invocation+'.json')
    receipt=dict(task=task['name'],source_head=prep['source']['head'],worker_invocation_id=invocation)
    m.write(path,receipt)
    return m.start_CPU_attempt(task,prep,receipt,path)


def test_actual_CPU_receipt_binds_source_task_policy_and_final_prediction(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    folder,started=begin_CPU(m,task,prep,policy,'owned-invocation')
    m.finish_CPU_attempt(folder,started,True)
    charge=m.completed_CPU_charge('task',prep)
    assert charge['charged_CPU_seconds']==10. # observed process3 + terminated children2 + tail5
    assert charge['credit_eligible']
    assert charge['completed_receipts_bound_to_final_prediction_seal']
    m.write(m.OUT/'tasks_done/task/completed_evidence.json',dict(scientific_packet='changed'))
    refused=m.completed_CPU_charge('task',prep)
    assert refused['charged_CPU_seconds']==100. and not refused['credit_eligible']


def test_partial_resume_without_earlier_CPU_provenance_cannot_release_headroom(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    m.write(m.OUT/'checkpoints/task/clock00_part000/completed_evidence.json',dict(prior_work=True))
    folder,started=begin_CPU(m,task,prep,policy,'resumed-invocation')
    m.finish_CPU_attempt(folder,started,True)
    charge=m.completed_CPU_charge('task',prep)
    assert not charge['credit_eligible']
    assert charge['charged_CPU_seconds']==100.
    assert 'no earlier owned CPU attempt' in charge['receipt_errors'][0]['error']


def test_verified_checkpoint_attempts_sum_all_observed_CPU_including_tail_allowances(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    first,started1=begin_CPU(m,task,prep,policy,'partial-owned')
    m.finish_CPU_attempt(first,started1,False)
    m.write(m.OUT/'checkpoints/task/clock00_part000/completed_evidence.json',dict(prior_work=True))
    second,started2=begin_CPU(m,task,prep,policy,'completed-owned')
    m.finish_CPU_attempt(second,started2,True)
    charge=m.completed_CPU_charge('task',prep)
    assert charge['credit_eligible'] and charge['observed_attempts']==2
    assert charge['charged_CPU_seconds']==20. # two separately metered attempts, each plus5s


def test_unsealed_earlier_attempt_keeps_frozen_reservation_even_after_successful_resume(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    begin_CPU(m,task,prep,policy,'abruptly-interrupted')
    m.write(m.OUT/'checkpoints/task/clock00_part000/completed_evidence.json',dict(prior_work=True))
    folder,started=begin_CPU(m,task,prep,policy,'resumed-completed')
    m.finish_CPU_attempt(folder,started,True)
    charge=m.completed_CPU_charge('task',prep)
    assert not charge['credit_eligible']
    assert charge['unknown_or_malformed_attempts']==1
    assert charge['charged_CPU_seconds']==110. # frozen100 unknown + known5 observed + tail5


def test_negative_individual_CPU_amount_is_malformed_even_if_positive_total_matches(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    folder,started=begin_CPU(m,task,prep,policy,'owned-invocation')
    m.finish_CPU_attempt(folder,started,True)
    observed=m.read(folder/'observed.json')
    observed.update(observed_process_CPU_seconds=-1.,observed_terminated_children_CPU_seconds=6.,observed_total_CPU_seconds=5.)
    m.write(folder/'observed.json',observed)
    m.write(folder/'observed.seal.json',dict(sha256=m.digest(folder/'observed.json'),source=prep['source']))
    charge=m.completed_CPU_charge('task',prep)
    assert charge['charged_CPU_seconds']==100. and not charge['credit_eligible']
    assert 'invalid observed CPU amount' in charge['receipt_errors'][0]['error']


def test_CPU_credit_requires_policy_contents_as_well_as_pinned_bytes(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    m.write(policy,dict(task='foreign-task',source_head='foreign-source',worker_invocation_id='owned-invocation'))
    folder,started=m.start_CPU_attempt(task,prep,dict(worker_invocation_id='owned-invocation'),policy)
    m.finish_CPU_attempt(folder,started,True)
    charge=m.completed_CPU_charge('task',prep)
    assert charge['charged_CPU_seconds']==100. and not charge['credit_eligible']
    assert 'policy task/source/invocation differs' in charge['receipt_errors'][0]['error']


def test_only_surviving_partial_CPU_receipts_cannot_replace_missing_completed_receipt(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    folder,started=begin_CPU(m,task,prep,policy,'partial-observation-only')
    m.finish_CPU_attempt(folder,started,False)
    # The scientific packet exists, but no CPU observation proves its final work.
    charge=m.completed_CPU_charge('task',prep)
    assert not charge['credit_eligible'] and charge['verified_final_CPU_receipts']==0
    assert not charge['completed_receipts_bound_to_final_prediction_seal']
    assert charge['charged_CPU_seconds']==110. # known partial5+tail5 plus full final-work reservation100


def test_deleted_referenced_earlier_attempt_keeps_unknown_work_reservation(m,tmp_path,monkeypatch):
    task,prep,policy=CPU_fixture(m,tmp_path,monkeypatch)
    first,started1=begin_CPU(m,task,prep,policy,'earlier-owned-attempt')
    m.finish_CPU_attempt(first,started1,False)
    m.write(m.OUT/'checkpoints/task/clock00_part000/completed_evidence.json',dict(prior_work=True))
    second,started2=begin_CPU(m,task,prep,policy,'completed-owned-attempt')
    m.finish_CPU_attempt(second,started2,True)
    (first/'started.json').unlink()
    charge=m.completed_CPU_charge('task',prep)
    assert not charge['credit_eligible'] and charge['verified_final_CPU_receipts']==1
    assert charge['missing_prior_invocations']==['earlier-owned-attempt']
    assert charge['charged_CPU_seconds']==110. # final observation5+tail5 and unknown earlier work100
