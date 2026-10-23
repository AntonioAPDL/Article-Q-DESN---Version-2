"""Bounded cached screening contracts. Toy arithmetic only; no model fitting."""
import copy
import datetime as dt
import importlib.util
from pathlib import Path
import subprocess
import sys
import types

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT/"application/scripts/pricefm/497_run_pricefm_stage_r150_cached_continuation.py"


@pytest.fixture
def m(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r150_test_science", ENTRY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "OUT", tmp_path/"campaign")
    monkeypatch.setattr(module, "PREP", tmp_path/"prep")
    return module


def toy_task(m):
    start = dt.datetime(2023, 1, 1, tzinfo=dt.timezone.utc)
    positions = [10, 11]
    return dict(name="toy", daily_origin_positions=positions, clock_offsets_steps=[0, 24, 48, 72],
        origin_timestamps={str(o): [(start+dt.timedelta(days=p-10, minutes=15*o)).isoformat() for p in positions]
                           for o in (0, 24, 48, 72)})


def toy_arrays(m, task):
    rows = m.expected_rows(task)
    arrays = {k: np.zeros(shape, dtype="<i8" if k in m.INT_KEYS else "<f8")
              for k, shape in m.array_shapes(len(rows)).items()}
    for key in ("truth_eur", "prediction_eur"):
        arrays[key].fill(10.)
    for i, (p, offset, stamp) in enumerate(rows):
        arrays["origin_positions"][i] = p
        arrays["clock_offsets"][i] = offset
        arrays["stable_rng_origin_keys"][i] = p*96+offset
        arrays["origin_timestamps_ns"][i] = round(dt.datetime.fromisoformat(stamp).timestamp()*1e9)
    return arrays


def test_import_has_no_numerical_side_effects():
    code = "import importlib.util,sys;s=importlib.util.spec_from_file_location('r150',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);assert 'numpy' not in sys.modules and 'scipy' not in sys.modules"
    subprocess.run([sys.executable, "-B", "-c", code, str(ENTRY)], check=True)


@pytest.mark.parametrize("field", ["al_authorized", "new_fits_authorized", "new_geometry_authorized",
    "official_evaluation_authorized", "promotion_authorized", "automatic_future_stage_authorized"])
def test_scope_cannot_be_silently_expanded(m, field):
    config = m.read(m.CONFIG)
    config[field] = True
    with pytest.raises(ValueError):
        m.validate_config(config)


@pytest.mark.parametrize("field,value", [("max_new_D_components", 75), ("max_new_S_B1", 30),
    ("max_new_S_B2", 90), ("paths", 500), ("chunk_origins", 12), ("seed0_trigger_fraction", 1.),
    ("extra_seeds", [3, 4]), ("audit_key", "retrospective-key")])
def test_scientific_budget_and_rng_policy_are_frozen(m, field, value):
    config = m.read(m.CONFIG)
    config[field] = value
    with pytest.raises(ValueError):
        m.validate_config(config)


def test_exact_pool_has_26_packages_25_geometries_and_both_C0_scales(m):
    config = m.validate_config(m.read(m.CONFIG))
    packages = config["packages"]
    assert len(packages) == 26
    assert len({p["candidate_id"] for p in packages}) == 25
    assert sorted(p["tau0"] for p in packages if p["candidate_id"] == "r134_0cab1abbe8ace168") == [.00024929739307713865, .0024929739307713865]


def test_loss_blind_sentinel_and_numerical_ties(m):
    c = m.read(m.CONFIG)
    packages = c["packages"]
    losses = {p["package_id"]: 20. for p in packages}
    losses.update(C0=15., C0_alt=10.+5e-11, C5=10.)
    result = m.choose_nominees(packages, losses, "C0", "C5", c["audit_key"])
    # Within the frozen tolerance, stable package ID C0_alt beats C5.
    assert result["A"] == "C0_alt"
    original_order = result["audit_order"]
    losses = {p: (v+1234 if p not in ("C0_alt", "C5") else v) for p, v in losses.items()}
    changed = m.choose_nominees(list(reversed(packages)), losses, "C0", "C5", c["audit_key"])
    assert changed["audit_order"] == original_order
    assert changed["B"] == result["B"]
    by_id = {p["package_id"]: p for p in packages}
    assert by_id[result["B"]]["candidate_id"] not in {by_id["C0"]["candidate_id"], by_id["C5"]["candidate_id"]}


def test_matching_three_seed_gate_is_not_win_every_seed_or_split(m):
    result = m.confirm_gains([20., 20., 20.], [19.6, 19.5, 19.7])
    assert result["eligible_for_AL_proposal"]
    assert result["practical_margin"] == .2
    unstable = m.confirm_gains([20., 20., 20.], [19., 19., 20.5])
    assert unstable["practical_gain"]
    assert unstable["algorithmic_stability_unresolved"]
    assert not unstable["eligible_for_AL_proposal"]
    assert not unstable["inferential_confidence_interval"]


@pytest.mark.parametrize("control", [0, -1., float("nan"), True])
def test_practical_margin_rejects_invalid_control(m, control):
    with pytest.raises(ValueError):
        m.practical_margin(control)


@pytest.mark.parametrize("b1,b2,budget,expected", [(100., 151., 200., ("B1", "ADMITTED_B1")),
    (100., 150., 200., ("B2", "ADMITTED_B2")), (100., 140., 120., ("B1", "ADMITTED_B1")),
    (100., 80., 90., ("B2", "ADMITTED_B2")), (100., 140., 70., ("B1", "DEFERRED_NEITHER_FULL_BRANCH_FITS"))])
def test_relative_branch_policy_and_finite_full_pool_budget(m, b1, b2, budget, expected):
    assert m.select_branch(b1, b2, budget) == expected


def test_analytic_pinball_EUR_transform_and_npz_header_roundtrip(m, tmp_path):
    task = toy_task(m)
    arrays = toy_arrays(m, task)
    # Constant standardized prediction +2 means EUR error -4. Mean pinball is2.
    arrays["prediction_standardized"].fill(2.)
    arrays["prediction_eur"].fill(14.)
    arrays["origin_AQL"].fill(2.)
    path = tmp_path/"toy.npz"
    np.savez_compressed(path, **arrays)
    loaded = m.read_npz(path)
    m.validate_arrays(task, loaded, dict(price_scale=2., price_mean=10.))
    measured = m.metrics(loaded)
    assert measured == dict(AQL=2., median_MAE=4., coverage_80=0., width_80=0.)
    m.validate_arrays(task, m.read_npz(path, headers_only=True), dict(price_scale=2., price_mean=10.), semantic=False)


@pytest.mark.parametrize("mutation", ["wrong_clock", "wrong_origin", "wrong_key", "wrong_timestamp", "missing", "float32",
    "nonfinite", "EUR", "loss", "crossing"])
def test_retained_arrays_fail_closed(m, tmp_path, mutation):
    task = toy_task(m)
    arrays = toy_arrays(m, task)
    if mutation == "wrong_clock": arrays["clock_offsets"][0] = 24
    elif mutation == "wrong_origin": arrays["origin_positions"][0] += 1
    elif mutation == "wrong_key": arrays["stable_rng_origin_keys"][0] += 1
    elif mutation == "wrong_timestamp": arrays["origin_timestamps_ns"][0] += 1000
    elif mutation == "missing": del arrays["truth_eur"]
    elif mutation == "float32": arrays["prediction_eur"] = arrays["prediction_eur"].astype("<f4")
    elif mutation == "nonfinite": arrays["truth_eur"][0, 0] = np.nan
    elif mutation == "EUR": arrays["truth_eur"][0, 0] += 1.
    elif mutation == "loss": arrays["origin_AQL"][0] = .1
    else:
        arrays["prediction_standardized"][0, 0, 0] = 1.
        arrays["prediction_eur"][0, 0, 0] = 12.
    path = tmp_path/"invalid.npz"
    np.savez_compressed(path, **arrays)
    with pytest.raises(ValueError):
        m.validate_arrays(task, m.read_npz(path), dict(price_scale=2., price_mean=10.))


def test_guard_precedes_any_numerical_import_or_worker_side_effect(m, monkeypatch):
    def refuse(*args):
        raise RuntimeError("policy gate")
    monkeypatch.setattr(m, "guarded_runtime", refuse)
    monkeypatch.setattr(m, "read_preparation", lambda: pytest.fail("must guard first"))
    with pytest.raises(RuntimeError, match="policy gate"):
        m.worker("foreign", 0, "missing.json")


def test_D_and_S_execute_only_their_own_kernel(m, monkeypatch):
    anchors = np.array(["2023-01-01T00:00:00+00:00", "2023-01-02T00:00:00+00:00"])
    shifted = types.SimpleNamespace(anchors=anchors[:1], response=np.zeros((1, 96)))
    raw = types.SimpleNamespace(anchors=anchors, response=np.zeros((2, 96)))
    contract = types.ModuleType("pricefm_r127_contract")
    contract.shifted_windows = lambda *args: shifted
    contract.window_identity = lambda *args: None
    monkeypatch.setitem(sys.modules, "pricefm_r127_contract", contract)
    calls = []
    def D(*args):
        calls.append("D")
        return np.zeros((1, 96, 7))
    def S(*args, **kwargs):
        calls.append("S")
        return np.zeros((1, 96, 7)), {}
    monkeypatch.setattr(m, "kernel", lambda: types.SimpleNamespace(deterministic_predictions=D))
    runtime = types.SimpleNamespace(BASE=types.SimpleNamespace(deterministic_seed=lambda *args: 123))
    context = dict(runtime=runtime, core=types.SimpleNamespace(normal_predictions=S), raw=raw, scaled=raw,
        fit={}, scaler=dict(price_scale=1., price_mean=0.))
    descriptor = dict(name="tiny", origin_positions=[0], clock_offset_steps=0,
        origin_timestamps=[str(anchors[0])], stable_rng_origin_keys=[0])
    task = dict(validation_origin_positions=[0, 1], mode="D", spec={}, forecast_seed=1, split=1)
    m.predict(context, task, descriptor, lambda _: None)
    assert calls == ["D"]
    task["mode"] = "S"
    m.predict(context, task, descriptor, lambda _: None)
    assert calls == ["D", "S"]


def test_chunk_coverage_is_complete_ordered_and_no_last_day(m):
    task = toy_task(m)
    task["daily_origin_positions"] = list(range(10, 29))
    for offset in task["clock_offsets_steps"]:
        first = dt.datetime.fromisoformat(task["origin_timestamps"][str(offset)][0])
        task["origin_timestamps"][str(offset)] = [(first+dt.timedelta(days=i)).isoformat() for i in range(19)]
    descriptors = m.chunks(task)
    assert len(descriptors) == 12
    assert all(len(d["origin_positions"]) <= 8 for d in descriptors)
    assert [r for d in descriptors for r in zip(d["origin_positions"], [d["clock_offset_steps"]]*len(d["origin_positions"]))] == [(p,o) for o in (0,24,48,72) for p in range(10,29)]


def test_empty_ready_transition_is_not_scientific_completion(m, monkeypatch):
    prep = dict(packages=[dict(package_id="C0"), dict(package_id="A")], control="C0")
    monkeypatch.setattr(m, "read_preparation", lambda: prep)
    monkeypatch.setattr(m, "task_complete", lambda name: True)
    monkeypatch.setattr(m, "read", lambda path: dict(branch="B1") if str(path).endswith("branch.json") else {})
    phase, names, terminal = m.manifest_state()
    assert phase == "NOMINATION_REQUIRED"
    assert not terminal


def test_B1_two_nominee_cap_and_B2_single_finalist_cap(m, monkeypatch):
    packages = [p["package_id"] for p in m.read(m.CONFIG)["packages"]]
    b1_seed0_new = m.component_names([packages[1], packages[2]], "S", [0])
    b1_extras = m.component_names(["C0", packages[1], packages[2]], "S", [1,2])
    assert len(b1_seed0_new+b1_extras) == 24
    b2_seed0_new = len(m.component_names(packages, "S", [0]))-6
    b2_extras = len(m.component_names(["C0", packages[1]], "S", [1,2]))
    assert b2_seed0_new+b2_extras == 84


def test_decision_tampering_is_detected_before_next_dispatch(m, tmp_path, monkeypatch):
    m.write(m.PREP/"preparation.json", {})
    monkeypatch.setattr(m, "read_preparation", lambda: dict(source=dict(head="frozen")))
    m.write_decision("nominees", dict(nominees=["A", "B"]))
    assert m.read_decision("nominees")["nominees"] == ["A", "B"]
    m.write(m.OUT/"decisions/nominees.json", dict(nominees=["other"]))
    with pytest.raises(RuntimeError, match="decision seal"):
        m.read_decision("nominees")


def toy_component(m, tmp_path):
    task = toy_task(m)
    scaler, bank, parent = (tmp_path/n for n in ("scaler.json", "bank.npz", "parent.bin"))
    m.write(scaler, dict(price_mean=10., price_scale=2.))
    bank.write_bytes(b"unchanged-training-bank")
    parent.write_bytes(b"original-posterior-moments")
    task.update(mode="D", forecast_seed=1, paths=100, parent_seal_sha256="original-parent-seal",
        scaler_path=str(scaler), scaler_sha256=m.digest(scaler),
        bank=dict(path=str(bank), sha256=m.digest(bank)), parent_input_sha256={str(parent): m.digest(parent)},
        tau0=.001, candidate_id="geometry", split=1, seed_index=0, reuse=None)
    task["scientific_identity_sha256"] = m.fingerprint(m.task_identity(task))
    return task


@pytest.mark.parametrize("field,value", [("tau0", .002), ("mode", "S"), ("forecast_seed", 2),
    ("parent_seal_sha256", "different"), ("scaler_sha256", "other"),
    ("bank", dict(path="different", sha256="other"))])
def test_scientific_identity_rejects_wrong_prior_mode_seed_parent_scaler_bank(m, tmp_path, monkeypatch, field, value):
    task = toy_component(m, tmp_path)
    task[field] = value
    with pytest.raises(RuntimeError, match="identity"):
        m.task_by_name("toy", dict(tasks=[task]))


def test_completed_packet_cache_invalidates_changed_training_bank(m, tmp_path, monkeypatch):
    task = toy_component(m, tmp_path)
    prep = dict(source=dict(head="source", branch="branch"), tasks=[task])
    monkeypatch.setattr(m, "read_preparation", lambda: prep)
    m.write(m.OUT/"tasks/toy.json", task)
    folder = m.OUT/"tasks_done/toy"
    folder.mkdir(parents=True)
    arrays = toy_arrays(m, task)
    np.savez_compressed(folder/"predictions.npz", **arrays)
    m.write(folder/"result.json", dict(scientific_identity_sha256=task["scientific_identity_sha256"],
        units="EUR/MWh", new_model_fits=0, posterior_updated=False, test_opened=False,
        mode="D", origin_clock_windows=8, numerical_threadpools=[dict(num_threads=1)], metrics=dict(AQL=0.)))
    m.write(folder/"completed_evidence.json", dict(certified=True, context=m.context_identity(task, prep),
        artifacts={p:m.digest(folder/p) for p in ("result.json", "predictions.npz")}))
    assert m.task_complete("toy")
    assert m.task_complete("toy")
    Path(task["bank"]["path"]).write_bytes(b"changed-training-bank")
    with pytest.raises(RuntimeError, match="pinned artifact changed"):
        m.task_complete("toy")


def prospective_toy(m):
    c=m.read(m.CONFIG)
    by_id={p['package_id']:p for p in c['packages']}
    tasks=[]
    for package in c['packages']:
        for split,n in ((1,2),(2,3),(3,4)):
            for mode,seeds in (('D',[0]),('S',[0,1,2])):
                for seed in seeds:
                    tasks.append(dict(name=m.name_for(package['package_id'],split,mode,seed),
                        package_id=package['package_id'],p=package['p'],spec=package['spec'],
                        daily_origin_positions=list(range(n)),clock_offsets_steps=[0,24,48,72],
                        mode=mode,seed_index=seed,
                        reuse=bool(package['package_id'] in ('C0','C5') and seed==0)))
    rows=[]
    for mode in ('D','S'):
        for name in c['benchmark_'+mode+'_packages']:
            package=by_id[name]
            cpu=(8. if mode=='D' else (800. if package['p']==769 else 80.))
            rows.append(dict(mode=mode,package_id=name,p=package['p'],spec=package['spec'],
                origin_count=8,arithmetic_cpu_seconds=cpu,serialization_cpu_seconds=0.,
                cold_context_cpu_seconds=40. if mode=='D' else 80.))
    pricing=m.prospective_costs(c['packages'],tasks,rows,'C0','C5',c['audit_key'],20.,.5)
    return c,tasks,rows,pricing


def test_cold_setup_is_charged_once_per_component_not_per_chunk(m):
    _,_,_,pricing=prospective_toy(m)
    one=pricing['task_estimates'][m.name_for('C0',1,'S',1)]
    two=pricing['task_estimates'][m.name_for('C0',3,'S',1)]
    assert one['setup_cpu_seconds_once']==150. # (startup20+cold80)*1.5
    assert one['cpu_seconds_per_window']==15. # S80 CPU/8origins*1.5
    assert one['estimated_cpu_seconds']==150.+8*15.
    assert two['estimated_cpu_seconds']==150.+16*15.
    assert two['estimated_cpu_seconds']-one['estimated_cpu_seconds']==8*15.
    assert one['estimated_wall_seconds']==2*one['estimated_cpu_seconds']
    assert one['estimated_max_chunk_cpu_seconds']==120.


def test_measured_dimension_input_bucket_avoids_pricing_C0_as_p769(m):
    c,_,_,pricing=prospective_toy(m)
    control=pricing['task_estimates'][m.name_for('C0',1,'S',1)]
    assert control['cost_bucket']=='covered_dimension_and_input_envelope'
    assert control['benchmark_packages']==['C0']
    assert control['cpu_seconds_per_window']==15.
    # The p513 target case lacks a sufficiently large target S measurement.
    package=next(p for p in c['packages'] if p['p']==513 and p['spec']['feature_policy']=='target_only')
    fallback=pricing['task_estimates'][m.name_for(package['package_id'],1,'S',0)]
    assert fallback['cost_bucket']=='global_policy_maximum_fallback'
    assert fallback['unmeasured_geometry_timing_uncertainty']
    assert fallback['cpu_seconds_per_window']==150.


def test_branch_budget_prices_actual_components_and_prospective_fixed_audit_without_losses(m):
    c,tasks,_,pricing=prospective_toy(m)
    estimates=pricing['task_estimates']
    D=sum(estimates[t['name']]['estimated_cpu_seconds'] for t in tasks if t['mode']=='D')
    S0=sum(estimates[t['name']]['estimated_cpu_seconds'] for t in tasks if t['mode']=='S' and t['seed_index']==0)
    assert pricing['B1_D_cpu_seconds']==D
    assert pricing['B2_original_seed_S_cpu_seconds']==S0
    assert pricing['estimated_B1_max_cpu_seconds']==D+max(p['B1_S_cpu_seconds'] for p in pricing['prospective_possible_nominations'])
    assert pricing['estimated_B2_max_cpu_seconds']==S0+max(p['B2_extra_S_cpu_seconds'] for p in pricing['prospective_possible_nominations'])
    assert len(pricing['prospective_possible_nominations'])==25
    for possible in pricing['prospective_possible_nominations']:
        losses={p['package_id']:2. for p in c['packages']}
        losses[possible['A']]=0.
        actual=m.choose_nominees(c['packages'],losses,'C0','C5',c['audit_key'])
        assert actual['B']==possible['B']
    assert pricing['no_losses_or_predictions_used']


def test_benchmark_serialization_uses_actual_units_schema_without_computing_candidate_AQL(m,monkeypatch):
    task=toy_task(m)
    descriptor=m.chunks(task)[0]
    prediction=np.zeros((2,96,7))
    truth=np.zeros((2,96))
    # With compute_loss=False the loss module must never be imported or used.
    fake=types.ModuleType('pricefm_r126_contract')
    fake.loss=lambda *args:pytest.fail('benchmark must not compute candidate loss')
    monkeypatch.setitem(sys.modules,'pricefm_r126_contract',fake)
    arrays=m.retained_arrays(dict(scaler=dict(price_scale=2.,price_mean=10.)),task,descriptor,prediction,truth,compute_loss=False)
    assert set(arrays)==set(m.array_shapes(2))
    assert np.array_equal(arrays['truth_eur'],truth+10.)
    assert np.array_equal(arrays['prediction_eur'],prediction+10.)
    assert np.array_equal(arrays['origin_AQL'],np.zeros(2))
