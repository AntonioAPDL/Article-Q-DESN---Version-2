from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import numpy as np
import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
sys.path.insert(0, str(SCRIPTS))
from pricefm_r124_covariance import GaussianSampler, POLICY, covariance_factor, projected_audit
import pricefm_r120_engine as ENGINE

loader = importlib.util.spec_from_file_location("r124_test", SCRIPTS / "445_run_pricefm_stage_r124_covariance_replay.py")
RUN = importlib.util.module_from_spec(loader); loader.loader.exec_module(RUN)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def jobs():
    return [dict(tag=RUN.TAG, job_id=f"{candidate}_s{split}", candidate_id=candidate,
        split=split, tau0=1e-4, posterior_paths=500, sampler=POLICY,
        official_test_opened=False, official_validation_opened=False, fitting_authorized=False)
        for candidate in ("r123_6d32d129873c7930", "r123_3e15bdc342f556c1", "r123_8680f8aaeaeae8ce")
        for split in (1, 2, 3)]


@pytest.mark.parametrize("scales", [[1, 1, 1], [1e-7, 1, 1e7], [1e-10, 1e-2, 1e5]])
def test_factor_preserves_anisotropic_covariance_and_projected_variance(scales):
    correlation = np.array([[1, .4, -.2], [.4, 1, .3], [-.2, .3, 1]])
    diagonal = np.array(scales)
    value = diagonal[:, None] * correlation * diagonal[None, :]
    rows = np.array([[1, 2, 3], [4, -2, 1], [-3, 2, 5]]) / diagonal[None, :]
    original = value.copy(); factor, audit = covariance_factor(value)
    np.testing.assert_allclose(factor @ factor.T, value, rtol=1e-12, atol=1e-30)
    assert np.array_equal(original, value)
    assert audit["covariance_inflation"] == 0
    assert audit["eigenvalue_clipping"] is False
    assert projected_audit(value, rows)["relative_projected_variance_error"] < 1e-12


def test_sampler_matches_direct_seeded_target_and_is_input_only():
    mean = np.array([.7, -2.1]); value = np.array([[4, .8], [.8, .25]])
    expected = mean + np.random.default_rng(71).standard_normal((500, 2)) @ np.linalg.cholesky(value).T
    sampler = GaussianSampler(); result = sampler(mean, value, 500, 71)
    np.testing.assert_allclose(result, expected, rtol=1e-12, atol=1e-12)
    np.testing.assert_array_equal(result, GaussianSampler()(mean, value, 500, 71))
    assert not np.array_equal(result, GaussianSampler()(mean, value, 500, 72))
    assert mean.tolist() == [.7, -2.1] and value.tolist() == [[4, .8], [.8, .25]]
    assert sampler.audit[0]["paths"] == 500


def test_monte_carlo_covariance_and_projected_mean():
    value = np.array([[1.1, .35], [.35, .6]]); mean = np.array([2., -1.]); z = np.array([1, 2])
    sample = GaussianSampler()(mean, value, 60000, 194)
    np.testing.assert_allclose(np.cov(sample.T), value, rtol=.025, atol=.01)
    assert abs(float((sample @ z).mean()) - float(mean @ z)) < .03
    assert abs(float((sample @ z).var()) - float(z @ value @ z)) < .08


@pytest.mark.parametrize("value", [np.ones((2, 3)), np.array([]), np.diag([1, 0]),
    np.diag([1, -1]), np.array([[1, 2], [2, 1]]), np.array([[1, 0], [.1, 1]]),
    np.array([[np.nan, 0], [0, 1]]), np.array([[np.inf, 0], [0, 1]])])
def test_invalid_covariance_never_receives_jitter_or_clipping(value):
    with pytest.raises(ValueError): covariance_factor(value)


@pytest.mark.parametrize("paths", [0, -1, .5, True])
def test_sampler_rejects_bad_draw_counts(paths):
    with pytest.raises(ValueError): GaussianSampler()([0], [[1]], paths, 4)


def test_projected_legacy_error_is_exact_one_step_not_horizon_claim():
    value = np.diag([1e-9, 1e7]); rows = np.array([[1, 1e-8], [2, -1e-8]])
    audit = projected_audit(value, rows, .05)
    added = np.sqrt(np.finfo(float).eps) * np.diag(value).mean() * (rows ** 2).sum(axis=1)
    reference = np.einsum("ij,jk,ik->i", rows, value, rows)
    assert audit["median_legacy_added_over_total_one_step_variance"] == pytest.approx(np.median(added / (reference + .05)))
    assert audit["covariance_inflation"] == 0


