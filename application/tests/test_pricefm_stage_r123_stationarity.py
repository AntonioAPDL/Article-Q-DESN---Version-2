import importlib.util
import json
from pathlib import Path
import sys
import shutil
import subprocess
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application/scripts/pricefm"))
loader = importlib.util.spec_from_file_location("r123_stationarity_test",
    ROOT / "application/scripts/pricefm/437_run_pricefm_stage_r123_stationarity.py")
M = importlib.util.module_from_spec(loader); loader.loader.exec_module(M)


def test_protocol_bounds_and_scientific_isolation():
    p = M.REC.read(ROOT / "application/config/pricefm_stage_r123_stationarity_protocol_20261004.json")
    assert len(p["resume_candidate_ids"]) * 3 + len(p["rejected_candidate_ids"]) * 2 == 10
    assert p["resume_total_iteration_cap"] == p["fresh_total_iteration_cap"] == 2000
    for key, value in p.items():
        if key.endswith("authorized"): assert value is False
    assert p["maximum_workers"] == 15


def test_rejected_diagnostic_is_complete_but_not_a_selected_model(tmp_path):
    contract = tmp_path / "contract.json"; contract.write_text("{}")
    output = tmp_path / "fit"; output.mkdir()
    artifact = output / "fit.rds"; artifact.write_bytes(b"checkpoint")
    for name in ("convergence_trace.csv", "geometry.json", "summary.json"):
        (output / name).write_bytes(b"evidence")
    terminal = dict(status="R123_VARIATIONAL_CAP_DIAGNOSTIC", contract_sha256=M.REC.digest(contract),
                    test_opened=False, selection_authorized=False,
                    artifact_sha256={path.name: M.REC.digest(path) for path in output.iterdir()})
    M.REC.write(output / "terminal.json", terminal)
    assert M.valid_diagnostic(output, contract)
    artifact.write_bytes(b"changed")
    with pytest.raises(RuntimeError, match="artifact differs"): M.valid_diagnostic(output, contract)


@pytest.mark.parametrize("key,value", [("test_opened", True), ("selection_authorized", True),
    ("status", "completed_recursive_normal_fit"), ("contract_sha256", "wrong")])
def test_wrong_target_or_ambiguous_success_is_rejected(tmp_path, key, value):
    contract = tmp_path / "contract.json"; contract.write_text("{}")
    output = tmp_path / "fit"; output.mkdir()
    terminal = dict(status="R123_FULL_VARIATIONAL_CERTIFIED", contract_sha256=M.REC.digest(contract),
                    test_opened=False, selection_authorized=False, artifact_sha256={})
    terminal[key] = value; M.REC.write(output / "terminal.json", terminal)
    with pytest.raises(RuntimeError): M.valid_diagnostic(output, contract)


def test_checkpoint_not_overwritten_and_target_is_explicit(tmp_path, monkeypatch):
    parent = dict(tau0=.0002, prior_type="rhs_ns", posterior_target_sha256="stats:tau0=.0002",
                  selection_split="train_validation_only", test_access_authorized=False)
    contract = tmp_path / "parent.json"; M.REC.write(contract, parent)
    fit = tmp_path / "parent_fit"; fit.mkdir(); checkpoint = fit / "fit.rds"; checkpoint.write_bytes(b"prior-state")
    runtime = tmp_path / "runtime/R"; runtime.mkdir(parents=True)
    for name in ("qdesn_rhs_ns_prior.R", "priors_beta.R"): (runtime / name).write_text("frozen")
    row = dict(fit_id="id", candidate_id="candidate", split="1", contract_path=str(contract), output_dir=str(fit))
    args = SimpleNamespace(output_root=tmp_path / "diagnosis")
    p = {"resume_total_iteration_cap": 2000, "fresh_total_iteration_cap": 2000, "minimum_iteration": 100,
         "full_state_stability_window": 10, "rhs_state_tol": 1e-6, "covariance_tol": 1e-6,
         "objective_per_observation_tol": 1e-8, "precision_accuracy_tol": 1e-5}
    ctl = dict(normal_runtime=str(runtime.parent))
    resumed = M.diagnostic_contract(row, args, ctl, p, "resume")
    fresh = M.diagnostic_contract(row, args, ctl, p, "prior_scale")
    assert resumed["initial_fit_sha256"] == M.REC.digest(checkpoint)
    assert fresh["initial_fit_path"] is None and fresh["initial_tau"] == parent["tau0"]
    assert resumed["tau0"] == fresh["tau0"] == parent["tau0"]
    assert resumed["posterior_target_sha256"] == fresh["posterior_target_sha256"]
    assert resumed["target_contract_sha256"] == fresh["target_contract_sha256"] == M.REC.digest(contract)
    assert Path(resumed["output_dir"]) != fit
    assert checkpoint.read_bytes() == b"prior-state"


