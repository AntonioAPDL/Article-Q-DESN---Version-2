from __future__ import annotations

import argparse
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


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


AUDIT = load("r122_closeout_tests", "431_closeout_pricefm_stage_r122_internal.py")
PROBE = load("r122_probe_tests", "432_diagnose_pricefm_stage_r122_recursive_operators.py")


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def trace(n=40, movement=1e-6):
    return pd.DataFrame({"iter": np.arange(1, n + 1), "elbo": np.linspace(10., 10. + 1e-7, n),
                         "delta_state": movement, "delta_sigma": 1e-8, "delta_elbo": 1e-8})


@pytest.fixture
def frozen(tmp_path):
    campaign = tmp_path / "campaign"; prep = tmp_path / "prep"
    campaign.mkdir(); prep.mkdir()
    source = tmp_path / "source.R"; source.write_text("# frozen test source\n")
    pd.DataFrame([{"path": str(source), "sha256": AUDIT.sha256_file(source)}]).to_csv(prep / "source_manifest.csv", index=False)
    dump(prep / "launch_control.json", {"code_head": "frozen", "official_test_scoring_authorized": False})
    dump(prep / "evaluation_contract.json", {"selection_protocol": {"test_selection_access": False},
                                             "historical_test_status": "HISTORICALLY_OPENED_NOT_PRISTINE"})
    dump(prep / "target_contract.json", {"test_access_authorized": False})
    input_path = campaign / "processed/windows/fold_1/region=BG/train_fixture.npz"
    input_path.parent.mkdir(parents=True); input_path.write_bytes(b"frozen training input")
    inventory = prep / "reused_input_inventory.csv"
    pd.DataFrame([{"path": str(input_path.relative_to(campaign)), "sha256": AUDIT.sha256_file(input_path)}]).to_csv(inventory, index=False)
    dump(prep / "summary.json", {"source": "frozen", "continuation": {"input_inventory_sha256": AUDIT.sha256_file(inventory)}})
    cran = prep / "cran.json"; dump(cran, {"version": "1.1.1"})
    ridge = []
    for i in range(3):
        item = {"fit_id": f"ridge{i}", "fit_sha256": f"hash{i}"}; ridge.append(item)
        dump(campaign / f"ridge/fits/ridge{i}/terminal.json",
             {**item, "status": "completed_r122_ridge_cell", "test_opened": False})
    pd.DataFrame(ridge[:2]).to_csv(prep / "execution_manifest.csv", index=False)
    (campaign / "seed3").mkdir()
    pd.DataFrame(ridge[2:]).to_csv(campaign / "seed3/manifest.csv", index=False)
    cells, rhs, shortlist, specs = [], [], [], []
    flags = {key: False for key in AUDIT.FORBIDDEN}
    for ci, candidate in enumerate(("a", "b", "c")):
        shortlist.append({"candidate_id": candidate, "tau0": .00024584350531880317})
        specs.append({"candidate_id": candidate, "spec_json": "{}"})
        for split in (1, 2, 3):
            parent = campaign / f"rhs/center/fits/{candidate}{split}"; parent.mkdir(parents=True)
            dump(parent / "terminal.json", {"status": "completed_recursive_normal_fit", "test_opened": False, "converged": True})
            dump(parent / "validation_score.json", {"test_opened": False})
            np.ones(1, dtype="<f8").tofile(parent / "beta_mean.bin")
            np.ones(1, dtype="<f8").tofile(parent / "beta_cov.bin")
            rhs_contract = parent / "contract.json"; dump(rhs_contract, {"test_access_authorized": False})
            rhs.append({"fit_id": candidate + str(split), "output_dir": str(parent), "contract_path": str(rhs_contract)})
            ladder = campaign / f"al_internal/{candidate}/split={split}"
            design = ladder / "design"; design.mkdir(parents=True)
            np.ones(40, dtype="<f8").tofile(design / "X.bin")
            np.ones(40, dtype="<f8").tofile(design / "y.bin")
            dump(design / "design.json", {"test_opened": False, "selection_boundary": "fold1_internal_training_only"})
            dump(design / "terminal.json", {"X_sha256": AUDIT.sha256_file(design / "X.bin"),
                                            "y_sha256": AUDIT.sha256_file(design / "y.bin")})
            accepted = []
            for tau in AUDIT.QUANTILES:
                target = AUDIT.sha256_file(design / "terminal.json") + f":tau={tau:.2f}:tau0={shortlist[-1]['tau0']:.17g}"
                output = ladder / f"quantiles/al/tau={tau:.2f}"; output.mkdir(parents=True)
                contract = {"candidate_id": candidate, "split": split, "tau": tau, "tau0": shortlist[-1]["tau0"],
                            "parent_dir": str(parent), "parent_terminal_sha256": AUDIT.sha256_file(parent / "terminal.json"),
                            "design_dir": str(design), "design_terminal_sha256": AUDIT.sha256_file(design / "terminal.json"),
                            "posterior_target_sha256": target, "max_iter": 40,
                            "cran_manifest": str(cran), "cran_manifest_sha256": AUDIT.sha256_file(cran),
                            "cran_adapter": str(source), "cran_adapter_sha256": AUDIT.sha256_file(source),
                            **{key: False for key in ("test_access_authorized", "article_mutation_authorized", "registry_mutation_authorized",
                                                     "joint_model_authorized", "mcmc_authorized", "exal_authorized")}}
                dump(ladder / f"contracts/final/tau={tau:.2f}.json", contract)
                np.ones(1, dtype="<f8").tofile(output / "beta_mean.bin")
                np.ones(1, dtype="<f8").tofile(output / "beta_cov.bin")
                frame = trace(); frame.to_csv(output / "vb_trace.csv", index=False)
                gate = AUDIT.trace_gate(frame, np.ones(1), 1.)
                dump(output / "diagnostics.json", {**gate, "formal_converged": False})
                dump(output / "parameter_summary.json", {"sigma": 1.})
                dump(output / "terminal.json", {**flags, "tau": tau, "tau0": shortlist[-1]["tau0"], "p": 1,
                                                "iterations": 40, "sigma": 1., "formal_converged": False, "train_seconds": .1,
                                                "initialization_only": True, "prior_center_from_initializer": False,
                                                "initializer_changes_prior": False, "family": "al", "package_version": "1.1.1",
                                                "package_repository": "CRAN", "posterior_target_sha256": target})
                accepted.append({"tau": tau, "accepted": True})
            cell = {"candidate_id": candidate, "split": split, "tau0": shortlist[-1]["tau0"], "eligible": True,
                    "test_opened": False, "score_scope": "fold1_training_internal_validation_only", "AQL": 1 + ci + split / 10,
                    "late_AQL": 2 + ci, "interval_80_coverage": .5, "interval_80_width": 1., "crossing_rate": 0.}
            cells.append(cell); dump(ladder / "metrics.json", {**cell, "accepted_quantiles": accepted})
    (campaign / "rhs/closeout").mkdir(parents=True)
    pd.DataFrame(rhs).to_csv(campaign / "rhs/manifest.csv", index=False)
    pd.DataFrame(shortlist).to_csv(campaign / "rhs/closeout/al_shortlist.csv", index=False)
    pd.DataFrame(specs).to_csv(prep / "candidate_manifest.csv", index=False)
    (campaign / "al_internal/closeout").mkdir()
    cells_frame = pd.DataFrame(cells); ranked = AUDIT.reconstruct_ranking(cells_frame)
    cells_frame.to_csv(campaign / "al_internal/closeout/cell_metrics.csv", index=False)
    ranked.to_csv(campaign / "al_internal/closeout/ranking.csv", index=False)
    choice = {"candidate_id": "a", "internal_mean_AQL": float(ranked.iloc[0].mean_AQL)}
    dump(campaign / "frozen_internal_choice.json", choice)
    dump(campaign / "terminal.json", {**flags, "status": "R122_INTERNAL_SPECIFICATION_FROZEN_TEST_BLOCKED", "frozen_choice": choice})
    protocol = {"campaign_tag": campaign.name, "campaign_terminal_sha256": AUDIT.sha256_file(campaign / "terminal.json"),
                "frozen_choice_sha256": AUDIT.sha256_file(campaign / "frozen_internal_choice.json"),
                "preparation_sha256": AUDIT.sha256_file(prep / "summary.json"), "executed_head": "frozen",
                "expected_counts": {"broad": 2, "third_seed": 1, "normal_rhs": 9},
                "selection_scope": "fold1_training_internal_validation_only", "metric_units": "processed"}
    return campaign, prep, protocol