def test_average_conditional_quantiles_are_not_mixture_quantiles():
    from scipy.special import ndtr, ndtri
    from scipy.optimize import brentq
    conditional_mean = ndtri(.9)
    mixture = brentq(lambda x: .5 * ndtr(x + 4) + .5 * ndtr(x - 4) - .9, -12, 12)
    assert mixture > conditional_mean + 3


def test_manifest_is_exact_complete_surface():
    RUN.validate_jobs(jobs())
    for bad in (jobs()[:-1], jobs() + [jobs()[0]], [dict(j, split=1) for j in jobs()]):
        with pytest.raises(ValueError): RUN.validate_jobs(bad)


@pytest.mark.parametrize("field,value", [("posterior_paths", 250), ("sampler", "jitter"),
    ("official_test_opened", True), ("official_validation_opened", True), ("fitting_authorized", True)])
def test_manifest_forbids_scope_and_algorithm_drift(field, value):
    current = jobs(); current[0][field] = value
    with pytest.raises(ValueError): RUN.validate_jobs(current)


def test_frozen_tau0_cannot_drift_across_splits():
    current = jobs(); current[0]["tau0"] *= 2
    with pytest.raises(ValueError): RUN.validate_jobs(current)


def test_protocol_firewall():
    value = RUN.read(RUN.PROTOCOL); RUN.protocol_valid(value)
    for field in ("fitting_authorized", "official_test_authorized", "model_selection_rule_changed"):
        altered = dict(value, **{field: True})
        with pytest.raises(ValueError): RUN.protocol_valid(altered)


def test_namespace_rejected_before_loading_frozen_code(tmp_path):
    args = SimpleNamespace(parent_campaign=tmp_path, parent_prep=tmp_path, output=tmp_path, prep=tmp_path)
    with pytest.raises(ValueError, match="namespace"): RUN.owner(args)


def test_immutable_metadata_never_overwrites(tmp_path):
    path = tmp_path / "contract.json"; RUN.immutable(path, {"a": 1}); before = path.read_bytes()
    RUN.immutable(path, {"a": 1})
    with pytest.raises(RuntimeError): RUN.immutable(path, {"a": 2})
    assert before == path.read_bytes()


def make_cell(path, job, smoke=False):
    path.mkdir()
    value = dict(job, status="R124_SMOKE_COMPLETE" if smoke else "R124_FORECAST_CELL_COMPLETE",
        model_refits=0, input_sha256={}, horizon_steps=96, step_minutes=15,
        scored_origins=2 if smoke else {1:125, 2:135, 3:174}[job["split"]],
        units="outer_fold1_training_scaled_price", fit_labels=[], source={"head": "frozen"}, sampler_audit=[{}] * 8)
    RUN.write(path / "terminal.json", value)
    for name in ("predictions.npz", "metrics.json", "forecast_contract.json"):
        (path / name).write_bytes(b"test fixture")
    RUN.write(path / "completed_evidence.json", {"artifact_sha256":
        {name: digest(path / name) for name in ("predictions.npz", "metrics.json", "forecast_contract.json", "terminal.json")}})
    return dict(job, input_sha256={}, fit_labels=[])


def test_completed_cell_reuses_hash_verified_output_and_preserves_partial(tmp_path):
    job = make_cell(tmp_path / "cell", jobs()[0]); before = (tmp_path / "cell/terminal.json").read_bytes()
    assert RUN.verified_cell(tmp_path / "cell", job, digest)["scored_origins"] == 125
    assert before == (tmp_path / "cell/terminal.json").read_bytes()
    (tmp_path / "partial").mkdir()
    with pytest.raises(RuntimeError, match="partial"): RUN.verified_cell(tmp_path / "partial", job, digest)
    RUN.write(tmp_path / "cell/terminal.json", {"tampered": True})
    with pytest.raises(RuntimeError, match="hash"): RUN.verified_cell(tmp_path / "cell", job, digest)


