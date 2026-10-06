from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT / "application/scripts/pricefm"))
import pricefm_r123_recovery as REC
import pricefm_r123_dependency_queue as Q


def runner():
    spec = importlib.util.spec_from_file_location("dependency_resume_test",
        ROOT / "application/scripts/pricefm/444_resume_pricefm_stage_r123_dependencies.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def test_lower_and_upper_branches_run_together_without_repeating_completed_fits():
    parents = dict(median=None,lower="median",upper="median",lowtail="lower",uptail="upper")
    barrier = threading.Barrier(2); calls=[]; guard=threading.Lock()
    def execute(key,cpu,record):
        with guard: calls.append((key,cpu,record))
        if key in ("lower","upper"): barrier.wait(timeout=3)
        return True
    assert Q.run_dependencies(parents,{"median"},{},[1,2],execute) == set(parents)
    assert {key for key,_,_ in calls} == set(parents)-{"median"}
    assert len(calls) == 4


def test_adopted_workers_keep_their_cores_and_ready_siblings_start_immediately():
    parents = dict(m=None,a="m",b="m",c="b")
    release=threading.Event(); started=threading.Event(); calls=[]
    def execute(key,cpu,record):
        calls.append((key,cpu,record))
        if key == "a":
            assert record == {"cpu":4,"pid":42}; assert release.wait(3)
        if key == "b": started.set(); release.set()
        return True
    assert Q.run_dependencies(parents,{"m"},{"a":{"cpu":4,"pid":42}},[1,4],execute) == set(parents)
    assert started.is_set()
    assert len(calls)==3 and len({key for key,_,_ in calls})==3


def test_failed_parent_blocks_only_its_descendants():
    calls=[]
    with pytest.raises(RuntimeError,match="rejected"):
        Q.run_dependencies(dict(m=None,a="m",b="m",tail="a"),{"m"},{},[1,2],
            lambda key,cpu,record: calls.append(key) is None and key != "a")
    assert set(calls)=={"a","b"}


@pytest.mark.parametrize("parents",[{"a":"missing"},{"a":"b","b":"a"}])
def test_invalid_dependency_graph_is_rejected(parents):
    with pytest.raises(ValueError): Q.validate_graph(parents)


@pytest.mark.parametrize("done,adopted,cpus",[
    ({"a"},{"a":{"cpu":1}},[1]),
    (set(),{"a":{"cpu":1},"b":{"cpu":1}},[1,2]),
    (set(),{"a":{"cpu":3}},[1,2]),
    (set(),{},[1,1]),
    ({"a"},{},[1,2]),
])
def test_duplicate_invalid_core_and_missing_ancestor_inventories_are_rejected(done,adopted,cpus):
    parents={"m":None,"a":"m","b":"m"}
    with pytest.raises(ValueError): Q.run_dependencies(parents,done,adopted,cpus,lambda *a:True)


def test_completed_resume_is_a_no_op():
    def forbidden(*a): raise AssertionError("completed work was rerun")
    assert Q.run_dependencies({"m":None,"a":"m"},{"m","a"},{},[1],forbidden)=={"m","a"}


def test_resource_failure_prevents_new_launches():
    def fail(): raise RuntimeError("reserve")
    calls=[]
    with pytest.raises(RuntimeError,match="reserve"):
        Q.run_dependencies({"a":None},set(),{},[1],lambda *a:calls.append(a),before_launch=fail)
    assert calls==[]


def test_process_identity_handles_spaces_and_pid_reuse(tmp_path):
    folder=tmp_path/"12"; folder.mkdir()
    fields=["S","1"]+["0"]*17+["987"]+["0"]*5
    (folder/"stat").write_text("12 (a tricky name) "+" ".join(fields))
    (folder/"cmdline").write_bytes(b"python\0controller.py\0")
    expected=Q.process_identity(12,tmp_path)
    assert expected["start_ticks"]==987
    assert Q.same_process(expected,dict(expected,state="T"))
    assert not Q.same_process(expected,dict(expected,start_ticks=988))


def test_pidfd_signal_refuses_a_changed_identity():
    identity=Q.process_identity(os.getpid()); identity["start_ticks"]+=1
    with pytest.raises(RuntimeError,match="identity changed"): Q.signal_exact(identity,signal.SIGSTOP)


def test_controller_only_signals_preserve_an_existing_numerical_child():
    code="import subprocess,time; p=subprocess.Popen(['sleep','120']); print(p.pid,flush=True); time.sleep(120)"
    parent=subprocess.Popen([sys.executable,"-c",code],stdout=subprocess.PIPE,text=True)
    child_pid=int(parent.stdout.readline()); identity=Q.process_identity(parent.pid)
    child=Q.process_identity(child_pid)
    try:
        Q.signal_exact(identity,signal.SIGSTOP)
        for _ in range(50):
            if Q.process_identity(parent.pid)["state"]=="T": break
            time.sleep(.01)
        assert Q.same_process(child,Q.process_identity(child_pid))
        assert Q.process_identity(child_pid)["state"] not in ("T","Z")
        Q.signal_exact(identity,signal.SIGTERM); Q.signal_exact(identity,signal.SIGCONT)
        parent.wait(timeout=3)
        assert Q.same_process(child,Q.process_identity(child_pid))
        assert Q.process_identity(child_pid)["state"] not in ("T","Z")
    finally:
        if parent.poll() is None: parent.kill(); parent.wait()
        if Q.same_process(child,Q.process_identity(child_pid)): Q.signal_exact(child,signal.SIGTERM)


def output_fixture(tmp_path,monkeypatch):
    m=runner(); output=tmp_path/"atom"; output.mkdir()
    contract=dict(atom_id="x",tag="scientific",stage="R122_internal_selection",readout="pure_all_layers",
        family="al",fold=1,split=1,tau=.9,tau0=.001,posterior_target_sha256="fixed",output_dir=str(output))
    terminal=dict(contract,status="completed_r121_quantile_atom",p=2,initialization_only=True,
        prior_center_from_initializer=False,initializer_changes_prior=False,test_opened=False,
        registry_mutated=False,article_mutated=False,joint_model_fitted=False,mcmc_fitted=False,
        exal_fitted=False,package_version="1.1.1",package_repository="CRAN")
    for name in m.ATOM_FILES:
        if name.endswith(".json"): REC.write(output/name,terminal if name=="terminal.json" else {})
        else: (output/name).write_bytes(b"0"*(16 if name=="beta_mean.bin" else 32 if name=="beta_cov.bin" else 1))
    path=tmp_path/"contract.json"; REC.write(path,contract)
    monkeypatch.setattr(m,"expected_contract",lambda *a:(path,contract))
    args=SimpleNamespace(attempt=tmp_path/"attempt")
    owner=SimpleNamespace(quantile_valid=lambda path,target: True)
    record=dict(pid=99999999,start_ticks=1,argv=["R"],contract_sha256=REC.digest(path))
    return m,args,owner,output,path,contract,terminal,record


@pytest.mark.parametrize("defect",[None,"prior","target","dimension","extra","missing","package"])
def test_only_complete_matching_adopted_outputs_can_be_sealed(tmp_path,monkeypatch,defect):
    m,args,owner,output,path,contract,terminal,record=output_fixture(tmp_path,monkeypatch)
    if defect=="prior": terminal["initializer_changes_prior"]=True
    elif defect=="target": terminal["posterior_target_sha256"]="changed"
    elif defect=="dimension": (output/"beta_mean.bin").write_bytes(b"0")
    elif defect=="extra": (output/"unexpected.rds").write_bytes(b"0")
    elif defect=="missing": (output/"vb_trace.csv").unlink()
    elif defect=="package": terminal["package_version"]="1.2.0"
    REC.write(output/"terminal.json",terminal)
    before={p.name:REC.digest(p) for p in output.iterdir()}
    call=lambda:m.seal_output(args,owner,{"code_head":"frozen"},{},record)
    if defect is None:
        call(); assert REC.read(output/"successor_output_hashes.json")==before
        call()
        assert all(REC.digest(output/name)==sha for name,sha in before.items())
    else:
        with pytest.raises(RuntimeError): call()
        assert not (output/"successor_output_hashes.json").exists()


def test_changed_contract_cannot_be_resealed(tmp_path,monkeypatch):
    m,args,owner,output,path,contract,terminal,record=output_fixture(tmp_path,monkeypatch)
    REC.write(path,dict(contract,tau0=.1))
    with pytest.raises(RuntimeError,match="contract changed"):
        m.seal_output(args,owner,{"code_head":"frozen"},{},record)


def test_existing_outputs_and_active_atoms_are_not_relaunched(tmp_path,monkeypatch):
    m=runner(); output=tmp_path/"existing"; output.mkdir()
    with pytest.raises(RuntimeError,match="duplicate"):
        m.run_atom(None,None,{},None,1,tmp_path/"contract",{"output_dir":str(output)})
    monkeypatch.setattr(m,"config_active",lambda path:True)
    with pytest.raises(RuntimeError,match="duplicate"):
        m.run_atom(None,None,{},None,1,tmp_path/"contract",{"output_dir":str(tmp_path/"absent")})


def test_failed_takeover_resumes_old_controller_without_signaling_children(tmp_path,monkeypatch):
    m=runner(); expected=dict(pid=42,start_ticks=123,argv=["python","owner.py"])
    monkeypatch.setattr(m,"process_identity",lambda pid:dict(expected,state="T"))
    calls=[]; monkeypatch.setattr(m,"signal_exact",lambda identity,sig:calls.append((identity["pid"],sig)))
    owner=SimpleNamespace(verify=lambda args:(_ for _ in ()).throw(RuntimeError("changed source")))
    with pytest.raises(RuntimeError,match="changed source"):
        m.takeover(SimpleNamespace(),owner,{}, {},{"old_controller":expected})
    assert calls==[(42,signal.SIGSTOP),(42,signal.SIGCONT)]


def test_process_completion_does_not_require_refitting(tmp_path,monkeypatch):
    m=runner(); calls=[]
    record=dict(pid=42,start_ticks=1,argv=["R"])
    monkeypatch.setattr(m,"process_identity",lambda pid:dict(record,state="Z"))
    monkeypatch.setattr(m,"seal_output",lambda *a:calls.append(a))
    m.seal_adopted("args","owner","control","node",record)
    assert len(calls)==1


def test_adopted_companion_restores_the_matching_output_only(monkeypatch):
    m=runner(); calls=[]
    record=dict(pid=42,start_ticks=1,argv=["R"],companion=True)
    monkeypatch.setattr(m,"process_identity",lambda pid:None)
    monkeypatch.setattr(m,"seal_output",lambda *a:calls.append(a))
    m.seal_adopted("args","owner","control","node",record)
    assert calls[0][-1] is True


def test_saved_frozen_result_hashes_cannot_be_silently_replaced(tmp_path):
    path=tmp_path/"beta_mean.bin"; path.write_bytes(b"original")
    ledger={"evidence_sha256":{str(path):REC.digest(path)}}
    path.write_bytes(b"changed")
    with pytest.raises(RuntimeError): REC.verify_evidence(ledger)


def test_old_pool_is_not_a_reservation_and_new_idle_physical_cores_can_be_used():
    old=list(range(15)); physical={cpu:cpu%32 for cpu in range(64)}
    busy={cpu:0 for cpu in range(32)}; foreign=set(range(10))-{5,6}
    cpus=Q.choose_cpu_pool(old,{5,6},set(range(64)),physical,busy,foreign)
    assert {5,6}<=set(cpus) and len(cpus)==15
    assert not {physical[cpu] for cpu in cpus}&foreign
    assert len({physical[cpu] for cpu in cpus})==len(cpus)
    assert any(cpu>=15 for cpu in cpus)


def test_small_healthy_pool_is_sufficient_for_remaining_branches():
    physical={cpu:cpu%32 for cpu in range(64)}
    busy={cpu:100 for cpu in range(32)}
    for cpu in (4,8): busy[cpu]=0
    assert Q.choose_cpu_pool(list(range(15)),{5,6},set(range(64)),physical,busy,set())==[4,5,6,8]


def test_busy_sibling_and_foreign_reservations_are_not_selected():
    physical={cpu:cpu%32 for cpu in range(64)}; busy={cpu:0 for cpu in range(32)}
    busy[4]=100
    cpus=Q.choose_cpu_pool(list(range(15)),{5,6},set(range(64)),physical,busy,{8})
    assert not {4,36,8,40}&set(cpus)
    with pytest.raises(RuntimeError,match="conflicts"):
        Q.choose_cpu_pool(list(range(15)),{5,6},set(range(64)),physical,busy,{6})


def test_scoring_is_bounded_to_distinct_cores_even_with_nine_ladder_threads():
    active=set(); peak=[0]; guard=threading.Lock()
    def score(key,cpu):
        with guard:
            assert cpu not in active; active.add(cpu); peak[0]=max(peak[0],len(active))
        time.sleep(.02)
        with guard: active.remove(cpu)
        return key
    callback=Q.BoundedScorer(score,[4,8,22])
    with ThreadPoolExecutor(max_workers=9) as pool:
        values=list(pool.map(lambda key:callback(key,-1),range(9)))
    assert values==list(range(9)) and peak[0]==3


def test_resume_keeps_workers_launched_on_new_cores_and_allows_a_full_live_pool():
    physical={cpu:cpu%32 for cpu in range(64)}; busy={cpu:0 for cpu in range(32)}
    assert {5,22}<=set(Q.choose_cpu_pool(list(range(15)),{5,22},set(range(64)),physical,busy,set()))
    full=set(range(15,30))
    assert set(Q.choose_cpu_pool(list(range(15)),full,set(range(64)),physical,busy,set()))==full
    with pytest.raises(RuntimeError,match="share"):
        Q.choose_cpu_pool(list(range(15)),{5,37},set(range(64)),physical,busy,set())