def test_complete_campaign_accepts_caps_without_claiming_formal_convergence(frozen):
    result = AUDIT.audit_campaign(*frozen)
    assert len(result["atoms"]) == 63
    assert result["atoms"].external_gate_passed.all()
    assert result["atoms"].at_cap.all()
    assert not result["atoms"].formal_converged.any()
    AUDIT.verify_ledger(result["ledger"])


@pytest.mark.parametrize("change", ["target", "prior", "test", "missing", "parent", "design", "source", "rank", "trace"])
def test_corrupt_or_target_changing_evidence_fails_closed(frozen, change):
    campaign, prep, protocol = frozen
    ladder = campaign / "al_internal/a/split=1"
    terminal = ladder / "quantiles/al/tau=0.50/terminal.json"
    if change in ("target", "prior", "test"):
        value = json.loads(terminal.read_text())
        value[{"target": "posterior_target_sha256", "prior": "initializer_changes_prior", "test": "test_opened"}[change]] = (
            "wrong" if change == "target" else True)
        dump(terminal, value)
    elif change == "missing": terminal.unlink()
    elif change == "parent": dump(campaign / "rhs/center/fits/a1/terminal.json", {"changed": True})
    elif change == "design": (ladder / "design/X.bin").write_bytes(b"bad design")
    elif change == "source": (prep.parent / "source.R").write_text("changed")
    elif change == "rank":
        file = campaign / "al_internal/closeout/ranking.csv"; frame = pd.read_csv(file); frame.loc[0, "mean_AQL"] = 99
        frame.to_csv(file, index=False)
    elif change == "trace": trace(movement=1.).to_csv(terminal.parent / "vb_trace.csv", index=False)
    with pytest.raises((RuntimeError, FileNotFoundError, KeyError)):
        AUDIT.audit_campaign(campaign, prep, protocol)


