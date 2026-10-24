"""Resource recovery fault boundaries; fake services, real competing claimants."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
from unittest import mock
import pytest

ENTRY=Path(__file__).resolve().parents[1]/'scripts/pricefm/501_recover_pricefm_stage_r150.py'
SPEC=importlib.util.spec_from_file_location('r151_resource_tested',ENTRY)
M=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(M)


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))


def root_fixture(tmp_path):
    root=tmp_path/'runtime';write(root/'wave_1/lease.json',{'consumed':True});return root


@pytest.mark.parametrize('wave',['0','1','4','benchmark'])
def test_only_two_original_unused_admissions(tmp_path,wave):
    with pytest.raises(RuntimeError,match='only unused'):
        M._claim_unused(root_fixture(tmp_path),wave,'admission',{},lambda:None)


def test_existing_nonexpired_lease_never_joined(tmp_path):
    root=root_fixture(tmp_path);first=M._claim_unused(root,'2','admission',{},lambda:None,now=100,boot_id='boot')
    with pytest.raises(RuntimeError,match='consumed'):
        M._claim_unused(root,'2','admission',{},lambda:None,now=101,boot_id='boot')
    assert M.read(root/'wave_2/lease.json')==first


def test_expired_lease_cannot_be_replaced(tmp_path):
    root=root_fixture(tmp_path);M._claim_unused(root,'2','a',{},lambda:None,now=0,boot_id='b')
    with pytest.raises(RuntimeError,match='consumed'):M._claim_unused(root,'2','a',{},lambda:None,now=100000,boot_id='b')


def test_wave_three_requires_wave_two(tmp_path):
    with pytest.raises(RuntimeError,match='sequence'):
        M._claim_unused(root_fixture(tmp_path),'3','a',{},lambda:None)


def test_empty_completion_list_cannot_restore_wave_one(tmp_path):
    root=root_fixture(tmp_path);write(root/'workflow_terminal.json',{'completed_admissions':[]})
    with pytest.raises(RuntimeError,match='only unused'):M._claim_unused(root,'1','a',{},lambda:None)


def test_unknown_namespace_defers_without_new_lease(tmp_path):
    root=root_fixture(tmp_path);(root/'wave_4').mkdir()
    with pytest.raises(RuntimeError,match='namespace'):M._claim_unused(root,'2','a',{},lambda:None)
    assert not (root/'wave_2/lease.json').exists()


def test_validation_error_precedes_claim(tmp_path):
    root=root_fixture(tmp_path)
    def reject():raise RuntimeError('drain ambiguity')
    with pytest.raises(RuntimeError,match='drain ambiguity'):M._claim_unused(root,'2','a',{},reject)
    assert not (root/'wave_2/lease.json').exists()


def claimant_script():
    return """import importlib.util,sys,os
