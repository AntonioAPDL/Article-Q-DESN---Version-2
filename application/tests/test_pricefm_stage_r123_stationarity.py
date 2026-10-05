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
         "objective_per_observation_tol": 1e-8}
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
        rhs_state_tol=1e-6, covariance_tol=1e-6, objective_per_observation_tol=1e-8)
    path = tmp_path / "contract.json"; M.REC.write(path, contract)
    command = ["Rscript", str(sources[1]), "--contract", str(path)]
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert M.valid_diagnostic(contract["output_dir"], path)
    terminal = M.REC.read(Path(contract["output_dir"]) / "terminal.json")
    assert terminal["status"] == "R123_VARIATIONAL_CAP_DIAGNOSTIC" and terminal["iterations"] == 2
    assert subprocess.run(command, capture_output=True).returncode != 0