def test_ledger_detects_post_audit_source_drift(frozen):
    result = AUDIT.audit_campaign(*frozen)
    source = frozen[1].parent / "source.R"; source.write_text("changed")
    with pytest.raises(RuntimeError, match="hash mismatch"):
        AUDIT.verify_ledger(result["ledger"])


def test_closeout_output_is_separate_immutable_and_idempotent(frozen, tmp_path, monkeypatch):
    campaign, prep, protocol = frozen
    protocol_file = tmp_path / "protocol.json"; dump(protocol_file, protocol)
    def render(path, audit): path.write_bytes(b"test pdf")
    monkeypatch.setattr(AUDIT, "render_pdf", render)
    args = argparse.Namespace(campaign=campaign, prep=prep, protocol=protocol_file, output=tmp_path / "closeout")
    first = AUDIT.run(args); second = AUDIT.run(args)
    assert first == second and first["source_preservation_verified"]
    assert first["counts"]["formal_converged_al"] == 0
    assert first["integration_status"] == "NOT_READY_FOR_INTEGRATION"
    (args.output / "internal_ranking.csv").write_text("corrupt")
    with pytest.raises(RuntimeError, match="hash mismatch"): AUDIT.run(args)
    with pytest.raises(RuntimeError, match="separate"):
        AUDIT.validate_output_root(campaign / "outputs", campaign, prep)


@pytest.mark.parametrize("movement,expected", [(1e-6, True), (.02, False)])
def test_gate_preserves_absolute_movement_bound(movement, expected):
    result = AUDIT.trace_gate(trace(movement=movement), np.array([1e9]), 1.)
    assert result["external_gate_passed"] is expected


def test_short_or_nonfinite_trace_is_rejected():
    with pytest.raises(RuntimeError): AUDIT.trace_gate(trace(n=20), np.ones(1), 1.)
    frame = trace(); frame.loc[39, "elbo"] = np.nan
    with pytest.raises(RuntimeError): AUDIT.trace_gate(frame, np.ones(1), 1.)


def test_diagnostic_origins_are_bounded_and_score_independent():
    result = PROBE.diagnostic_indices(np.arange(506, 631), 12)
    assert len(result) == 12 and result[0] == 506 and result[-1] == 630
    assert len(np.unique(result)) == 12
    with pytest.raises(RuntimeError): PROBE.diagnostic_indices(np.arange(125), 17)
    with pytest.raises(RuntimeError): PROBE.diagnostic_indices(np.array([3, 2, 1]), 2)


def test_averaged_conditional_quantiles_are_not_mixture_quantiles():
    example = PROBE.mixture_counterexample()
    assert example["nominal_quantile"] == .9
    assert example["mixture_cdf_at_average_conditional_quantile"] == pytest.approx(.5, abs=1e-4)


def test_linear_path_mean_equals_mean_feature_for_fixed_coefficients():
    rng = np.random.default_rng(7)
    features = rng.normal(size=(500, 10)); beta = rng.normal(size=10)
    assert np.mean(features @ beta) == pytest.approx(np.mean(features, axis=0) @ beta, abs=1e-14)


def test_operators_use_identical_truth_units_and_horizon_blocks():
    truth = np.zeros((2, 96))
    prediction = np.broadcast_to(np.array([-3., -2., -1., 0., 1., 2., 3.]), (2, 96, 7)).copy()
    values = {key: prediction.copy() for key in ("mean_feature", "path_specific", "normal_driver")}
    metrics, horizons = PROBE.score_operators(truth, values)
    assert len(metrics) == 3 and len(horizons) == 9
    assert {row["interval_80_coverage"] for row in metrics} == {1.}
    assert {row["interval_80_width"] for row in metrics} == {6.}
    assert {row["horizon_block"] for row in horizons} == {"first_6_hours", "middle_12_hours", "last_6_hours"}
    values["normal_driver"] = prediction[:, :95]
    with pytest.raises(RuntimeError): PROBE.score_operators(truth, values)


