"""Scientific replay, resumability and aggregation tests; no fits or official data."""
import copy
import datetime as dt
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import types

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py"


@pytest.fixture
def m(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r149_science_test", ENTRY)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    monkeypatch.setattr(value, "OUT", tmp_path / "campaign")
    monkeypatch.setattr(value, "PREP", tmp_path / "prep")
    return value


def task_fixture(m, tmp_path, seed_index=1):
    scaler = tmp_path / "scaler.json"
    m.write(scaler, dict(price_mean=10., price_scale=2.))
    start = dt.datetime(2023, 1, 1, tzinfo=dt.timezone.utc)
    daily = list(range(10, 22))
    task = dict(name="EE_C0_s1_mc_seed1_panel48", region="EE", role="C0", split=1,
        kind="mc_panel_replay", candidate_id="r134_control", spec={}, tau0=.002,
        parent_source=dict(head="original-fit-source"), parent_task="original_fit",
        parent_seal_sha256="sealed-fit", parent_input_sha256={}, parent_fit="fit",
        scaler_path=str(scaler), scaler_sha256=m.digest(scaler), bank=dict(path="train.npz", sha256="bank"),
        paths=100, forecast_seed=567, seed_index=seed_index, clock_offsets_steps=[0, 24, 48, 72],
        daily_origin_positions=daily, validation_origin_positions=daily+[22], train_origin_positions=[0, 1],
        origin_timestamps={str(offset): [(start+dt.timedelta(days=i-10, minutes=15*offset)).isoformat()
            for i in daily] for offset in (0, 24, 48, 72)},
        original_panels=dict(small=[0, 3, 7, 11], large=list(range(12))),
        parent_r148_result="old_result.json", parent_r148_result_sha256="old-result", kernel_sha256="frozen-kernel",
        dependency_task="EE_C0_s1_full_seed0", posterior_updated=False, new_model_fits=0, test_opened=False)
    task["scientific_identity_sha256"] = m.fingerprint(m.scientific_identity(task))
    return task


def arrays_fixture(m, task, descriptor=None):
    rows = m.expected_rows(task, descriptor)
    a = {k: np.zeros(shape, dtype="<i8" if k in m.INT_ARRAYS else "<f8")
        for k, shape in m.array_shapes(len(rows), reference=descriptor is None and task["seed_index"] == 0).items()}
    for key in ("truth_eur", "deterministic_eur", "stochastic_eur"):
        a[key].fill(10.)
    for i, (position, offset, stamp) in enumerate(rows):
        anchor = dt.datetime.fromisoformat(stamp)
        for key, value in (("origin_positions", position), ("clock_offsets", offset),
                           ("stable_rng_origin_keys", position*96+offset),
                           ("origin_timestamps_ns", round(anchor.timestamp()*1e9)),
                           ("weekday_UTC", anchor.weekday()), ("month_UTC", anchor.month)):
            a[key][i] = value
    return a


def test_import_is_light():
    code = "import importlib.util,sys;s=importlib.util.spec_from_file_location('r149',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);assert 'numpy' not in sys.modules"
    subprocess.run([sys.executable, "-B", "-c", code, str(ENTRY)], check=True)


@pytest.mark.parametrize("field", ["al_authorized", "official_evaluation_authorized", "automatic_future_stage_authorized"])
def test_config_cannot_expand_stage(m, field):
    c = m.read(m.CONFIG)
    c[field] = True
    with pytest.raises(ValueError):
        m.validate_config(c)


def test_original_provenance_and_seed_have_stable_scientific_identity(m, tmp_path):
    task = task_fixture(m, tmp_path)
    original = m.scientific_identity(task)
    changed = dict(task, name="future_exact_reuse_name", producer_source="future")
    assert m.scientific_identity(changed) == original
    changed["forecast_seed"] += 1
    assert m.scientific_identity(changed) != original


def test_npz_standard_library_roundtrip_and_shapes(m, tmp_path):
    task = task_fixture(m, tmp_path)
    arrays = arrays_fixture(m, task)
    path = tmp_path / "prediction.npz"
    np.savez_compressed(path, **arrays)
    loaded = m.load_npz_light(path)
    m.validate_arrays(task, loaded)
    assert loaded["origin_positions"][1].tolist() == task["daily_origin_positions"]*4


@pytest.mark.parametrize("change", ["object", "float32", "missing", "nonfinite"])
def test_npz_invalid_payload_is_rejected(m, tmp_path, change):
    task = task_fixture(m, tmp_path)
    arrays = arrays_fixture(m, task)
    if change == "object":
        arrays["truth_eur"] = arrays["truth_eur"].astype(object)
    elif change == "float32":
        arrays["truth_eur"] = arrays["truth_eur"].astype("<f4")
    elif change == "missing":
        del arrays["origin_positions"]
    else:
        arrays["stochastic_eur"][0, 0, 0] = np.nan
    path = tmp_path / "prediction.npz"
    np.savez_compressed(path, **arrays)
    with pytest.raises(RuntimeError):
        m.validate_arrays(task, m.load_npz_light(path))


def test_resume_reuses_valid_sealed_chunk_without_numerical_replay(m, tmp_path, monkeypatch):
    task = task_fixture(m, tmp_path)
    descriptor = m.chunk_descriptors(task)[0]
    arrays = arrays_fixture(m, task, descriptor)
    prep = dict(source=dict(head="new-producer", branch="new"))
    pools = [dict(num_threads=1)]
    monkeypatch.setattr(m, "kernel", lambda: types.SimpleNamespace(numerical_threadpools=lambda: pools))
    calls = []
    def compute(*args):
        calls.append(True)
        return arrays, dict(paths=100)
    monkeypatch.setattr(m, "retained_chunk", compute)
    m.seal_chunk(prep, task, descriptor, {}, lambda _: None)
    recovered, _ = m.seal_chunk(prep, task, descriptor, {}, lambda _: None)
    assert calls == [True]
    assert np.array_equal(recovered["stochastic_standardized"], arrays["stochastic_standardized"])
    metadata = m.read(m.OUT / "checkpoints" / task["name"] / descriptor["name"] / "chunk.json")
    assert metadata["context"]["original_parent_source"] == task["parent_source"]


def test_corrupted_checkpoint_fails_closed_and_partial_attempt_is_not_reused(m, tmp_path, monkeypatch):
    task = task_fixture(m, tmp_path)
    descriptor = m.chunk_descriptors(task)[0]
    arrays = arrays_fixture(m, task, descriptor)
    prep = dict(source=dict(head="head"))
    monkeypatch.setattr(m, "kernel", lambda: types.SimpleNamespace(numerical_threadpools=lambda: [dict(num_threads=1)]))
    monkeypatch.setattr(m, "retained_chunk", lambda *args: (arrays, {}))
    partial = m.OUT / "attempts" / task["name"] / "interrupted"
    m.write(partial / "chunk.json", {"incomplete": True})
    m.seal_chunk(prep, task, descriptor, {}, lambda _: None)
    folder = m.OUT / "checkpoints" / task["name"] / descriptor["name"]
    (folder / "predictions.npz").write_bytes(b"corrupt")
    with pytest.raises(RuntimeError, match="changed"):
        m.seal_chunk(prep, task, descriptor, {}, lambda _: None)
    assert (partial / "chunk.json").exists()


def test_dag_prioritizes_full_and_does_not_confuse_blocked_mc_with_complete(m, monkeypatch):
    tasks = [dict(name="full1", seed_index=0, role="C0", split=1, dependency_task=None),
             dict(name="mc1", seed_index=1, role="C0", split=1, dependency_task="full1"),
             dict(name="full2", seed_index=0, role="C0", split=2, dependency_task=None)]
    monkeypatch.setattr(m, "read_preparation", lambda: dict(tasks=tasks))
    monkeypatch.setattr(m, "task_complete", lambda name: name == "full1")
    assert m.pending_task_names() == ["full2", "mc1"]
    assert not m.all_tasks_complete()
    monkeypatch.setattr(m, "task_complete", lambda name: name == "full2")
    assert m.pending_task_names() == ["full1"]
    assert not m.all_tasks_complete()


def test_guard_precedes_numerical_import_and_worker_side_effects(m, monkeypatch):
    monkeypatch.setattr(m, "guarded_runtime", lambda cpu: (_ for _ in ()).throw(RuntimeError("guard")))
    monkeypatch.setattr(m, "read_preparation", lambda: pytest.fail("must guard first"))
    with pytest.raises(RuntimeError, match="guard"):
        m.worker("not_prepared", 0)


def test_metrics_preserve_equal_origin_and_clock_weights(m, tmp_path):
    task = task_fixture(m, tmp_path)
    a = arrays_fixture(m, task)
    # An origin has a distinct constant forecast error at every horizon/quantile.
    for i in range(48):
        a["stochastic_standardized"][i] = i
        a["stochastic_eur"][i] = 10+2*i
        a["stochastic_origin_AQL"][i] = i
    m.validate_arrays(task, a)
    assert m.metrics_light(a)["stochastic"]["AQL"] == 23.5


def test_exante_regime_thresholds_use_only_exact_training_histories(m):
    history = np.zeros((5, 96))
    history[2:] = 1000000.*np.arange(96)
    raw = types.SimpleNamespace(price_history=history)
    value = m.training_lag_thresholds(raw, [0, 1])
    assert value["q50"] == value["q90"] == [0.]*4
    assert value["training_origin_positions"] == [0, 1]


def test_macro_and_pooled_objectives_are_reported_separately(m, monkeypatch):
    tasks, results = [], {}
    for role in ("C0", "C5"):
        for split, count in ((1, 124), (2, 134), (3, 173)):
            name = f"{role}_{split}"
            tasks.append(dict(name=name, role=role, split=split, seed_index=0))
            metric = dict(AQL=float(split), median_MAE=0., coverage_80=0., width_80=0.)
            results[name] = dict(metrics={p: dict(metric) for p in ("deterministic", "stochastic")},
                                 origin_clock_windows=4*count,
                                 original_nested_panel_metrics={"48": {"stochastic": dict(metric)}})
    original_read = m.read
    monkeypatch.setattr(m, "read_preparation", lambda: dict(tasks=tasks, source={"head": "head"}))
    monkeypatch.setattr(m, "task_complete", lambda _: True)
    monkeypatch.setattr(m, "read", lambda p: results[Path(p).parent.name] if Path(p).name == "result.json" else original_read(p))
    scores = m.status()["complete_three_split_scores"]["C0_seed0"]
    assert scores["equal_split_macro"]["stochastic"]["AQL"] == 2.
    assert scores["pooled_origin_clock"]["stochastic"]["AQL"] == pytest.approx((124+2*134+3*173)/431)


def test_real_frozen_helpers_preserve_chunk_and_origin_rng_identity(m):
    """Tiny synthetic pure reservoir; supplied moments only, zero fitting."""
    from threadpoolctl import threadpool_limits
    parent = m.read(m.read(m.CONFIG)["parent_preparation"])
    if not Path(parent["dependency"]).exists():
        pytest.skip("frozen numerical dependency unavailable")
    with threadpool_limits(limits=1):
        core, runtime = m.load_numerical(parent)
        spec = dict(region="EE", feature_policy="target_only", calendar="none", readout="pure_all_layers",
            m_y=32, m_x=0, source_window=3120, warmup_steps=240, depth=2, units=[48, 32],
            alpha=.15, rho=.55, input_scale=.01, input_fan_in=8, recurrent_sparsity=.1,
            interlayer_gain=1., input_policy="coverage", seed=17)
        rng = np.random.default_rng(91)
        arrays = runtime.ExplicitArrays(rng.normal(size=(3, 3120)), rng.normal(size=(3, 3120, 1)),
            rng.normal(size=(3, 96, 1)), rng.normal(size=(3, 96)),
            np.array(["2023-01-01T00:00:00+00:00", "2023-01-02T00:00:00+00:00", "2023-01-03T00:00:00+00:00"]),
            ("EE::load",), ())
        fit = dict(beta_mean=np.linspace(-.05, .05, 81), beta_cov=np.eye(81)*1e-4,
            omega_mean=.04, omega_shape=100., omega_rate=3.96, prior_type="rhs_ns")
        deterministic = m.kernel().deterministic_predictions(runtime, arrays, spec, fit)
        keys = np.array([101, 202, 303])
        full, _ = core.normal_predictions(runtime, arrays, spec, fit, keys, 318, paths=8)
        order = np.array([2, 0])
        subset = core.slice_arrays(runtime, arrays, order)
        sparse, _ = core.normal_predictions(runtime, subset, spec, fit, keys[order], 318, paths=8)
        assert sparse.tobytes() == full[order].tobytes()
        np.testing.assert_allclose(m.kernel().deterministic_predictions(runtime, subset, spec, fit),
                                   deterministic[order], rtol=1e-10, atol=1e-12)