s=importlib.util.spec_from_file_location('claim',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
try:
 m._claim_unused(sys.argv[2],'2','a',{},lambda:None,now=100,boot_id='b')
 if len(sys.argv)>3:os._exit(23)
except RuntimeError:sys.exit(7)
"""


def test_real_subprocess_claimants_exactly_one_and_no_nested_lock(tmp_path):
    root=root_fixture(tmp_path);command=[sys.executable,'-B','-c',claimant_script(),str(ENTRY),str(root)]
    first=subprocess.Popen(command);second=subprocess.Popen(command)
    assert sorted([first.wait(timeout=10),second.wait(timeout=10)])==[0,7]
    lease=M.read(root/'wave_2/lease.json');assert lease['seconds']==7200 and lease['nonrenewing']
    assert lease['source_head']==M.SCIENCE_HEAD and lease['expires_epoch']==7300


def test_postclaim_crash_consumes_admission(tmp_path):
    root=root_fixture(tmp_path);command=[sys.executable,'-B','-c',claimant_script(),str(ENTRY),str(root),'crash']
    assert subprocess.run(command,timeout=10).returncode==23
    assert (root/'wave_2/lease.json').exists()
    with pytest.raises(RuntimeError,match='consumed'):M._claim_unused(root,'2','a',{},lambda:None)


def test_controller_lock_nonblocking_conflict_no_deadlock(tmp_path):
    path=tmp_path/'controller.lock'
    with M.canonical_lock(path):
        with pytest.raises(RuntimeError,match='already owned'):
            with M.canonical_lock(path):pass


def test_immutable_intent_never_overwritten(tmp_path):
    path=tmp_path/'intent.json';M.immutable(path,{'uuid':'one'})
    with pytest.raises(FileExistsError):M.immutable(path,{'uuid':'two'})
    assert M.read(path)=={'uuid':'one'}


def capsule(name='controller',pid=101):
    r=M.load_legacy();unit='pricefm-r150-test-'+name+'.service'
    argv=['/python','-B',str(ENTRY),'test-hold','--controller-unit',unit]
    props={key:'' for key in r.UNIT_PROPERTIES}
    props.update(Id=unit,LoadState='loaded',ActiveState='active',MainPID=str(pid),InvocationID='inv-'+name,
        ControlGroup='/user.slice/test/'+unit,ExecStart='{ argv[]='+' '.join(argv)+' ; ignore_errors=no ; }',
        Description='owned '+name,WorkingDirectory=str(M.SCIENCE_ROOT),KillMode='control-group',Restart='no',
        CPUSchedulingPolicy='0',IOSchedulingClass='3',RuntimeMaxUSec='2h')
    saved=dict(unit=unit,argv=argv,description=props['Description'],expected_cgroup=props['ControlGroup'],attested=copy.deepcopy(props),
        runtime_seconds=7200,source_entry_path=str(ENTRY),source_entry_sha256=M.digest(ENTRY),source_head='new')
    return saved,props


class FakeSystem:
    def __init__(self,records):
        self.props={s['unit']:copy.deepcopy(p) for s,p in records}
        self.groups={p['ControlGroup']:[int(p['MainPID'])] for _,p in records};self.stops=[]
    def unit(self,name):return copy.deepcopy(self.props[name])
    def members(self,cg):return list(self.groups.get(cg,[]))
    def stop(self,name):
        self.stops.append(name);p=self.props[name];self.groups[p['ControlGroup']]=[];p.update(ActiveState='inactive',MainPID='0',ControlGroup='')


def test_whole_owned_tree_rss_collects_coordinator_and_descendants_once():
    a,ap=capsule('coordinator',101);b,bp=capsule('wave',102);w,wp=capsule('worker',103)
    system=FakeSystem([(a,ap),(b,bp),(w,wp)])
    system.groups[ap['ControlGroup']]=[101,104];system.groups[bp['ControlGroup']]=[102,104]
    system.groups[wp['ControlGroup']]=[103,105]
    assert M.owned_groups(system,[a,b],[w])==[101,102,103,104,105]


def test_draining_predecessor_members_included():
    saved,props=capsule('old',101);system=FakeSystem([(saved,props)])
    system.props[saved['unit']].update(ActiveState='inactive',MainPID='0',ControlGroup='')
    system.groups[saved['expected_cgroup']]=[900]
    assert M.owned_groups(system,[],[saved])==[900]


def test_missing_membership_identity_fails_closed():
    saved,props=capsule();saved.pop('attested');saved.pop('expected_cgroup');props['ControlGroup']=''
    system=FakeSystem([(saved,props)])
    with pytest.raises(RuntimeError,match='no cgroup'):M.owned_groups(system,[saved],[])


@pytest.mark.parametrize('field,value',[('InvocationID','other'),('ControlGroup','/user.slice/foreign'),('ExecStart','foreign')])
def test_replaced_lifetime_never_signalled(field,value):
    saved,props=capsule();system=FakeSystem([(saved,props)]);system.props[saved['unit']][field]=value
    with pytest.raises(RuntimeError,match='mismatch'):M.drain_exact(system,saved,timeout=0)
    assert not system.stops


def test_missing_terminal_still_allows_exact_owned_drain():
    saved,props=capsule();system=FakeSystem([(saved,props)])
    assert M.drain_exact(system,saved,timeout=0)['drained'];assert system.stops==[saved['unit']]


def test_rapid_exit_remembers_expected_cgroup():
    saved,props=capsule();saved.pop('attested');system=FakeSystem([(saved,props)])
    system.props[saved['unit']].update(LoadState='not-found',ActiveState='inactive',MainPID='0',ControlGroup='')
    system.groups[saved['expected_cgroup']]=[900]
    with pytest.raises(RuntimeError,match='did not drain'):M.drain_exact(system,saved,timeout=0)
    assert not system.stops


def test_fragmentation_not_just_aggregate_cpu():
    tasks=[dict(name=str(i),estimated_wall_seconds=60) for i in range(3)]
    projection=M.scheduling_projection(tasks,100,0)
    assert sum(t['estimated_wall_seconds'] for t in tasks)<200
    assert not projection['fits']


def test_two_wave_packing_records_each_task_once():
    tasks=[dict(name=str(i),estimated_wall_seconds=1000) for i in range(12)]
    p=M.scheduling_projection(tasks,1000,1)
    assert p['fits'] and len(p['allocation'])==12
    assert len(set(t['task'] for t in p['allocation']))==12


def test_remaining_time_never_renews_elapsed_wave(tmp_path):
    with mock.patch.object(M,'CANONICAL',tmp_path):
        c={'idle_share':.5};leases={'2':{'expires_epoch':7200}}
        assert M.remaining_capacity(c,leases,now=0)==10800
        assert M.remaining_capacity(c,leases,now=5400)==5400
        assert M.remaining_capacity(c,leases,now=100000)==5400 # only unclaimed3
        write(tmp_path/'wave_3/terminal.json',{})
        assert M.remaining_capacity(c,dict(leases,**{'3':{'expires_epoch':7200}}),now=100000)==0


def test_global_replacement_token_consumed_before_any_stop(tmp_path):
    saved,_=capsule('worker');saved['task']='same-task';saved['cpu']=18
    lease={'lease_id':'same-lease','expires_epoch':10000};c={'cleanup_seconds':1800}
    with mock.patch.object(M,'CANONICAL',tmp_path),mock.patch.object(M.time,'time',return_value=100):
        token=M.reserve_replacement(c,'recovery',saved,lease,{'fits':True})
        assert M.read(tmp_path/'r151_replacement_token.json')==token
        assert token['lease_id']=='same-lease' and token['task']=='same-task'
        with pytest.raises(RuntimeError,match='already consumed'):M.reserve_replacement(c,'different-recovery',saved,lease,{'fits':True})


def test_replacement_capacity_or_deadline_denial_leaves_no_token(tmp_path):
    saved,_=capsule('worker');saved['task']='task'
    with mock.patch.object(M,'CANONICAL',tmp_path),mock.patch.object(M.time,'time',return_value=100):
        with pytest.raises(RuntimeError,match='capacity'):M.reserve_replacement({'cleanup_seconds':1800},'r',saved,{'expires_epoch':10000},{'fits':False})
        with pytest.raises(RuntimeError,match='capacity'):M.reserve_replacement({'cleanup_seconds':1800},'r',saved,{'expires_epoch':101},{'fits':True})
        assert not (tmp_path/'r151_replacement_token.json').exists()


def fake_science(tmp_path):
    prices={n:dict(estimated_cpu_seconds=c,estimated_wall_seconds=c/.5) for n,c in [('d',10),('C0S',10),('aS',20),('bS',30),('cS',40)]}
    prep={'packages':[{'package_id':v} for v in ['C0','a','b','c']],'control':'C0','pricing':{'task_estimates':prices}}
    science=SimpleNamespace(OUT=tmp_path,read_preparation=lambda:prep,names_for=lambda ids,mode,seeds:[v+'S' for v in ids],task_complete=lambda n:False)
    return science,prep


def test_d_gate_includes_unselected_worst_s_prefix_and_replacement(tmp_path):
    science,prep=fake_science(tmp_path);c={'replacement_reserve_CPU_seconds':5,'historical_charge_CPU_seconds':2,'original_adjusted_CPU_seconds':1000,'idle_share':.5}
    q={'phase':'DETERMINISTIC_POOL','pending':['d']}
    with mock.patch.object(M,'CANONICAL',tmp_path),mock.patch.object(M,'recovery_attempts',return_value=[]):
        p=M.resource_projection(c,science,q,{},now=0)
    # d + C0 + two costliest candidate S bundles + reserve.
    assert p['remaining_projected_CPU_seconds']==105
    assert p['original_cumulative_CPU_seconds']==107
    assert set(v['task'] for v in p['packing']['allocation'])=={'d','C0S','__nominee1_split1_S_seed0_envelope__','__nominee2_split1_S_seed0_envelope__','__single_replacement_reserve__'}


def test_missing_cpu_receipt_retains_frozen_reservation(tmp_path):
    science,prep=fake_science(tmp_path);saved={'task':'d','attested':{'InvocationID':'missing'}}
    assert M.attempt_charge(saved,science,prep)==10


def test_altered_new_source_fails_before_service_side_effect(tmp_path):
    source={'root':str(M.ROOT),'head':'new','runtime_sha256':{},'idle_wrapper_sha256':'wrong'}
    with mock.patch.object(M,'git',side_effect=lambda *args:'new' if args[0]=='rev-parse' else ''):
        with pytest.raises(RuntimeError,match='wrapper'):M.verify_new_source(source)


def test_control_actual_executable_hash_not_working_directory():
    saved,props=capsule();system=FakeSystem([(saved,props)]);saved['source_entry_sha256']='bad'
    r=M.load_legacy()
    with mock.patch.object(r,'process',return_value={'scheduler':0,'affinity':list(range(15,30))}),mock.patch.object(M,'git',return_value='new'):
        with pytest.raises(RuntimeError,match='executable source'):M.verify_control(system,saved,{'cpus':list(range(15,30))})


def test_control_requires_parent_dependency():
    saved,props=capsule();system=FakeSystem([(saved,props)]);r=M.load_legacy()
    with mock.patch.object(r,'process',return_value={'scheduler':0,'affinity':list(range(15,30))}),mock.patch.object(M,'git',return_value='new'):
        with pytest.raises(RuntimeError,match='death binding'):M.verify_control(system,saved,{'cpus':list(range(15,30))},required_parent='parent')


def test_control_rejects_child_idle_or_wrong_affinity():
    saved,props=capsule();system=FakeSystem([(saved,props)]);r=M.load_legacy()
    with mock.patch.object(r,'process',return_value={'scheduler':5,'affinity':[15]}),mock.patch.object(M,'git',return_value='new'):
        with pytest.raises(RuntimeError,match='lifecycle'):M.verify_control(system,saved,{'cpus':list(range(15,30))})


def test_no_global_rebinding_of_immutable_modules():
    source=ENTRY.read_text()
    for text in ('r.ROOT =','r.guard =','r.workflow_members =','science.ROOT =','science.guard =','lease_once('):assert text not in source
    assert 'os.kill(' not in source and 'os.killpg(' not in source


def guard_fixture(tmp_path):
    coordinator,cp=capsule('coordinator',101);base,bp=capsule('baseline',200)
    system=FakeSystem([(coordinator,cp),(base,bp)])
    c={'cpus':list(range(15,30)),'AT_terminal':str(tmp_path/'AT.json'),'disk_path':str(tmp_path),
       'min_available_memory_gib':192,'min_disk_gib':80,'max_owned_rss_gib':24}
    write(Path(c['AT_terminal']),{'status':'quarantined'})
    proc=dict(pid=200,start_ticks=5,boot_id='boot',cmdline_sha256='baseline')
    admission={'handoff':{'heartbeat':1},'baseline':{'units':{base['unit']:{'properties':bp,'process':proc}},'AT_terminal_sha256':M.digest(c['AT_terminal'])}}
    stack=__import__('contextlib').ExitStack();r=M.load_legacy()
    stack.enter_context(mock.patch.object(M,'verify_release',side_effect=lambda release:release.setdefault('original_global_expires_epoch',100000000000.)))
    stack.enter_context(mock.patch.object(M,'retirement_contract',return_value={'retired_unit':'outside-fixture'}))
    stack.enter_context(mock.patch.object(M,'assert_capsules_drained',return_value=True))
    stack.enter_context(mock.patch.object(M,'verify_control',return_value=cp))
    stack.enter_context(mock.patch.object(r,'assert_parent_policy'))
    stack.enter_context(mock.patch.object(r,'verify_baseline_sources'))
    stack.enter_context(mock.patch.object(r,'handoff_snapshot',return_value={'heartbeat':2}))
    stack.enter_context(mock.patch.object(r,'process',return_value=proc))
    stack.enter_context(mock.patch.object(r,'memory_available_gib',return_value=300))
    stack.enter_context(mock.patch.object(r,'rss_gib',return_value=1))
    stack.enter_context(mock.patch.object(__import__('shutil'),'disk_usage',return_value=SimpleNamespace(free=200*1024**3)))
    return stack,r,c,system,admission,coordinator


def test_preclaim_guard_accepts_none_without_reviving_old_workflow(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    with stack,mock.patch.object(r,'workflow_members',side_effect=AssertionError('dead499mustneverberequired')):
        result=M.baseline_guard(c,system,admission,coordinator,None,None,[],{})
    assert result['active_workers']==0 and result['owned_pids']==[101]


@pytest.mark.parametrize('available,rss,disk',[(191,1,200),(300,24.01,200),(300,1,79)])
def test_floor_or_whole_rss_violation_stops_preclaim(tmp_path,available,rss,disk):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    with stack,mock.patch.object(r,'memory_available_gib',return_value=available),mock.patch.object(r,'rss_gib',return_value=rss),mock.patch.object(__import__('shutil'),'disk_usage',return_value=SimpleNamespace(free=disk*1024**3)):
        with pytest.raises(RuntimeError,match='whole-owned-RSS'):
            M.baseline_guard(c,system,admission,coordinator,None,None,[],{})


def test_changed_baseline_lifetime_defers_before_claim(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    baseline=next(iter(admission['baseline']['units']))
    system.props[baseline]['InvocationID']='newbaseline'
    with stack,pytest.raises(RuntimeError,match='baseline lifecycle'):
        M.baseline_guard(c,system,admission,coordinator,None,None,[],{})
    assert not system.stops


def test_changed_at_terminal_defers_before_claim(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    write(Path(c['AT_terminal']),{'status':'new'})
    with stack,pytest.raises(RuntimeError,match='AT terminal'):
        M.baseline_guard(c,system,admission,coordinator,None,None,[],{})
    assert not system.stops


def test_stale_or_regressed_handoff_defers_before_claim(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    with stack,mock.patch.object(r,'handoff_snapshot',side_effect=RuntimeError('stale heartbeat')),pytest.raises(RuntimeError,match='stale'):
        M.baseline_guard(c,system,admission,coordinator,None,None,[],{})
    assert not system.stops


def test_changed_source_defers_before_any_service_read(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    with stack,mock.patch.object(M,'verify_release',side_effect=RuntimeError('dual source changed')),mock.patch.object(system,'unit',side_effect=AssertionError('no service action')),pytest.raises(RuntimeError,match='dual source'):
        M.baseline_guard(c,system,admission,coordinator,None,None,[],{})


def test_numerical_lease_mutation_rejected(tmp_path):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    lease={'source_head':M.SCIENCE_HEAD,'wave':'2','boot_id':'boot','expires_epoch':1000}
    write(tmp_path/'wave_2/lease.json',dict(lease,expires_epoch=2000))
    with stack,mock.patch.object(M,'CANONICAL',tmp_path),mock.patch.object(M,'boot',return_value='boot'),mock.patch.object(M.time,'time',return_value=100),pytest.raises(RuntimeError,match='lease changed'):
        M.baseline_guard(c,system,admission,coordinator,None,lease,[],{})


def cpu_receipt_fixture(tmp_path,*,completed=False,total=30):
    name='task';inv='inv';policy=tmp_path/'policy.json';write(policy,{'worker_invocation_id':inv,'task':name,'source_head':M.SCIENCE_HEAD})
    source={'head':M.SCIENCE_HEAD};task={'scientific_identity_sha256':'identity'}
    prep={'source':source,'pricing':{'task_estimates':{name:{'estimated_cpu_seconds':10.}}}}
    saved={'task':name,'attested':{'InvocationID':inv},'policy_receipt':str(policy)}
    start=dict(source=source,task=name,policy_invocation_id=inv,scientific_identity_sha256='identity',policy_receipt_path=str(policy),policy_receipt_sha256=M.digest(policy))
    final=tmp_path/'tasks_done'/name/'completed_evidence.json';write(final,{'seal':'final'})
    observed=dict(start,completed_component=completed,post_observation_exit_allowance_CPU_seconds=5.,observed_process_CPU_seconds=total,
        observed_terminated_children_CPU_seconds=0,observed_total_CPU_seconds=total,task_final_seal_sha256=M.digest(final) if completed else None)
    folder=tmp_path/'cpu_accounting'/name/inv;write(folder/'started.json',start);write(folder/'observed.json',observed)
    write(folder/'observed.seal.json',{'sha256':M.digest(folder/'observed.json'),'source':source})
    science=SimpleNamespace(OUT=tmp_path,task_by_name=lambda n,p:task,task_complete=lambda n:completed)
    return science,prep,saved,folder


def test_known_partial_cpu_overrun_increases_charge(tmp_path):
    science,prep,saved,_=cpu_receipt_fixture(tmp_path,completed=False,total=30)
    assert M.attempt_charge(saved,science,prep)==35


def test_partial_small_observation_cannot_earn_credit(tmp_path):
    science,prep,saved,_=cpu_receipt_fixture(tmp_path,completed=False,total=1)
    assert M.attempt_charge(saved,science,prep)==10


def test_complete_final_bound_cpu_can_earn_credit(tmp_path):
    science,prep,saved,_=cpu_receipt_fixture(tmp_path,completed=True,total=1)
    assert M.attempt_charge(saved,science,prep)==6


def test_cpu_final_seal_change_retains_reservation(tmp_path):
    science,prep,saved,_=cpu_receipt_fixture(tmp_path,completed=True,total=1)
    write(tmp_path/'tasks_done/task/completed_evidence.json',{'seal':'changed'})
    assert M.attempt_charge(saved,science,prep)==10


def test_live_attempt_overrun_increases_charge_without_finished_sidecar(tmp_path):
    science,prep,saved,folder=cpu_receipt_fixture(tmp_path,completed=False,total=1)
    (folder/'observed.json').unlink();saved['process']=dict(pid=100,start_ticks=1,boot_id='boot')
    r=M.load_legacy()
    with mock.patch.object(r,'process',return_value=dict(saved['process'],argv=['execchanged'])),mock.patch.object(r,'cpu_seconds',return_value=30):
        assert M.attempt_charge(saved,science,prep)==35


def test_live_pid_reuse_does_not_charge_foreign_cpu(tmp_path):
    science,prep,saved,folder=cpu_receipt_fixture(tmp_path,completed=False,total=1)
    (folder/'observed.json').unlink();saved['process']=dict(pid=100,start_ticks=1,boot_id='boot')
    r=M.load_legacy()
    with mock.patch.object(r,'process',return_value=dict(pid=100,start_ticks=2,boot_id='boot')),mock.patch.object(r,'cpu_seconds',side_effect=AssertionError('foreignCPU')):
        assert M.attempt_charge(saved,science,prep)==10


def test_token_without_drain_proof_retains_full_reserve(tmp_path):
    write(tmp_path/'r151_replacement_token.json',{'old_unit':'worker'})
    with mock.patch.object(M,'CANONICAL',tmp_path):assert M.replacement_reserve({'replacement_reserve_CPU_seconds':99},[])==99


def test_exact_drained_predecessor_retires_risk_but_not_attempt_charge(tmp_path):
    token={'old_unit':'worker','old_invocation_id':'inv','lease_id':'lease'};write(tmp_path/'r151_replacement_token.json',token)
    proof={'token_sha256':M.digest(tmp_path/'r151_replacement_token.json'),'old_unit':'worker','lease_id':'lease',
        'drain':{'cleanup_verified':True,'cleanup_errors':[],'cleanup':[{'drained':True}]}}
    write(tmp_path/'r151_replacement_drain.json',proof)
    attempts=[{'unit':'worker','attested':{'InvocationID':'inv'}}]
    with mock.patch.object(M,'CANONICAL',tmp_path):
        assert M.replacement_reserve({'replacement_reserve_CPU_seconds':99},attempts)==0
        assert M.replacement_reserve({'replacement_reserve_CPU_seconds':99},[])==99


def test_phase_barrier_and_fixed_active_slot_respected():
    tasks=[dict(name='d',phase=0,estimated_wall_seconds=80),dict(name='s',phase=1,estimated_wall_seconds=60,fixed_slot=0)]
    # S cannot begin before D completed, including on the other free worker.
    p=M.scheduling_projection(tasks,200,0)
    assert p['fits']
    a={v['task']:v for v in p['allocation']};assert a['s']['start']>=a['d']['end'] and a['s']['slot']==0


def test_worst_initial_s_plus_retry_has_a_concrete_feasible_partition():
    tasks=[dict(name='d'+str(i),phase=0,estimated_wall_seconds=100) for i in range(63)]
    tasks += [dict(name='s'+str(i),phase=1,estimated_wall_seconds=wall) for i,wall in enumerate([1752,1752,1752,1359,1359,1258,1258])]
    p=M.scheduling_projection(tasks,5400,1);assert p['fits']
    d_end=max(v['end'] for v in p['allocation'] if v['phase']==0)
    assert min(v['start'] for v in p['allocation'] if v['phase']==1)>=d_end


def test_startup_intent_persists_before_service_side_effect(tmp_path):
    parent,pp=capsule('parent');system=FakeSystem([(parent,pp)]);c={'cpus':list(range(15,30))}
    unit='pricefm-r150-test-new.service';argv=['/python','-B',str(ENTRY),'test-hold','--controller-unit',unit]
    def start(name,description,command,**kwargs):
        intent=M.read(tmp_path/'intent.json');assert intent['unit']==name and intent['argv']==command
        props=dict(pp,Id=name,Description=description,InvocationID='newinv',ControlGroup='/user.slice/test/'+name,
            ExecStart='{ argv[]='+' '.join(command)+' ; ignore_errors=no ; }',BindsTo=parent['unit'],After=parent['unit'],RuntimeMaxUSec='1min')
        system.props[name]=props;system.groups[props['ControlGroup']]=[101]
    with mock.patch.object(system,'start',side_effect=start,create=True),mock.patch.object(M,'git',return_value='new'),mock.patch.object(M,'verify_control'):
        saved=M.start_control(system,c,tmp_path,'test',argv,60,parent=parent)
    assert saved['attested']['InvocationID']=='newinv' and M.read(tmp_path/'intent.json')['source_entry_path']==str(ENTRY)
    assert (tmp_path/'attestation.json').exists()


def test_startup_failure_preserves_original_error_and_owned_cleanup(tmp_path):
    parent,pp=capsule('parent');system=FakeSystem([(parent,pp)]);c={'cpus':list(range(15,30))}
    unit='pricefm-r150-test-new.service';argv=['/python','-B',str(ENTRY),'test-hold','--controller-unit',unit]
    def start(name,description,command,**kwargs):
        props=dict(pp,Id=name,Description=description,InvocationID='newinv',ControlGroup='/user.slice/test/'+name,
            ExecStart='{ argv[]='+' '.join(command)+' ; ignore_errors=no ; }',BindsTo=parent['unit'],After=parent['unit'])
        system.props[name]=props;system.groups[props['ControlGroup']]=[101]
        raise RuntimeError('manager rejected start after creating unit')
    with mock.patch.object(system,'start',side_effect=start,create=True),mock.patch.object(M,'git',return_value='new'),pytest.raises(RuntimeError,match='manager rejected'):
        M.start_control(system,c,tmp_path,'test',argv,60,parent=parent)
    failure=M.read(tmp_path/'startup_failure.json')
    assert 'manager rejected' in failure['original_error'] and failure['cleanup']['drained'] and failure['cleanup_errors']==[]
    assert not (tmp_path/'attestation.json').exists()


def test_acknowledgement_cannot_replace_prestart_identity(tmp_path):
    M.immutable(tmp_path/'intent.json',{'unit':'one','argv':['one']})
    M.immutable(tmp_path/'attestation.json',{'unit':'two','argv':['two'],'attested':{}})
    with pytest.raises(RuntimeError,match='prestart intent'):M.await_capsule(tmp_path,timeout=0)


@pytest.mark.parametrize('strict_seal',[True,False])
def test_fake_wave_drains_before_phase_advance_and_final_assessment(tmp_path,strict_seal):
    root=tmp_path/'runtime';recovery='a'*32;folder=root/'recoveries'/recovery;wave=root/'wave_2'
    coordinator,cp=capsule('coordinator');controller,wp=capsule('wave');system=FakeSystem([(coordinator,cp),(controller,wp)])
    release={'source':{'head':'new'}};write(folder/'release.json',release)
    write(root/'admission.json',{'source':{'head':M.SCIENCE_HEAD}})
    write(wave/'lease.json',{'wave':'2','lease_id':'lease','seconds':7200,'expires_epoch':100000000000.,'recovery':{'recovery_id':recovery}})
    c={'cleanup_seconds':1800};oldc={'cpus':list(range(15,30)),'cooperative_grace_seconds':0,'poll_seconds':0}
    state={'started':False,'checked':False,'drained':False,'finalized':False,'advanced_after_drain':False}
    task={'name':'d','estimated_cpu_seconds':10,'estimated_wall_seconds':20}
    def queue():
        done=state['checked'] and strict_seal
        return dict(complete=['d'] if done else [],ready=[] if done else [task],pending=[] if done else ['d'],terminal=done,
            phase='READY_FOR_ASSESSMENT' if done else 'DETERMINISTIC_POOL',unfunded_pending=[])
    def complete(name):state['checked']=True;return strict_seal
    def advance():
        if state['started']:
            assert state['drained'];state['advanced_after_drain']=True
    science=SimpleNamespace(queue_state=queue,advance=advance,task_complete=complete)
    def start(*args):
        state['started']=True;saved,props=capsule('worker',300)
        saved.update(task='d',token='token',cpu=18,policy_receipt=str(wave/'workers/token/policy.json'))
        props.update(ActiveState='inactive',MainPID='0',ControlGroup='')
        system.props[saved['unit']]=props;write(wave/'workers/token/ownership.json',saved);return saved
    def drain(*args,**kwargs):state['drained']=True;return {'drained':True}
    def final(*args):assert state['drained'];state['finalized']=True
    r=M.load_legacy()
    with mock.patch.object(M,'CANONICAL',root),mock.patch.object(M,'verify_release',return_value=(c,oldc)),mock.patch.object(M,'await_capsule',side_effect=[coordinator,controller]),mock.patch.object(r,'System',return_value=system),mock.patch.object(r,'load_science',return_value=science),mock.patch.object(M,'baseline_guard',return_value={'handoff':{}}),mock.patch.object(M,'all_workers',return_value=[]),mock.patch.object(M,'recovery_capsules',return_value=[]),mock.patch.object(M,'resource_projection',return_value={'fits':True,'packing':{'allocation':[{'task':'d','slot':0}]}}),mock.patch.object(M,'passive_placement',return_value={'ranked':[18,19]}),mock.patch.object(r,'projection_fits',return_value=True),mock.patch.object(r,'start_worker',side_effect=start),mock.patch.object(r,'starvation_predicate',return_value=None),mock.patch.object(M,'drain_exact',side_effect=drain),mock.patch.object(M,'cooperative_drain',return_value={'cleanup_verified':True,'cleanup':[],'cleanup_errors':[]}),mock.patch.object(M,'finalize_owned',side_effect=final):
        result=M.run_wave(recovery,'2',controller['unit'])
    terminal=M.read(wave/'terminal.json')
    assert result==(0 if strict_seal else 2)
    assert terminal['status']==('R150_WAVE_COMPLETE' if strict_seal else 'R150_GUARD_STOPPED')
    assert state['finalized'] is strict_seal
    if strict_seal:assert state['advanced_after_drain'] and terminal['strict_new_components']==1
    else:assert terminal['strict_new_components']==0 and 'without strict seal' in terminal['original_stop_reason']


def test_policy_failure_after_observed_lifetime_never_stops_replacement(tmp_path):
    parent,pp=capsule('parent');system=FakeSystem([(parent,pp)]);c={'cpus':list(range(15,30))}
    unit='pricefm-r150-test-new.service';argv=['/python','-B',str(ENTRY),'test-hold','--controller-unit',unit]
    def start(name,description,command,**kwargs):
        props=dict(pp,Id=name,Description=description,InvocationID='first-invocation',ControlGroup='/user.slice/test/'+name,
            ExecStart='{ argv[]='+' '.join(command)+' ; ignore_errors=no ; }',BindsTo=parent['unit'],After=parent['unit'])
        system.props[name]=props;system.groups[props['ControlGroup']]=[101]
    def failed_policy(*args,**kwargs):
        # Another actor replaced the unit after our first actual identity read.
        system.props[unit]['InvocationID']='replacement-invocation';raise RuntimeError('actual policy failed')
    with mock.patch.object(system,'start',side_effect=start,create=True),mock.patch.object(M,'git',return_value='new'),mock.patch.object(M,'verify_control',side_effect=failed_policy),pytest.raises(RuntimeError,match='actual policy failed'):
        M.start_control(system,c,tmp_path,'test',argv,60,parent=parent)
    failure=M.read(tmp_path/'startup_failure.json')
    assert failure['strongest_ownership']['attested']['InvocationID']=='first-invocation'
    assert failure['cleanup_errors'] and not system.stops
    assert M.control_capsule(tmp_path)['attested']['InvocationID']=='first-invocation'


def test_attesting_legacy_api_preserves_first_invocation_before_return(tmp_path):
    saved,props=capsule('worker');saved.pop('attested');write(tmp_path/'workers/token/ownership.json',saved)
    system=FakeSystem([(saved,props)]);wrapped=M.AttestingSystem(system,tmp_path)
    wrapped.unit(saved['unit'])
    recorded=M.read(tmp_path/'workers/token/ownership.json')
    assert recorded['attested']['InvocationID']==props['InvocationID']
    system.props[saved['unit']]['InvocationID']='replaced'
    with pytest.raises(RuntimeError,match='identity mismatch'):wrapped.unit(saved['unit'])
    with pytest.raises(RuntimeError,match='identity mismatch'):M.drain_exact(system,recorded,timeout=0)
    assert not system.stops


def test_unattested_cgroup_substitution_refuses_all_signals():
    saved,props=capsule();saved.pop('attested');props['ControlGroup']='/user.slice/substituted'
    system=FakeSystem([(saved,props)])
    with pytest.raises(RuntimeError,match='expected cgroup mismatch'):M.drain_exact(system,saved,timeout=0)
    assert not system.stops


def test_componentwise_s_envelope_dominates_different_task_shapes(tmp_path):
    prices={'d':{'estimated_cpu_seconds':1,'estimated_wall_seconds':2}}
    vectors={'a':[(100,200),(1,2)],'b':[(1,2),(100,200)],'c':[(51,102),(51,102)]}
    for package,values in vectors.items():
        for i,(cpu,wall) in enumerate(values):prices[package+str(i)]={'estimated_cpu_seconds':cpu,'estimated_wall_seconds':wall}
    prep={'packages':[{'package_id':n} for n in ['C0','a','b','c']],'control':'C0','pricing':{'task_estimates':prices}}
    science=SimpleNamespace(read_preparation=lambda:prep,names_for=lambda ids,*_:[] if ids==['C0'] else [ids[0]+str(i) for i in range(2)],task_complete=lambda _:False)
    with mock.patch.object(M,'CANONICAL',tmp_path),mock.patch.object(M,'recovery_attempts',return_value=[]):
        p=M.resource_projection({'replacement_reserve_CPU_seconds':5,'historical_charge_CPU_seconds':0,'original_adjusted_CPU_seconds':10000,'idle_share':.5},science,{'phase':'DETERMINISTIC_POOL','pending':['d']},{},now=0)
    # Top summed packages alone would miss the split-wise worst envelope. Here
    # each selected nominee reserves [100,100], dominating every possible shape.
    assert p['remaining_projected_CPU_seconds']==406
    assert [v['estimated_cpu_seconds'] for v in p['initial_S_componentwise_envelope']]==[100,100,100,100]


def test_next_child_wave_must_fit_original_parent_deadline():
    coordinator={'epoch':100.,'runtime_seconds':14700.}
    assert M.parent_admission_deadline(coordinator,14700.,7200.,now=7595.)==14800.
    with pytest.raises(RuntimeError,match='entire next admission'):
        M.parent_admission_deadline(coordinator,14700.,7200.,now=7595.01)
    # An unchanged capsule cannot grant more time because its caller starts a new
    # child or supplies a larger service-duration property.
    with pytest.raises(RuntimeError,match='entire next admission'):
        M.parent_admission_deadline(coordinator,999999.,7200.,now=8000.)


def test_parent_runtime_readback_can_tighten_but_never_extend_deadline():
    coordinator={'epoch':100.,'runtime_seconds':14700.}
    assert M.parent_admission_deadline(coordinator,14000.,7200.,now=100.)==14100.
    with pytest.raises(RuntimeError,match='entire next admission'):
        M.parent_admission_deadline(coordinator,14000.,7200.,now=6895.01)
    with pytest.raises(RuntimeError,match='invalid'):
        M.parent_admission_deadline(coordinator,float('inf'),7200.,now=100.)


def retirement_fixture():
    r=M.load_legacy();proof=M.read(M.ROOT/'application/config/pricefm_stage_r151_retirement_contract_20261023.json')
    saved={'properties':proof['original_saved_properties'],'process':proof['original_saved_process']}
    system=FakeSystem([]);system.props[proof['retired_unit']]=dict(proof['observed_retired_properties'])
    system.groups[proof['expected_cgroup']]=[]
    return r,proof,saved,system


def test_exact_retired_r141_absence_is_guarded_without_replacement():
    r,proof,saved,system=retirement_fixture()
    with mock.patch.object(r,'process',return_value=None):
        assert M.verify_retired_baseline(system,proof,saved)['retired_absent']
    assert not system.stops


@pytest.mark.parametrize('change',[{'LoadState':'loaded'},{'ActiveState':'active','MainPID':'999'},
    {'InvocationID':'new-lifetime'},{'ControlGroup':'/user.slice/replacement'}])
def test_retired_baseline_reappearance_is_not_an_accepted_new_owner(change):
    r,proof,saved,system=retirement_fixture();system.props[proof['retired_unit']].update(change)
    with mock.patch.object(r,'process',return_value=None),pytest.raises(RuntimeError,match='reappeared'):
        M.verify_retired_baseline(system,proof,saved)
    assert not system.stops


@pytest.mark.parametrize('pid_kind',['supervisor','LT_controller','descendant'])
def test_retired_process_or_cgroup_membership_defers(pid_kind):
    r,proof,saved,system=retirement_fixture()
    if pid_kind=='descendant':system.groups[proof['expected_cgroup']]=[999]
    target=saved['process']['pid'] if pid_kind=='supervisor' else proof['old_LT_controller_pid']
    with mock.patch.object(r,'process',side_effect=lambda pid:{'pid':pid} if pid_kind!='descendant' and pid==target else None),pytest.raises(RuntimeError,match='not fully drained'):
        M.verify_retired_baseline(system,proof,saved)
    assert not system.stops


def test_retirement_contract_cannot_substitute_a_different_saved_baseline():
    r,proof,saved,system=retirement_fixture();saved=copy.deepcopy(saved);saved['process']['start_ticks']+=1
    with mock.patch.object(r,'process',return_value=None),pytest.raises(RuntimeError,match='changed'):
        M.verify_retired_baseline(system,proof,saved)


def test_prior_retirement_capsule_must_be_drained():
    saved,props=capsule();system=FakeSystem([(saved,props)])
    with pytest.raises(RuntimeError,match='prior failed'):M.assert_capsules_drained(system,[saved])
    system.props[saved['unit']].update(ActiveState='inactive',MainPID='0',ControlGroup='')
    system.groups[saved['expected_cgroup']]=[]
    assert M.assert_capsules_drained(system,[saved])


@pytest.mark.parametrize('directory',['muscat_resources','benchmark','tasks_done','checkpoints','cpu_accounting','decisions'])
def test_original_prepared_region_may_not_acquire_new_budget_or_outputs(tmp_path,directory):
    prep=tmp_path/'prep';out=tmp_path/'out';write(prep/'prepared.json',{})
    (out/directory).mkdir(parents=True)
    with mock.patch.object(M,'PARENT_REGION_PREP',prep),mock.patch.object(M,'PARENT_REGION_OUT',out),pytest.raises(RuntimeError,match='original regional namespace'):
        M.assert_parent_region_unused()


def test_preouter_guard_none_lifecycle_checks_resource_floors(tmp_path):
    stack,r,c,system,admission,_=guard_fixture(tmp_path)
    with stack:
        result=M.baseline_guard(c,system,admission,None,None,None,[],{})
    assert result['active_workers']==0 and result['owned_pids']==[os.getpid()]


def test_preouter_guard_does_not_accept_a_numerical_lease(tmp_path):
    stack,r,c,system,admission,_=guard_fixture(tmp_path)
    with stack,mock.patch.object(M,'boot',return_value='boot'),mock.patch.object(M.time,'time',return_value=1),pytest.raises(RuntimeError,match='preouter'):
        M.baseline_guard(c,system,admission,None,None,{'boot_id':'boot','expires_epoch':100},[],{})


def test_fresh_ee_coordinator_is_bounded_by_carried_outer_deadline():
    outer={'epoch':100.,'runtime_seconds':10000.}
    assert M.bounded_child_runtime(14700.,outer,10000.,now=100.)==9995.
    assert M.bounded_child_runtime(14700.,outer,999999.,now=100.)==9995.
    assert M.bounded_child_runtime(14700.,outer,9000.,now=100.)==8995.
    with pytest.raises(RuntimeError,match='outer finite'):
        M.bounded_child_runtime(14700.,outer,10000.,now=10095.)


def test_standalone_recovery_cannot_reset_original_global_deadline():
    assert M.bounded_recovery_runtime(14700.,10100.,now=100.)==9995.
    assert M.bounded_recovery_runtime(14700.,20100.,now=100.)==14700.
    with pytest.raises(RuntimeError,match='global continuation deadline'):
        M.bounded_recovery_runtime(14700.,10100.,now=10095.)


@pytest.mark.parametrize('with_lease',[False,True])
def test_original_global_deadline_stops_before_and_after_admission(tmp_path,with_lease):
    stack,r,c,system,admission,coordinator=guard_fixture(tmp_path)
    release={'original_global_expires_epoch':100.}
    lease={'boot_id':'boot','expires_epoch':10000.} if with_lease else None
    with stack,mock.patch.object(M.time,'time',return_value=100.),pytest.raises(RuntimeError,match='global continuation deadline expired'):
        M.baseline_guard(c,system,admission,coordinator,None,lease,[],release)