def test_missing_completion_is_not_assumed(tmp_path):
    assert M.valid_diagnostic(tmp_path / "missing", tmp_path / "missing_contract") is False


def test_real_r_entrypoint_persists_cap_and_refuses_overwrite(tmp_path):
    import numpy as np
    runtime = M.DEFAULT / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names/exdqlm"
    if not shutil.which("Rscript") or not runtime.exists(): pytest.skip("exact Normal R runtime unavailable")
    rng = np.random.default_rng(19)
    X = np.column_stack([np.ones(40), rng.normal(size=(40, 3))]); y = rng.normal(size=40)
    stats = tmp_path / "stats"; stats.mkdir()
    np.asarray(X.T @ X, dtype="<f8").tofile(stats / "XtX.bin")
    np.asarray(X.T @ y, dtype="<f8").tofile(stats / "Xty.bin")
    M.REC.write(stats / "statistics.json", dict(n=40, p=4, yty=float(y @ y), test_opened=False))
    files = {path.name: {"sha256": M.REC.digest(path)} for path in stats.iterdir()}
    M.REC.write(stats / "terminal.json", dict(status="completed_causal_sufficient_statistics", test_opened=False, files=files))
    sources = [ROOT / "application/R/pricefm_recursive_normal_fit.R",
               ROOT / "application/scripts/pricefm/436_diagnose_pricefm_stage_r123_stationarity.R",
               runtime / "R/qdesn_rhs_ns_prior.R", runtime / "R/priors_beta.R"]
    contract = dict(selection_split="train_validation_only", test_access_authorized=False, prior_type="rhs_ns",
        stats_dir=str(stats), output_dir=str(tmp_path / "diagnostic"), fit_id="isolated_test", candidate_id="test", split=1,
        helper_path=str(sources[0]), package_path=str(runtime), source_sha256={str(p): M.REC.digest(p) for p in sources},
        tau0=.05, initial_tau=1, min_iter=1, max_iter=2, initial_fit_path=None, convergence_mode="full_variational",
        target_contract_sha256="isolated_test_target", tol=1e-5, stability_window=10, predictive_tol=1e-7,
        relative_beta_tol=1e-6, sigma_relative_tol=1e-8, prior_rms_log_precision_tol=1e-6,
        rhs_state_tol=1e-6, covariance_tol=1e-6, objective_per_observation_tol=1e-8, precision_accuracy_tol=1e-5)
    path = tmp_path / "contract.json"; M.REC.write(path, contract)
    command = ["Rscript", str(sources[1]), "--contract", str(path)]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert M.valid_diagnostic(contract["output_dir"], path)
    terminal = M.REC.read(Path(contract["output_dir"]) / "terminal.json")
    assert terminal["status"] == "R123_VARIATIONAL_CAP_DIAGNOSTIC" and terminal["iterations"] == 2
    assert subprocess.run(command, capture_output=True).returncode != 0


