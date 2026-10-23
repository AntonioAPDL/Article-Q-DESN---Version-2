"""R148 scientific boundaries: cached moments only, honest panels and strict seals."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import types

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py"


@pytest.fixture
def m(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("r148_scientific_test", ENTRY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "OUT", tmp_path / "campaign")
    monkeypatch.setattr(module, "PREP", tmp_path / "prep")
    return module


def task():
    return dict(name="EE_cached_rhs_r134_example_s1", kind="cached_rhs_rescore",
                candidate_id="r134_example", split=1, tau0=.001,
                panels=dict(validation_origin_positions=list(range(12)),small=[0,3,7,11],large=list(range(12))))


def result(t=None):
    t = t or task()
    metric = dict(AQL=2., median_MAE=3., coverage_80=.8, width_80=4.)
    variants = ["deterministic16", "deterministic48", "stochastic16", "stochastic48"]
    return dict(certified=True, kind="cached_rhs_rescore", candidate_id=t["candidate_id"],
        split=t["split"], tau0=t["tau0"], paths=100, test_opened=False, posterior_updated=False,
        new_model_fits=0, original_cached_moments_unchanged=True,
        numerical_threadpools=[dict(internal_api="openblas", num_threads=1)],
        metrics={k: dict(metric) for k in variants}, clock_metrics={k: [dict(metric) for _ in range(4)] for k in variants},
        origin_identities=[dict(clock_offset_steps=i, daily_origin_positions_small=[0, 3, 7, 11],
            daily_origin_positions_large=list(range(12)), stable_rng_origin_keys=[v*96+i for v in range(12)],
            small_reused_from_large=True) for i in (0, 24, 48, 72)])


def seal_result(m, t=None):
    t = t or task()
    folder = m.OUT / "tasks_done" / t["name"]
    m.write(m.OUT / "tasks" / (t["name"] + ".json"), t)
    m.write(m.PREP / "preparation.json", dict(source=dict(head="newhead")))
    m.write(folder / "result.json", result(t))
    seal = dict(artifacts={"result.json": m.digest(folder / "result.json")},
                metadata=dict(source_head="newhead", certified=True,
                    task_sha256=m.digest(m.OUT / "tasks" / (t["name"] + ".json"))))
    m.write(folder / "completed_evidence.json", seal)
    return folder, seal


def test_import_does_not_initialize_numerical_libraries():
    code = "import importlib.util,sys; s=importlib.util.spec_from_file_location('r148',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert 'numpy' not in sys.modules"
    subprocess.run([sys.executable, "-B", "-c", code, str(ENTRY)], check=True)


def test_config_has_zero_new_geometries_or_fits(m):
    config = m.validate_config(m.read(m.CONFIG))
    assert config["new_ridge_geometries"] == config["new_ridge_split_fits"] == 0
    assert config["allowed_worker_kinds"] == ["cached_rhs_rescore"]


@pytest.mark.parametrize("field", ["new_rhs_fits_authorized", "al_authorized", "mcmc_authorized", "official_evaluation_authorized", "promotion_authorized"])
def test_scope_cannot_enable_another_stage(m, field):
    config = m.read(m.CONFIG)
    config[field] = True
    with pytest.raises(ValueError):
        m.validate_config(config)


def test_distinct_geometry_selection_preserves_actual_control_scale_and_score(m):
    rows = [dict(candidate_id="a", tau0=.1, mean_AQL=1.), dict(candidate_id="a", tau0=1., mean_AQL=1.1),
            dict(candidate_id="b", tau0=.2, mean_AQL=2.)]
    selected = m.distinct_selection(rows, dict(candidate_id="a", tau0=1.), 2)
    assert selected[0]["tau0"] == 1.
    assert selected[0]["mean_AQL"] == 1.1
    assert [r["candidate_id"] for r in selected] == ["a", "b"]


@pytest.mark.parametrize("size", [80, 121, 132, 169])
def test_panels_preserve_old_four_and_have_nested_exact_twelve(m, size):
    import numpy as np
    panels = m.panel_indices(size)
    assert panels["small"] == sorted(set(np.linspace(0, size - 2, 4).round().astype(int)))
    assert len(panels["large"]) == 12
    assert set(panels["small"]) < set(panels["large"])
    assert len(set(panels["large"]) - set(panels["small"])) == 8
    assert m.panel_indices(size) == panels


def test_original_rhs_grid_is_recorded_without_nested_assumption(m):
    panels = m.panel_indices(132)
    assert panels["historical_rhs"] != panels["large"]
    assert not panels["large_equals_historical_rhs"]


def test_strict_complete_packet(m):
    seal_result(m)
    assert m.task_complete(task()["name"])


@pytest.mark.parametrize("change", ["empty", "source", "uncertified", "checksum", "nan", "missing_clock", "identity", "posterior_updated"])
def test_bogus_completion_never_advances_queue(m, change):
    folder, seal = seal_result(m)
    if change == "empty":
        seal["artifacts"] = {}
    elif change == "source":
        seal["metadata"]["source_head"] = "wrong"
    elif change == "uncertified":
        seal["metadata"]["certified"] = False
    elif change == "checksum":
        seal["artifacts"]["result.json"] = "0" * 64
    else:
        payload = m.read(folder / "result.json")
        if change == "nan":
            payload["metrics"]["deterministic16"]["AQL"] = "nan"
        elif change == "missing_clock":
            payload["clock_metrics"]["stochastic48"].pop()
        elif change == "identity":
            payload["split"] = 2
        else:
            payload["posterior_updated"] = True
        m.write(folder / "result.json", payload)
        seal["artifacts"]["result.json"] = m.digest(folder / "result.json")
    m.write(folder / "completed_evidence.json", seal)
    with pytest.raises(RuntimeError):
        m.task_complete(task()["name"])


def test_cached_packet_requires_moments_even_with_a_valid_seal(m, tmp_path):
    cache = tmp_path / "old"
    name = "rhs_EE_a_s1"
    m.write(cache / "tasks" / (name + ".json"), dict(kind="rhs"))
    folder = cache / "tasks_done" / name
    m.write(folder / "result.json", dict(certified=True))
    m.write(folder / "completed_evidence.json", dict(artifacts={"result.json": m.digest(folder / "result.json")},
        metadata=dict(source_head="old", certified=True, task_sha256=m.digest(cache / "tasks" / (name + ".json")))))
    with pytest.raises(RuntimeError, match="required artifacts"):
        m.verify_cached_packet(cache, name, "old")


def test_ordinary_direct_launch_fails_before_numerical_import(m, monkeypatch):
    monkeypatch.setattr(m.os, "sched_setaffinity", lambda *a: None)
    monkeypatch.setattr(m.os, "sched_getaffinity", lambda *a: {2})
    monkeypatch.setattr(m.os, "sched_getscheduler", lambda *a: os.SCHED_OTHER)
    monkeypatch.setattr(m, "load_engine", lambda *a: pytest.fail("must not load numerical engine"))
    with pytest.raises(RuntimeError, match="SCHED_IDLE"):
        m.worker(task()["name"], 2)


def test_guard_checks_io_and_threads(m, monkeypatch):
    monkeypatch.setattr(m.os, "sched_getaffinity", lambda *a: {2})
    monkeypatch.setattr(m.os, "sched_getscheduler", lambda *a: os.SCHED_IDLE)
    monkeypatch.setattr(m.subprocess, "check_output", lambda *a, **k: "idle\n")
    for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        monkeypatch.setenv(key, "1")
    m.guarded_runtime(2)
    monkeypatch.setenv("OPENBLAS_NUM_THREADS", "8")
    with pytest.raises(RuntimeError, match="thread"):
        m.guarded_runtime(2)


def test_immutable_records_cannot_silently_change(m, tmp_path):
    p = tmp_path / "frozen.json"
    m.immutable(p, dict(a=1))
    with pytest.raises(RuntimeError):
        m.immutable(p, dict(a=2))


def test_rank_fidelity_handles_ties_and_flat_scores(m):
    assert m.spearman([1, 2, 3], [3, 2, 1]) == -1
    assert m.spearman([1, 1, 3], [2, 2, 4]) == 1
    assert m.spearman([1, 1], [2, 3]) is None


def test_historical_rank_context_collapses_tau_and_labels_conditioning(m):
    ridge = dict(ranking=[dict(candidate_id="a", mean_AQL=1.),dict(candidate_id="b", mean_AQL=2.),dict(candidate_id="c", mean_AQL=3.)])
    rhs = dict(ranking=[dict(candidate_id="b", mean_AQL=1.,tau0=.1),dict(candidate_id="b", mean_AQL=1.01,tau0=1.),dict(candidate_id="a", mean_AQL=2.,tau0=.1)])
    context = m.proxy_rank_context(ridge,rhs)
    assert context["Ridge_geometry_count"] == 3
    assert context["RHS_certified_distinct_geometries"] == 2
    assert context["conditional_Ridge_vs_RHS_Spearman"] == -1
    assert "conditional_on_Ridge_shortlist" in context["limitation"]


def test_loaded_multithread_numerical_pool_is_rejected(m, monkeypatch):
    import threadpoolctl
    monkeypatch.setattr(threadpoolctl, "threadpool_info", lambda: [dict(internal_api="openblas", num_threads=8)])
    with pytest.raises(RuntimeError, match="one thread"):
        m.numerical_threadpools()


def test_saved_multithread_pool_proof_is_rejected(m):
    payload = result()
    payload["numerical_threadpools"][0]["num_threads"] = 8
    with pytest.raises(RuntimeError, match="one-thread"):
        m.validate_result(payload, task())


def test_interrupted_scoring_never_publishes_a_result(m, monkeypatch):
    t = task()
    m.write(m.OUT / "tasks" / (t["name"] + ".json"), t)
    prep = dict(tasks=[t], source_sha256={}, dependency="dep", dependency_head="head")
    monkeypatch.setattr(m, "read_preparation", lambda: prep)
    monkeypatch.setattr(m.os, "sched_setaffinity", lambda *a: None)
    monkeypatch.setattr(m, "guarded_runtime", lambda *a: None)
    monkeypatch.setattr(m, "git", lambda root, *args: "head" if args[0] == "rev-parse" else "")
    monkeypatch.setattr(m, "load_engine", lambda *a: types.SimpleNamespace(setup=lambda *a: None))
    def interrupted(*args):
        raise RuntimeError("lease ended")
    monkeypatch.setattr(m, "score_cached", interrupted)
    with pytest.raises(RuntimeError, match="lease ended"):
        m.worker(t["name"], 2)
    assert not (m.OUT / "tasks_done" / t["name"]).exists()
    assert len(list((m.OUT / "attempts" / t["name"]).iterdir())) == 1


def test_real_frozen_runtime_math_and_origin_rng_invariance(m):
    """Tiny synthetic reservoir, supplied moments only: no model is fitted."""
    import numpy as np
    from threadpoolctl import threadpool_limits
    config = m.read(m.CONFIG)
    if not Path(config["engine_root"]).exists():
        pytest.skip("frozen scientific dependency is not available on this machine")
    with threadpool_limits(limits=1):
        engine = m.load_engine(config)
        # Frozen runtime setup imports source only; this test never reads banks,
        # posterior packets, raw prices, official arrays or any R optimizer.
        dependency = m.read(config["cache_preparation"])["dependency"]
        runtime = engine.setup(Path(dependency))
        spec = dict(region="EE", feature_policy="target_only", calendar="none",
            readout="pure_all_layers", m_y=32, m_x=0, source_window=3120,
            warmup_steps=240, depth=2, units=[48,32], alpha=.15, rho=.55,
            input_scale=.01, input_fan_in=8, recurrent_sparsity=.1,
            interlayer_gain=1., input_policy="coverage", seed=17)
        rng = np.random.default_rng(91)
        arrays = runtime.ExplicitArrays(rng.normal(size=(3,3120)),
            rng.normal(size=(3,3120,1)), rng.normal(size=(3,96,1)),
            rng.normal(size=(3,96)), np.array(["2023-01-01T00:00:00+00:00",
                "2023-01-02T00:00:00+00:00", "2023-01-03T00:00:00+00:00"]), ("EE::load",), ())
        fit = dict(beta_mean=np.linspace(-.05,.05,81), beta_cov=np.eye(81)*1e-4,
            omega_mean=.04, omega_shape=100., omega_rate=3.96, prior_type="rhs_ns")
        from pricefm_r127_contract import common_metrics
        actual = m.deterministic_predictions(runtime, arrays, spec, fit)
        metrics = common_metrics(arrays.response,actual)
        frozen = runtime.recursive_normal_score(arrays,spec,fit,np.arange(3))
        for key, old in [("AQL","AQL"),("median_MAE","median_MAE"),
                         ("coverage_80","interval_80_coverage"),("width_80","interval_80_width")]:
            assert metrics[key] == pytest.approx(frozen[old],rel=1e-12,abs=1e-12)
        order = np.array([2,0])
        subset = engine.core.slice_arrays(runtime,arrays,order)
        np.testing.assert_allclose(m.deterministic_predictions(runtime,subset,spec,fit),
                                   actual[order],rtol=1e-12,atol=1e-12)
        origin_keys = np.array([101,202,303])
        sampled, _ = engine.core.normal_predictions(runtime,arrays,spec,fit,origin_keys,318,paths=8)
        reordered, _ = engine.core.normal_predictions(runtime,subset,spec,fit,origin_keys[order],318,paths=8)
        np.testing.assert_allclose(reordered,sampled[order],rtol=1e-12,atol=1e-12)
