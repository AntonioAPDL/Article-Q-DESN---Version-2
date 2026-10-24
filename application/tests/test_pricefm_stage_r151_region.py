"""Regional lineage, complete-pool decisions, RNG and finite admission hazards."""
import copy
import datetime as dt
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import types
import zipfile

import pytest

ENTRY = Path(__file__).resolve().parents[1]/"scripts/pricefm/502_screen_pricefm_stage_r151_region.py"


@pytest.fixture
def m(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r151_region_test", ENTRY)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    monkeypatch.setattr(value, "OUT", tmp_path/"campaign")
    monkeypatch.setattr(value, "PREP", tmp_path/"prep")
    return value


def test_parent_imports_no_numerical_library_even_when_loading_frozen_producer():
    code = "import importlib.util,sys;s=importlib.util.spec_from_file_location('region',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.producer();assert not any(n in sys.modules for n in ('numpy','pandas','scipy'))"
    subprocess.run([sys.executable, "-B", "-c", code, str(ENTRY)], check=True)


@pytest.mark.parametrize("key,value", [("region", "DK_1"), ("new_model_fits", 1), ("new_geometries", 1),
    ("AL_authorized", True), ("official_evaluation_authorized", True), ("promotion_authorized", True),
    ("test_used_for_selection", True), ("paths", 500), ("max_new_S_components", 24),
    ("max_projected_cpu_seconds", 43200), ("max_numerical_waves", 4), ("maximum_replacement_reserve", 2),
    ("audit_key", "other"), ("extra_seeds", [1, 2]), ("primary_aggregation", "micro")])
def test_frozen_scope_rejects_expansion_or_scientific_drift(m, key, value):
    c = m.read(m.CONFIG); c[key] = value
    with pytest.raises(ValueError): m.validate_config(c)


def test_actual_C0_and_original_AL_alternate_are_distinct_retained_packages(m):
    c = m.validate_config(m.read(m.CONFIG)); by_id = {p["package_id"]: p for p in c["packages"]}
    assert len(by_id) == 21 and len({p["candidate_id"] for p in by_id.values()}) == 20
    assert by_id["C0"]["candidate_id"] == by_id["C0_alt"]["candidate_id"] == "r134_c05562984f2b74bc"
    assert by_id["C0"]["tau0"] == .0024929739307713865
    assert by_id["C0_alt"]["tau0"] == 2.4929739307713866e-5
    c["packages"][-1]["tau0"] = by_id["C0"]["tau0"]
    with pytest.raises(ValueError): m.validate_config(c)


def save_anchors(path, values):
    chars = max(map(len, values)); header = repr(dict(descr="<U"+str(chars), fortran_order=False, shape=(len(values),))).encode()
    header += b" "*((64-(10+len(header)+1)%64)%64)+b"\n"
    body = b"".join(v.ljust(chars, "\0").encode("utf-32-le") for v in values)
    with zipfile.ZipFile(path, "w") as packet:
        packet.writestr("anchors.npy", b"\x93NUMPY\x01\x00"+struct.pack("<H", len(header))+header+body)


def test_cohort_uses_own_pinned_bank_anchors_and_split_helper(m, tmp_path):
    c = m.read(m.CONFIG); base = dt.datetime(2022, 2, 4, tzinfo=dt.timezone.utc)
    anchors = [(base+dt.timedelta(days=i)).isoformat() for i in range(940)]
    path = tmp_path/"bank.npz"; save_anchors(path, anchors)
    assert m.bank_anchors(path) == anchors
    boundaries = m.split_boundaries(c["split_helper"], len(anchors))
    derived = {s: m.cohort(anchors, boundaries, s, [0, 24, 48, 72]) for s in (1, 2, 3)}
    assert [len(derived[s]["daily_origin_positions"]) for s in (1, 2, 3)] == [124, 134, 173]
    for v in derived.values():
        assert v["daily_origin_positions"] == v["validation_origin_positions"][:-1]
        assert max(v["train_origin_positions"])+1 == min(v["validation_origin_positions"])
        first = dt.datetime.fromisoformat(v["origin_timestamps"]["0"][0])
        assert dt.datetime.fromisoformat(v["origin_timestamps"]["72"][0])-first == dt.timedelta(hours=18)
    with pytest.raises(ValueError): m.split_boundaries(c["split_helper"], 939)


def test_banks_reject_nonUTC_nonconsecutive_anchors(m, tmp_path):
    path = tmp_path/"bank.npz"
    save_anchors(path, ["2022-01-01T00:00:00", "2022-01-02T00:00:00"])
    with pytest.raises(ValueError, match="UTC"): m.bank_anchors(path)
    save_anchors(path, ["2022-01-01T00:00:00+00:00", "2022-01-03T00:00:00+00:00"])
    with pytest.raises(ValueError, match="consecutive"): m.bank_anchors(path)


def pool():
    return [dict(package_id=i, candidate_id=g) for i, g in [("C0", "g0"), ("C0_alt", "g0"), ("A", "gA"), ("B", "gB"), ("C", "gC")]]


def test_complete_D_is_required_and_A_is_selected_even_when_loss_worse_than_C0(m):
    ps = pool(); losses = dict(C0=1., C0_alt=3., A=2., B=2.+5e-11, C=4.)
    rule = m.choose_nominees(ps, losses, "C0", "frozen")
    assert rule["A"] == "A"  # Stable ID inside the1e-10 tolerance.
    assert rule["B"] in ("B", "C")
    with pytest.raises(ValueError): m.choose_nominees(ps, dict(losses, missing=1.), "C0", "frozen")
    with pytest.raises(ValueError): m.choose_nominees(ps, {k: v for k, v in losses.items() if k != "C"}, "C0", "frozen")


def test_SHA_nominee_ignores_losses_and_excludes_control_and_A_geometry(m):
    ps = pool(); a = dict(C0=1., C0_alt=.8, A=2., B=3., C=4.)
    one = m.choose_nominees(ps, a, "C0", "frozen")
    two = m.choose_nominees(ps, dict(a, A=90., B=11., C=77.), "C0", "frozen")
    assert one == two and one["A"] == "C0_alt"
    assert one["B"] in ("A", "B", "C")
    assert one["audit_order"] == m.producer().audit_permutation(ps, "frozen")


def test_regional_prefix_includes_all_C0_seed0_and_one_replacement(m):
    ps = pool(); prep = dict(packages=ps, control="C0")
    estimates = {n: dict(estimated_cpu_seconds=1.) for n in m.names_for([v["package_id"] for v in ps], "D", [0])}
    for n in m.names_for([v["package_id"] for v in ps], "S", [0, 1, 2]): estimates[n] = dict(estimated_cpu_seconds=2.)
    result = m.prefix_contract(prep, estimates, 35.)
    assert result["D_CPU_seconds"] == 15.
    assert result["worst_seed0_nomination"]["seed0_CPU_seconds"] == 18.  # C0,A,B ×3splits.
    assert result["replacement_reserve_CPU_seconds"] == 2.
    assert result["worst_prefix_CPU_seconds"] == 35. and result["prefix_admitted"]
    assert not m.prefix_contract(prep, estimates, 34.999)["prefix_admitted"]


def prices(m):
    tasks = {n: dict(estimated_cpu_seconds=2.) for n in m.names_for(["C0", "A", "B"], "S", [1, 2])}
    return dict(task_estimates=tasks, benchmark_adjusted_available_CPU_seconds=100., replacement_reserve_CPU_seconds=4.)


def test_all_qualifiers_and_shared_control_extras_are_atomic_and_window_bounded(m):
    charges = dict(prefix=dict(charged_CPU_seconds=10.))
    decision = m.extra_admission(["prefix"], ["A", "B"], "C0", prices(m), 36., charges, dict(sha256="view"))
    assert len(decision["admitted_extra_components"]) == 18
    assert len(set(decision["admitted_extra_components"])) == 18
    assert len([n for n in decision["admitted_extra_components"] if "_C0_" in n]) == 6
    assert decision["resource_budget_view"] == dict(sha256="view")
    blocked = m.extra_admission(["prefix"], ["A", "B"], "C0", prices(m), 35.999, charges)
    assert blocked["admitted_extra_components"] == [] and len(blocked["unfunded_pending"]) == 18
    assert blocked["qualified"] == ["A", "B"]
    original_limited = m.extra_admission(["prefix"], ["A", "B"], "C0", prices(m), 100., dict(prefix=dict(charged_CPU_seconds=61.)))
    assert original_limited["remaining_CPU_seconds"] == 35. and original_limited["unfunded_pending"]


@pytest.mark.parametrize("allowance", [None, -1., float("nan"), float("inf")])
def test_extra_seed_admission_fails_closed_without_current_finite_windows(m, allowance):
    with pytest.raises(ValueError): m.extra_admission([], ["A"], "C0", prices(m), allowance, {})


def test_no_qualifier_needs_no_extra_seed_work(m):
    d = m.extra_admission([], [], "C0", prices(m), 0., {})
    assert d["atomic_qualified_set_admitted"] and d["required_extra_components"] == []


def toy_context(monkeypatch, m):
    import numpy as np
    anchors = np.asarray(["2023-01-01T00:00:00+00:00", "2023-01-02T00:00:00+00:00"])
    raw = types.SimpleNamespace(anchors=anchors, response=np.full((1, 96), 10.))
    scaled = types.SimpleNamespace(anchors=anchors, response=np.zeros((1, 96)))
    def shifted(value, positions, offset, validation):
        return types.SimpleNamespace(response=value.response, anchors=np.asarray(["2023-01-01T06:00:00+00:00"]))
    module = types.ModuleType("pricefm_r127_contract"); module.shifted_windows = shifted; module.window_identity = lambda *a: None
    monkeypatch.setitem(sys.modules, "pricefm_r127_contract", module)
    calls = []
    def normal(runtime, arrays, spec, fit, positions, seed, **kwargs):
        calls.append(dict(positions=list(positions), seed=seed, paths=kwargs["paths"]))
        return np.zeros((1, 96, 7)), dict(paths=100)
    runtime = types.SimpleNamespace(BASE=types.SimpleNamespace(deterministic_seed=lambda *args: tuple(args)))
    context = dict(runtime=runtime, raw=raw, scaled=scaled, scaler=dict(price_mean=10., price_scale=2.),
                   core=types.SimpleNamespace(normal_predictions=normal), fit={})
    task = dict(mode="S", region="DK_2", forecast_seed=2026101502, split=2, validation_origin_positions=[0, 1], spec={})
    descriptor = dict(name="x", origin_positions=[0], clock_offset_steps=24, stable_rng_origin_keys=[24],
                      origin_timestamps=["2023-01-01T06:00:00+00:00"])
    return context, task, descriptor, calls


def test_original_regional_master_seed_region_split_clock_absolute_origin_are_preserved(m, monkeypatch):
    context, task, descriptor, calls = toy_context(monkeypatch, m)
    m.predict(context, task, descriptor, lambda e: None)
    assert calls == [dict(positions=[24], seed=((2026101502, "DK_2", 2), "clock", 24), paths=100)]
    task["forecast_seed"] = 2026102301
    m.predict(context, task, descriptor, lambda e: None)
    assert calls[-1]["seed"] == ((2026102301, "DK_2", 2), "clock", 24)


def test_region_truth_units_and_absolute_timestamp_cannot_drift(m, monkeypatch):
    context, task, descriptor, _ = toy_context(monkeypatch, m)
    context["raw"].response[:] = 11.
    with pytest.raises(RuntimeError, match="inverse scaler"): m.predict(context, task, descriptor, lambda e: None)
    context["raw"].response[:] = 10.; descriptor["origin_timestamps"] = ["2023-01-01T00:00:00+00:00"]
    with pytest.raises(RuntimeError, match="absolute clock"): m.predict(context, task, descriptor, lambda e: None)


def cpu_fixture(m, monkeypatch):
    task = dict(name="task", scientific_identity_sha256="science")
    prep = dict(source=dict(head="source")); monkeypatch.setattr(m, "read_preparation", lambda: prep)
    monkeypatch.setattr(m, "task_by_name", lambda n, p=None: task)
    monkeypatch.setattr(m, "task_complete", lambda n: True)
    monkeypatch.setattr(m, "pricing", lambda: dict(task_estimates=dict(task=dict(estimated_cpu_seconds=100.))))
    m.write(m.OUT/"tasks_done/task/completed_evidence.json", dict(valid=True))
    def attempt(invocation, total, completed, prior=(), preexisting=0):
        policy = m.PREP/(invocation+".json")
        m.write(policy, dict(task="task", source_head="source", worker_invocation_id=invocation))
        folder = m.OUT/"cpu_accounting/task"/invocation
        started = dict(source=prep["source"], task="task", scientific_identity_sha256="science", policy_invocation_id=invocation,
            policy_receipt_path=str(policy), policy_receipt_sha256=m.digest(policy), prior_started_invocations=list(prior),
            preexisting_checkpoint_count=preexisting)
        observed = dict(started, completed_component=completed, observed_process_CPU_seconds=total-1.,
            observed_terminated_children_CPU_seconds=1., observed_total_CPU_seconds=total,
            task_final_seal_sha256=m.digest(m.OUT/"tasks_done/task/completed_evidence.json") if completed else None,
            post_observation_exit_allowance_CPU_seconds=5., hard_CPU_quota=False, exact_exit_CPU_measurement=False)
        m.write(folder/"started.json", started); m.write(folder/"observed.json", observed)
        m.write(folder/"observed.seal.json", dict(sha256=m.digest(folder/"observed.json"), source=prep["source"]))
        return folder
    return attempt


def test_CPU_credit_sums_every_partial_and_final_attempt_plus_exit_allowance(m, monkeypatch):
    attempt = cpu_fixture(m, monkeypatch); attempt("first", 20., False)
    attempt("last", 30., True, prior=["first"], preexisting=3)
    charge = m.completed_CPU_charge("task")
    assert charge["charged_CPU_seconds"] == 60. and charge["observed_attempts"] == 2
    assert charge["credit_eligible"] and charge["verified_final_CPU_receipts"] == 1


def test_missing_prior_CPU_or_missing_final_receipt_keeps_frozen_reservation(m, monkeypatch):
    attempt = cpu_fixture(m, monkeypatch); attempt("last", 30., True, prior=["lost"], preexisting=3)
    charge = m.completed_CPU_charge("task")
    assert charge["charged_CPU_seconds"] == 135. and charge["missing_prior_invocations"] == ["lost"]
    assert not charge["credit_eligible"]


def test_surviving_partial_CPU_cannot_substitute_for_final_attempt(m, monkeypatch):
    attempt = cpu_fixture(m, monkeypatch); attempt("first", 20., False)
    charge = m.completed_CPU_charge("task")
    assert charge["charged_CPU_seconds"] == 125. and charge["verified_final_CPU_receipts"] == 0


def test_final_scientific_seal_tampering_revokes_CPU_credit(m, monkeypatch):
    attempt = cpu_fixture(m, monkeypatch); attempt("last", 30., True)
    m.write(m.OUT/"tasks_done/task/completed_evidence.json", dict(valid="changed"))
    charge = m.completed_CPU_charge("task")
    assert charge["charged_CPU_seconds"] == 100. and not charge["credit_eligible"]


def test_unfunded_MC_is_pending_and_cannot_finalize(m, monkeypatch):
    monkeypatch.setattr(m, "read_preparation", lambda: dict(source={}, packages=[]))
    monkeypatch.setattr(m, "manifest_state", lambda: ("MATCHED_MC_UNFUNDED_PENDING", ["one"], ["one"], False))
    with pytest.raises(RuntimeError, match="incomplete"): m.finalize()


def test_budget_deferred_or_unsealed_assessment_is_not_scientific_completion(m, monkeypatch):
    prep = dict(source=dict(head="source")); monkeypatch.setattr(m, "read_preparation", lambda: prep)
    monkeypatch.setattr(m, "manifest_state", lambda: ("DEFERRED_UNFUNDED_PREFIX", [], [], True))
    monkeypatch.setattr(m, "pricing", lambda: dict(resource_projection={}))
    result = dict(source=prep["source"], status="R151_REGION_DEFERRED_UNFUNDED_COMPLETE_PREFIX", scientific_complete=False)
    m.write(m.OUT/"assessment.json", result)
    assert not m.queue_state()["scientific_complete"]
    m.write(m.OUT/"assessment_seal.json", dict(source=prep["source"], sha256=m.digest(m.OUT/"assessment.json")))
    assert not m.queue_state()["scientific_complete"]
    m.write(m.OUT/"assessment.json", dict(result, status="changed"))
    with pytest.raises(RuntimeError, match="assessment seal"): m.queue_state()


def test_actual_local_metadata_rehash_and_original_split_cohorts(m):
    audit = m.metadata_audit()
    assert audit["packages"] == 21 and audit["potential_components"] == 252
    assert audit["input_pins"] >= 990
    assert audit["cohort_audit"]["bank_origins"] == 940
    assert audit["cohort_audit"]["daily_counts"] == dict(zip(["1", "2", "3"], [124, 134, 173]))


def test_full_S_component_counts_include_control_and_shared_extras(m):
    initial = m.names_for(["C0", "A", "B"], "S", [0])
    assert len(initial) == 9
    one = m.extra_admission([], ["A"], "C0", prices(m), 100., {})
    both = m.extra_admission([], ["A", "B"], "C0", prices(m), 100., {})
    assert len(initial+one["required_extra_components"]) == 21
    assert len(initial+both["required_extra_components"]) == 27
    assert len(set(initial+both["required_extra_components"])) == 27


def test_benchmark_keeps_sealed_unit_auditable_panels_without_computing_loss(m, monkeypatch):
    import numpy as np
    c = m.read(m.CONFIG); original = m.producer()
    descriptor = dict(name="clock00_part000", origin_positions=[506], clock_offset_steps=0,
        origin_timestamps=["2023-06-25T00:00:00+00:00"], stable_rng_origin_keys=[506*96])
    wrapper = types.SimpleNamespace(**{k: getattr(original, k) for k in (
        "strongest", "audit_permutation", "retained_arrays", "verify_packet")})
    wrapper.numerical_context = lambda prep, task: dict(scaler=dict(price_mean=10., price_scale=2.))
    wrapper.chunks = lambda task: [descriptor]
    wrapper.kernel = lambda: types.SimpleNamespace(numerical_threadpools=lambda: [dict(num_threads=1)])
    estimates = {n: dict(estimated_cpu_seconds=1., estimated_max_chunk_wall_seconds=1.)
        for n in m.names_for([p["package_id"] for p in c["packages"]], "D", [0])
        +m.names_for([p["package_id"] for p in c["packages"]], "S", [0, 1, 2])}
    wrapper.prospective_costs = lambda *args: dict(task_estimates=estimates)
    monkeypatch.setattr(m, "producer", lambda: wrapper)
    monkeypatch.setattr(m, "task_by_name", lambda n, prep: dict(name=n, mode="D" if "_D_" in n else "S", p=385,
        spec=next(p["spec"] for p in c["packages"] if n.startswith("DK_2_"+p["package_id"]+"_"))))
    monkeypatch.setattr(m, "predict", lambda *args: (np.zeros((1, 96, 7)), np.zeros((1, 96)), {}))
    monkeypatch.setattr(m, "legacy_control_replay", lambda *args: dict(status="TEST_CALL_CHAIN_ONLY"))
    fake = types.ModuleType("pricefm_r126_contract"); fake.loss = lambda *args: pytest.fail("benchmark cannot compute any candidate AQL")
    monkeypatch.setitem(sys.modules, "pricefm_r126_contract", fake)
    prep = dict(source=dict(head="source"), packages=c["packages"], control="C0", tasks=[])
    m.write(m.PREP/"preparation.json", prep); monkeypatch.setattr(m, "read_preparation", lambda: prep)
    receipt = m.PREP/"policy.json"; m.write(receipt, dict(lease_expires_epoch=m.time.time()+1200.))
    result = m.benchmark(prep, 29, receipt)
    assert result["prefix_admitted"]
    assert m.task_complete("__benchmark__")
    timing = m.read(m.OUT/"benchmark/timings.json")
    assert len(timing["rows"]) == 16
    assert timing["timed_prediction_calls"] == 16 and timing["untimed_control_replay_prediction_calls"] == 2
    assert timing["arithmetic_calls"] == 18
    for row in timing["rows"]:
        path = m.OUT/"benchmark"/row["retained_prediction_packet"]
        assert m.digest(path) == row["retained_prediction_sha256"]
        with np.load(path, allow_pickle=False) as panel:
            assert np.array_equal(panel["origin_AQL"], [0.])
            assert np.array_equal(panel["truth_eur"], np.full((1, 96), 10.))
            assert np.array_equal(panel["prediction_eur"], np.full((1, 96, 7), 10.))
    path.write_bytes(b"broken")
    with pytest.raises(RuntimeError, match="pinned artifact"): m.task_complete("__benchmark__")


def lease_fixture(m, wave="1"):
    prep = dict(source=dict(head="source")); m.write(m.PREP/"preparation.json", prep)
    base = m.PREP/"muscat_resources"; outer = m.PREP/"outer.json"
    m.write(outer, dict(unit="outer", attested=dict(InvocationID="outer-invocation")))
    m.write(base/"outer_context.json", dict(run_id="run", outer_capsule_path=str(outer)))
    seconds = 1200 if wave == "benchmark" else 7200
    lease = dict(stage="R151_REGION", region="DK_2", wave=wave, lease_id="lease", started_epoch=0., expires_epoch=float(seconds),
        seconds=seconds, nonrenewing=True, source_head="source", boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        preparation_sha256=m.digest(m.PREP/"preparation.json"), outer_context_sha256=m.digest(base/"outer_context.json"),
        orchestration_config_sha256=m.digest(m.ROOT/"application/config/pricefm_stage_r151_orchestration_20261023.json"),
        outer_run_id="run", outer_unit="outer", outer_invocation_id="outer-invocation")
    m.write(base/("wave_"+wave)/"lease.json", lease)
    return prep, lease, dict(lease_id="lease", lease_expires_epoch=float(seconds))


def test_worker_binds_to_one_exact_immutable_regional_admission(m):
    prep, lease, receipt = lease_fixture(m)
    assert m.validate_worker_lease(receipt, prep, "DK_2_C0_s1_D_seed0", now=100.) == lease
    m.write(m.PREP/"muscat_resources/wave_2/lease.json", lease)
    with pytest.raises(RuntimeError, match="exactly one"): m.validate_worker_lease(receipt, prep, "D", now=100.)


@pytest.mark.parametrize("change", [dict(stage="other"), dict(region="EE"), dict(source_head="other"),
    dict(preparation_sha256="other"), dict(boot_id="other"), dict(nonrenewing=False), dict(seconds=7300),
    dict(expires_epoch=7300.), dict(outer_context_sha256="other"), dict(outer_invocation_id="replacement")])
def test_worker_rejects_mutated_lease_or_outer_lifetime(m, change):
    prep, lease, receipt = lease_fixture(m); lease.update(change)
    m.write(m.PREP/"muscat_resources/wave_1/lease.json", lease)
    with pytest.raises(RuntimeError): m.validate_worker_lease(receipt, prep, "DK_2_C0_s1_D_seed0", now=100.)


def test_worker_cannot_repurpose_benchmark_or_expired_admission(m, monkeypatch):
    prep, lease, receipt = lease_fixture(m, "benchmark")
    assert m.validate_worker_lease(receipt, prep, "__benchmark__", now=100.) == lease
    with pytest.raises(RuntimeError, match="benchmark admission"): m.validate_worker_lease(receipt, prep, "DK_2_C0_s1_D_seed0", now=100.)
    monkeypatch.setattr(m, "task_complete", lambda n: True); monkeypatch.setattr(m, "pricing", lambda: dict(prefix_admitted=False))
    assert m.validate_worker_lease(receipt, prep, "__finalize__", now=100.) == lease
    monkeypatch.setattr(m, "pricing", lambda: dict(prefix_admitted=True))
    with pytest.raises(RuntimeError, match="nondeferred"): m.validate_worker_lease(receipt, prep, "__finalize__", now=100.)
    with pytest.raises(RuntimeError, match="finite lease"): m.validate_worker_lease(receipt, prep, "__benchmark__", now=1200.)


def test_benchmark_cannot_consume_numerical_wave(m):
    prep, _, receipt = lease_fixture(m)
    with pytest.raises(RuntimeError, match="benchmark cannot"): m.validate_worker_lease(receipt, prep, "__benchmark__", now=100.)


@pytest.mark.parametrize("field,value", [("pid", -1), ("start_ticks", -1), ("boot_id", "other")])
def test_worker_proof_checks_current_pid_start_ticks_boot_but_allows_exec_change(m, field, value):
    process = dict(pid=m.os.getpid(), start_ticks=int(Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()[19]),
        boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip(), argv=["previous-bootstrap-before-exec"])
    m.validate_worker_process(process)
    process[field] = value
    with pytest.raises(RuntimeError, match="process lifetime"): m.validate_worker_process(process)


def test_parent_moments_must_match_external_frozen_audit_not_only_new_self_consistent_seal(m, tmp_path):
    directory = tmp_path/"parent"; contract = tmp_path/"contract.json"
    record = dict(directory=str(directory), completed_evidence_sha256="seal", beta_mean_sha256="mean",
        beta_cov_sha256="cov", contract_sha256="contract", p=385, n=100, omega_shape=52,
        omega_rate=10., posterior_target_sha256="frozen-target")
    ledger = {str(directory/"completed_evidence.json"): "seal", str(directory/"fit/beta_mean.bin"): "mean",
        str(directory/"fit/beta_cov.bin"): "cov", str(contract): "contract"}
    summary = {k: record[k] for k in ("p", "n", "omega_shape", "omega_rate", "posterior_target_sha256")}
    summary["full_variational_certified"] = True
    m.verify_evidence_lineage(record, directory, ledger, summary, contract)
    with pytest.raises(RuntimeError, match="prospectively pinned"):
        m.verify_evidence_lineage(record, directory, dict(ledger, **{str(directory/"fit/beta_cov.bin"): "new-self-consistent-cov"}), summary, contract)
    with pytest.raises(RuntimeError, match="prospectively pinned"):
        m.verify_evidence_lineage(record, directory, ledger, dict(summary, posterior_target_sha256="new-target"), contract)