def test_complete_diagnostic_report_and_overwrite_guard(tmp_path):
    import pandas as pd
    spec = importlib.util.spec_from_file_location("r123_report_test",
        ROOT / "application/scripts/pricefm/439_report_pricefm_stage_r123_stationarity.py")
    report = importlib.util.module_from_spec(spec); spec.loader.exec_module(report)
    manifest, rows = [], []
    for i in range(10):
        folder = tmp_path / f"fit_{i}"; folder.mkdir()
        trace = pd.DataFrame(dict(iter=range(1, 12), total_objective=range(1, 12),
            objective_delta_per_observation=[1e-9] * 11, prior_rms_log_precision_delta=[1e-7] * 11,
            rhs_max_log_rate_delta=[1e-7] * 11, beta_cov_relative_delta=[1e-7] * 11,
            sigma2_mean=[.1] * 11))
        trace.to_csv(folder / "convergence_trace.csv", index=False)
        M.REC.write(folder / "geometry.json", dict(normalized_gram_numerical_rank=4, p=4))
        M.REC.write(folder / "terminal.json", dict(artifact_sha256={p.name: M.REC.digest(p) for p in folder.iterdir()}))
        manifest.append(dict(fit_id=f"fit_{i}", output_dir=str(folder), candidate_id="fixture", split=1))
        rows.append(dict(fit_id=f"fit_{i}", initialization="resume", certified=i < 6, maximum_precision_jitter=0))
    closeout = tmp_path / "closeout"; closeout.mkdir()
    pd.DataFrame(rows).to_csv(closeout / "audit_table.csv", index=False)
    M.REC.write(closeout / "objective_check.json", dict(status="R123_STATE_OBJECTIVE_CLOSEOUT_PASS",
        audit_table_sha256=M.REC.digest(closeout / "audit_table.csv")))
    M.REC.write(tmp_path / "terminal.json", dict(status="R123_STATIONARITY_DIAGNOSIS_COMPLETE"))
    M.REC.write(tmp_path / "manifest.json", manifest)
    value = report.render(tmp_path)
    assert value["pages"] == 10 and value["certified"] == 6 and value["capped"] == 4
    assert Path(value["pdf"]).read_bytes().startswith(b"%PDF")
    with pytest.raises(RuntimeError, match="overwrite"): report.render(tmp_path)
    original = M.REC.digest(value["pdf"])
    revised = report.render(tmp_path, "stationarity_layout_v2")
    assert Path(revised["pdf"]).exists() and M.REC.digest(value["pdf"]) == original
    assert (closeout / "stationarity_layout_v2_identity.json").exists()
    with pytest.raises(RuntimeError, match="overwrite"): report.render(tmp_path, "stationarity_layout_v2")
    with pytest.raises(ValueError): report.render(tmp_path, "../outside")


def test_certified_selection_does_not_require_every_screened_candidate():
    from pricefm_r123_certified_selection import certified_groups
    cells = [dict(candidate_id=identifier, split=split, tau0=.001, AQL=score,
        late_AQL=score + .01, full_variational_certified=True, test_opened=False)
        for identifier, score in [("a", .1), ("b", .2), ("c", .3)] for split in (1, 2, 3)]
    cells.append(dict(candidate_id="d", split=1, tau0=.001, AQL=.01, late_AQL=.02,
        full_variational_certified=False, test_opened=False))
    value = certified_groups(cells, ["a", "b", "c", "d", "e"])
    assert value["status"] == "CERTIFIED_SELECTION_READY"
    assert value["tau_candidate_ids"] == value["al_candidate_ids"] == ["a", "b", "c"]
    assert value["missing_candidate_ids"] == ["e"] and len(value["excluded"]) == 1
    assert value["launch_authorized"] is False
    blocked = certified_groups(cells[:6], ["a", "b", "c"])
    assert blocked["status"] == "CERTIFIED_SELECTION_BLOCKED" and blocked["al_candidate_ids"] == []


@pytest.mark.parametrize("change", ["duplicate", "unknown", "forbidden_test", "bad_scale", "bad_split"])
def test_certified_selection_fails_closed_on_invalid_evidence(change):
    from pricefm_r123_certified_selection import certified_groups
    cell = dict(candidate_id="a", split=1, tau0=.001, AQL=.1, late_AQL=.2,
                full_variational_certified=True, test_opened=False)
    cells = [cell]
    if change == "duplicate": cells.append(dict(cell))
    elif change == "unknown": cell["candidate_id"] = "other"
    elif change == "forbidden_test": cell["test_opened"] = True
    elif change == "bad_scale": cell["tau0"] = -1
    else: cell["split"] = 4
    with pytest.raises(ValueError): certified_groups(cells, ["a"])