def test_smoke_cannot_substitute_for_full_panel(tmp_path):
    job = make_cell(tmp_path / "smoke", jobs()[0], smoke=True)
    assert RUN.verified_cell(tmp_path / "smoke", job, digest, smoke=True)["scored_origins"] == 2
    with pytest.raises(RuntimeError): RUN.verified_cell(tmp_path / "smoke", job, digest)


def test_controller_requires_matching_smoke_source(tmp_path):
    current = jobs(); job = next(j for j in current if j["candidate_id"] == "r123_3e15bdc342f556c1" and j["split"] == 3)
    args = SimpleNamespace(output=tmp_path); m = SimpleNamespace(REC=SimpleNamespace(digest=digest))
    with pytest.raises(RuntimeError, match="smoke"): RUN.smoke_valid(args, m, current, {"source": {"head": "frozen"}})
    (tmp_path / "smoke").mkdir(); replacement = make_cell(tmp_path / "smoke" / job["job_id"], job, smoke=True)
    current[current.index(job)] = replacement
    RUN.smoke_valid(args, m, current, {"source": {"head": "frozen"}})
    with pytest.raises(RuntimeError): RUN.smoke_valid(args, m, current, {"source": {"head": "different"}})


def test_release_receipt_matches_commit_and_all_suites(tmp_path):
    path = tmp_path / "release.json"
    evidence = tmp_path / "log"; evidence.write_text("all passed")
    value = dict(source_head="one", failures=0, errors=0, python_tests=400, r_suites=4, r124_tests_included=True,
        outcomes=[dict(exit_code=0, command=["application/tests/test_pricefm_stage_r124_covariance_replay.py"])] * 5,
        evidence_sha256={str(evidence): digest(evidence)})
    RUN.write(path, value); RUN.release_valid(path, {"head": "one"})
    for key, change in [("source_head", "two"), ("failures", 1), ("errors", 1),
                        ("python_tests", 356), ("r_suites", 3), ("r124_tests_included", False)]:
        RUN.write(path, dict(value, **{key: change}))
        with pytest.raises(RuntimeError): RUN.release_valid(path, {"head": "one"})
    RUN.write(path, value); evidence.write_text("tampered")
    with pytest.raises(RuntimeError, match="evidence changed"): RUN.release_valid(path, {"head": "one"})


@pytest.mark.parametrize("ceiling", [1, 2, 3, 9])
def test_scheduler_honors_budget_and_distinct_physical_cores(ceiling):
    physical = {cpu: cpu % 10 for cpu in range(20)}; busy = {core: 0 for core in range(10)}
    selected = RUN.choose_replay_cpus({10}, set(range(20)), physical, busy, {1}, ceiling)
    assert len(selected) == ceiling and 10 in selected
    assert len({physical[c] for c in selected}) == ceiling
    assert 1 not in {physical[c] for c in selected}


def test_scheduler_excludes_busy_cores_and_refuses_active_conflict():
    with pytest.raises(RuntimeError): RUN.choose_replay_cpus([], {0}, {0: 0}, {0: 90}, set(), 1)
    with pytest.raises(RuntimeError): RUN.choose_replay_cpus([0], {0}, {0: 0}, {0: 0}, {0}, 1)
    with pytest.raises(RuntimeError): RUN.choose_replay_cpus([0, 1], {0, 1}, {0: 0, 1: 0}, {0: 0}, set(), 2)


def test_orphan_worker_blocks_duplicate_launch(tmp_path, monkeypatch):
    import pricefm_r123_dependency_queue as Q
    (tmp_path / "78").mkdir()
    record = dict(pid=78, start_ticks=1, state="R", argv=["python", RUN.__file__, "--mode", "cell"])
    monkeypatch.setattr(Q, "process_identity", lambda pid: record)
    monkeypatch.setattr(RUN, "Path", lambda p: tmp_path if p == "/proc" else Path(p))
    with pytest.raises(RuntimeError, match="unrecorded"): RUN.assert_no_orphan_workers([])
    RUN.assert_no_orphan_workers([record])