def test_production_protocol_has_no_authorized_fitting_or_publication():
    protocol = json.loads(AUDIT.DEFAULT_PROTOCOL.read_text())
    assert protocol["posterior_paths"] == 500 and protocol["diagnostic_origins_per_split"] == 12
    assert all(value is False for key, value in protocol.items() if key.endswith("_authorized"))
    assert protocol["metric_units"].endswith("not_EUR_per_MWh")
    source = (SCRIPTS / "432_diagnose_pricefm_stage_r122_recursive_operators.py").read_text()
    assert "RT.recursive_quantile_forecast" in source
    assert "RUNNER._selection_arrays" in source
    assert "Rscript" not in source and "rhs-score" not in source


def test_no_refit_case_saves_matched_predictions_and_resumes_without_reforecasting(frozen, tmp_path, monkeypatch):
    campaign, prep, _ = frozen
    arrays = SimpleNamespace(response=np.zeros((940, 96)), anchors=np.asarray([f"origin-{i}" for i in range(940)]),
                             source_manifest=())
    spec = {"region": "BG", "feature_policy": "target_only", "calendar": "none", "readout": "pure_all_layers",
            "depth": 1, "units": [16], "m_y": 96, "m_x": 0, "alpha": .1, "rho": .7, "input_scale": .05,
            "input_fan_in": 8, "recurrent_sparsity": .05, "source_window": 3120, "warmup_steps": 240}
    monkeypatch.setattr(PROBE.os, "sched_setaffinity", lambda *args: None)
    monkeypatch.setattr(PROBE.os, "sched_getaffinity", lambda *args: {2})
    monkeypatch.setattr(PROBE.RUNNER, "_selection_arrays", lambda *args: arrays)
    monkeypatch.setattr(PROBE.RT, "standardize_from_training_origins", lambda *args: (arrays, {"price_scale": 2., "price_mean": 10.}))
    monkeypatch.setattr(PROBE.RT, "subset_arrays", lambda a, idx: SimpleNamespace(response=a.response[idx]))
    monkeypatch.setattr(PROBE.RT, "load_normal_fit", lambda *args: {})
    monkeypatch.setattr(PROBE.RT, "load_quantile_fit", lambda *args: {})
    calls = []
    def forecast(a, spec, normal, qfits, paths, seed):
        calls.append((paths, seed))
        value = np.broadcast_to(np.arange(-3, 4), (*a.response.shape, 7)).copy()
        return {"truth": a.response, **{k: value for k in ("mean_feature", "path_specific", "normal_driver")}}
    monkeypatch.setattr(PROBE.RT, "recursive_quantile_forecast", forecast)
    monkeypatch.setattr(PROBE.RT, "recursive_normal_score", lambda *args, **kwargs: {
        "AQL": 1., "late_AQL": 1., "median_MAE": 1., "interval_80_width": 1., "interval_80_coverage": .8})
    job = {"candidate_id": "a", "split": 1, "spec": spec, "campaign": str(campaign), "prep": str(prep),
           "output": str(tmp_path / "diagnostic/case"), "cpu": 2, "origin_count": 12, "posterior_paths": 500}
    before = AUDIT.audit_campaign(*frozen)["ledger"]
    result = PROBE.case_job(job)
    assert result == PROBE.case_job(job) and len(calls) == 1
    assert result["cpu_affinity"] == [2] and result["model_fitted"] is False
    assert result["origin_count"] == 12 and result["selected_origin_indices"][0] == 506
    with np.load(Path(job["output"]) / "matched_predictions.npz") as saved:
        assert saved["truth"].shape == (12, 96)
        assert np.all(saved["truth"] == 10) and np.all(saved["mean_feature"][:, :, 0] == 4)
        assert np.all(saved["mean_feature"][:, :, -1] == 16)
    AUDIT.verify_ledger(before)
    (Path(job["output"]) / "matched_predictions.npz").write_bytes(b"changed")
    with pytest.raises(RuntimeError, match="hash mismatch"): PROBE.case_job(job)


def test_preflight_requires_explicit_single_thread_caps(tmp_path, monkeypatch):
    for key in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        monkeypatch.setenv(key, "1")
    monkeypatch.setenv("OMP_NUM_THREADS", "2")
    with pytest.raises(RuntimeError, match="thread cap"):
        PROBE.preflight([2], tmp_path, {"maximum_workers": 9})