def tiny_arrays():
    rng = np.random.default_rng(3); n = 2
    window = dict(X_lag=rng.normal(size=(n, ENGINE.SOURCE_WINDOW, 4)),
        X_lead=rng.normal(size=(n, 96, 3)), Y=rng.normal(size=(n, 96)), anchors=np.array(["a", "b"]),
        lag_cols=["BG-price", "BG-load", "BG-solar", "BG-wind"],
        lead_cols=["BG-load", "BG-solar", "BG-wind"], path="/BG", sha256="test",
        manifest_path="/BG.json", manifest_sha256="test")
    spec = ENGINE.normalize_spec(dict(region="BG", feature_policy="target_only", calendar="none",
        readout="pure_all_layers", m_y=3, m_x=2, units=[4, 3], alpha=.5, rho=.8,
        input_scale=.15, input_fan_in=2, recurrent_sparsity=.5, seed=17))
    return ENGINE.explicit_arrays({"BG": window}, spec), spec


def test_forecast_future_truth_is_not_recursive_input_and_patch_is_reversible(monkeypatch):
    arrays, spec = tiny_arrays(); p = 8
    mean = np.zeros(p); mean[0] = .1; covariance = np.eye(p) * .001
    normal = dict(beta_mean=mean, beta_cov=covariance, omega_shape=5., omega_rate=.5)
    quantiles = {float(q): dict(beta_mean=mean + q / 10, beta_cov=covariance) for q in ENGINE.QUANTILES}
    before = {q: f["beta_cov"].copy() for q, f in quantiles.items()}
    original = ENGINE._draw_gaussian; monkeypatch.setattr(ENGINE, "_draw_gaussian", GaussianSampler())
    first = ENGINE.recursive_quantile_forecast(arrays, spec, normal, quantiles, 10, 4)
    from dataclasses import replace
    changed = replace(arrays, response=arrays.response + 1e6)
    second = ENGINE.recursive_quantile_forecast(changed, spec, normal, quantiles, 10, 4)
    for name in RUN.OPERATORS: np.testing.assert_array_equal(first[name], second[name])
    assert not np.array_equal(first["truth"], second["truth"])
    for q in quantiles: np.testing.assert_array_equal(before[q], quantiles[q]["beta_cov"])
    monkeypatch.undo(); assert ENGINE._draw_gaussian is original


def test_own_entrypoint_contains_no_fitting_or_publication_calls():
    import ast
    tree = ast.parse(Path(RUN.__file__).read_text())
    calls = {node.func.attr for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)}
    assert not calls & {"_run_al", "_run_rhs", "_al_ladder", "_command", "_write_design", "kill", "killpg"}
    assert "_selection_arrays" in calls


def test_report_has_raw_elbo_and_scientific_boundaries(tmp_path):
    from pricefm_r124_report import report
    current = jobs(); rows = []; comparisons = []; labels = []
    for job in current:
        output = tmp_path / job["job_id"]; output.mkdir(); job["output_dir"] = str(output)
        job["quantile_dirs"] = {}
        for q in ENGINE.QUANTILES:
            fit = output / f"q{q}"; fit.mkdir()
            pd.DataFrame({"iter": [1, 2, 3], "elbo": [-100, -80, -79]}).to_csv(fit / "vb_trace.csv", index=False)
            RUN.write(fit / "terminal.json", {"formal_converged": False})
            job["quantile_dirs"][str(q)] = str(fit)
            labels.append(dict(formal_converged=False))
        np.savez_compressed(output / "predictions.npz", truth=np.zeros((3, 96)), origin_utc=np.array(["a", "b", "c"]),
            **{name: np.ones((3, 96, 7)) for name in RUN.OPERATORS})
        for name in RUN.OPERATORS: rows.append(dict(candidate_id=job["candidate_id"], split=job["split"], operator=name, AQL=.1))
        comparisons.append(dict(candidate_id=job["candidate_id"], split=job["split"], legacy_AQL=.2, AQL=.1, AQL_change_percent=-50))
    ranking = pd.DataFrame([dict(candidate_id=cid, mean_AQL=.1, mean_late_AQL=.1, mean_coverage=.6, mean_crossing=.01)
                           for cid in sorted({j["candidate_id"] for j in current})])
    report(tmp_path, current, pd.DataFrame(rows), pd.DataFrame(comparisons), ranking, pd.DataFrame(labels))
    assert (tmp_path / "replay_diagnostics.pdf").read_bytes().startswith(b"%PDF")
    text = (tmp_path / "replay_report.md").read_text()
    for required in ("not EUR/MWh", "iteration-capped", "not a marginal-mixture quantile", "NOT_READY_FOR_INTEGRATION"):
        assert required in text
