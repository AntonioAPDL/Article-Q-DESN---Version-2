"""Focused tests for the read-only R94 exAL initialization repair workflow."""

from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import pandas as pd
import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_atom(root: Path, tau: float, family: str) -> None:
    atom = root / "atoms" / f"tau={tau:.2f}".replace(".", "p") / family
    atom.mkdir(parents=True)
    checks = {"finite_core": True}
    status = "completed"
    passed = True
    if family == "exal":
        checks.update(
            trace_complete=True,
            trace_finite=True,
            structured_updates=True,
            sigma_below_100=True,
            gamma_bounded=True,
            beta_l2_ratio_below_10=True,
            first_state_delta_below_100=False,
            tail_state_sigma_delta_below_2=True,
        )
        status = "completed_numerically_ineligible"
        passed = False
    write_json(
        atom / "terminal.json",
        {
            "family": family,
            "tau": tau,
            "status": status,
            "numerical_gate_passed": passed,
            "numerical_checks": checks,
            "formal_converged": family == "al",
            "structured_updates": 60 if family == "exal" else 0,
        },
    )
    pd.DataFrame([{"iter": 60, "train_seconds": 1.2}]).to_csv(atom / "method_summary.csv", index=False)
    pd.DataFrame(
        [
            {
                "init_beta_l2": 20,
                "beta_l2": 21,
                "sigma": 0.8,
                "gamma": 0.2 if family == "exal" else 0,
            }
        ]
    ).to_csv(atom / "parameter_summary.csv", index=False)
    pd.DataFrame(
        {"beta_mean": [1.0, 2.0], "beta_cov_diag": [0.1, 0.2]}
    ).to_csv(atom / "beta_summary.csv", index=False)
    if family == "exal":
        pd.DataFrame(
            {
                "sigma": [0.8] * 40,
                "gamma": [0.2] * 40,
                "delta_state": [200.0] + [0.01] * 39,
                "delta_sigma": [0.1] + [0.001] * 39,
                "delta_gamma": [0.1] + [0.001] * 39,
                "delta_s": [0.1] + [0.001] * 39,
            }
        ).to_csv(atom / "vb_trace.csv", index=False)


def test_r94_audit_rejects_absolute_first_delta_as_universal_gate(tmp_path):
    module = load("297_audit_pricefm_stage_r94_exal_initialization.py")
    model = tmp_path / "r93"
    for tau in module.EXPECTED_QUANTILES:
        make_atom(model, tau, "al")
        make_atom(model, tau, "exal")
    history = tmp_path / "r87"
    for index, first in enumerate((7.0, 197.0, 1075.0)):
        path = history / f"case{index}" / "components" / "tau=0p25" / "exal"
        path.mkdir(parents=True)
        pd.DataFrame({"delta_state": [first, 0.01]}).to_csv(path / "vb_trace.csv", index=False)
    output = tmp_path / "audit"
    summary = module.run(
        SimpleNamespace(
            r93_model_dir=model,
            r87_run_dir=history,
            output_dir=output,
            require_complete=True,
            force=False,
        )
    )
    assert summary["r93_complete"] is True
    assert summary["repair_preparation_authorized"] is True
    assert summary["production_refit_preparation_authorized"] is True
    assert summary["r93_exal_legacy_gate_passed"] == 0
    assert summary["r93_exal_historical_proxy_trajectory_gate_passed"] == 7
    contract = json.loads((output / "pricefm_stage_r94_repair_contract.json").read_text())
    assert contract["eligibility_gate"]["first_state_delta_below_100"] == "diagnostic_only"
    assert contract["eligibility_gate"]["tail_to_first_state_ratio"] == "diagnostic_only"
    assert contract["reuse_without_refit"] == ["ridge", "normal_RHS", "DESN_features", "seven_AL_atoms"]
    assert not list(output.rglob("*.yaml"))


def minimal_runtime_source(tmp_path: Path) -> Path:
    source = tmp_path / "source"
    (source / "R").mkdir(parents=True)
    (source / "DESCRIPTION").write_text(
        "Version: 1.1.1.9004\n"
        "Config/PriceFM/repair: scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init\n"
    )
    (source / "R/exalStaticLDVB.R").write_text(
        '''  m_beta  <- if (is.null(init$beta)) rep(0, p) else as.numeric(init$beta)
  V_beta  <- V0
  sigma0  <- ld_setup$sigma0
  gamma0  <- ld_setup$gamma0
  beta_state <- beta_prior_obj$init_vb()
  initial_xis <- xis
  elbo_trace <- numeric(0)
  delta_beta <- numeric(0)
  delta_sigma <- numeric(0)
    d_beta <- max(abs(m_beta_new - prev_m_beta))
    d_sigma <- abs(sigma_cur - sigma_prev)
    delta_beta <- c(delta_beta, d_beta)
    delta_sigma <- c(delta_sigma, d_sigma)
      sigmagam_initial_xi = initial_xis,
      sigmagam_required_postwarmup_updates
          delta_state = if (length(delta_beta)) utils::tail(delta_beta, 1L) else NA_real_,
          delta_sigma
        state = delta_beta,
        sigma = delta_sigma,
'''
    )
    return source


def test_r94_runtime_patch_is_coherent_and_single_application(tmp_path):
    module = load("298_materialize_pricefm_stage_r94_exal_runtime.py")
    source = minimal_runtime_source(tmp_path)
    module.patch_source(source)
    text = (source / "R/exalStaticLDVB.R").read_text()
    assert 'warm_start_mode, "al_qbeta_rhs_latent_first"' in text
    assert "beta_covariance_source <- \"al_beta_cov_diag\"" in text
    assert "beta_prior_obj$update_vb" in text
    assert "beta_state$iter <- 0L" in text
    assert "latent_first_initialized <- TRUE" in text
    assert "delta_prediction_scaled" in text
    assert "delta_state_relative" in text
    description = (source / "DESCRIPTION").read_text()
    assert f"Version: {module.VERSION}" in description
    assert f"Config/PriceFM/repair: {module.REPAIR}" in description
    with pytest.raises(RuntimeError, match="exactly one R94 repair anchor"):
        module.patch_source(source)


def make_prep_fixture(tmp_path: Path):
    adapter_scripts = []
    for index in range(3):
        path = tmp_path / f"adapter_{index}.R"
        path.write_text(f"# adapter {index}\n")
        adapter_scripts.append({"path": str(path), "sha256": sha256(path)})
    task = {
        "stage": "R93",
        "selection_split": "val",
        "quantiles": [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90],
        "adapter_dir": str(tmp_path / "adapter"),
        "semantic_contract_sha256": "semantic",
        "semantic_contract": {
            "region": "SE_2", "fold": 1, "seed": 94,
            "feature_policy": "graph_summary_mean", "depth": 2,
            "units": "[120,64]", "lag_window": 240, "alpha": 0.5,
            "rho": 0.95, "input_scale": 0.15, "state_output": "final_layer",
            "tau0": 0.01,
        },
        "qdesn_vb": {
            "tol": 1e-4, "n_samp": 200, "n_samp_xi": 200,
            "structured_sigmagam": {
                "structured_grid_size": 151, "structured_span_sd": 6,
                "min_postwarmup_updates": 35,
                "postwarmup_damping": 0.2, "postwarmup_damping_iters": 30,
            },
        },
        "rhs": {
            "tau0": 0.01, "init_tau": 1, "freeze_tau_iters": 50,
            "freeze_tau_warmup_iters": 50,
        },
        "adapter_scripts": adapter_scripts,
        **{name: False for name in (
            "test_access_authorized", "registry_mutation_authorized",
            "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
        )},
    }
    task_path = tmp_path / "r93_task.json"
    write_json(task_path, task)
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    for name in (
        "X_train.csv", "y_train.csv", "rows_train.csv", "X_val.csv", "y_val.csv",
        "rows_val.csv", "adapter_manifest.json", "feature_manifest.json",
    ):
        (adapter / name).write_text("1\n")
    (adapter / "feature_map_matrix.npz").write_bytes(b"fixture")
    model = tmp_path / "model"
    for tau in task["quantiles"]:
        atom = model / "atoms" / f"tau={tau:.2f}".replace(".", "p") / "al"
        atom.mkdir(parents=True)
        pd.DataFrame({"beta_mean": [1.0, 2.0], "beta_cov_diag": [0.1, 0.2]}).to_csv(atom / "beta_summary.csv", index=False)
        pd.DataFrame([{"sigma": 0.8}]).to_csv(atom / "parameter_summary.csv", index=False)
        pd.DataFrame([{
            "method_id": "al", "split": "val", "origin_id": 1,
            "horizon": 1, "tau": tau, "pred_scaled": 1.0,
        }]).to_csv(atom / "predictions_scaled.csv", index=False)
        write_json(atom / "terminal.json", {"status": "completed", "numerical_gate_passed": True})
    audit_path = tmp_path / "audit.json"
    write_json(audit_path, {
        "r93_complete": True, "production_refit_preparation_authorized": True,
        "test_opened": False, "test_access_authorized": False,
    })
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    runtime_manifest = tmp_path / "runtime.json"
    write_json(
        runtime_manifest,
        {
            "status": "installed_coherent_exal_initialization_runtime",
            "version": "1.1.1.9005",
            "repair": "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init-plus-coherent-al-latent-init",
            "base_tarball_sha256": "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e",
            "launch_authorized": False,
            "test_opened": False,
            "test_access_authorized": False,
        },
    )
    return task_path, model, audit_path, runtime, runtime_manifest


def test_r94_prep_materializes_only_seven_blocked_exal_tasks(tmp_path):
    module = load("300_prepare_pricefm_stage_r94_exal_refit.py")
    task, model, audit, runtime, runtime_manifest = make_prep_fixture(tmp_path)
    grid, output = tmp_path / "grid", tmp_path / "output"
    summary = module.run(
        SimpleNamespace(
            r93_task=task, r93_model_dir=model, audit_summary=audit,
            runtime=runtime, runtime_manifest=runtime_manifest,
            grid_dir=grid, run_dir=tmp_path / "runs", output_dir=output,
            adapter_dir=None, code_root=tmp_path, quarantine_root=None,
            recommended_workers=7, quarantine_existing=False, skip_git_check=True,
        )
    )
    manifest = pd.read_csv(grid / "task_manifest.csv")
    assert summary["tasks"] == 7 and summary["AL_atoms_reused"] == 7
    assert manifest.likelihood_family.eq("exal").all()
    assert manifest.rhs_tau0.eq(0.01).all()
    assert manifest.warm_start_mode.eq("al_qbeta_rhs_latent_first").all()
    assert not manifest.launch_authorized.astype(bool).any()
    assert not list(grid.rglob("*.yaml"))
    one = json.loads(Path(manifest.task_config.iloc[0]).read_text())
    assert one["max_iter"] == 200
    assert one["postwarmup_damping"] == 0.2
    assert one["postwarmup_damping_iters"] == 30
    assert one["frozen_desn"]["units"] == "[120,64]"
    assert len(one["adapter_files"]) == 9
    assert len(one["adapter_scripts"]) == 3
    assert one["test_opened"] is False
    assert one["pipeline_contract_sha256"]


def test_r94_launcher_and_runner_keep_launch_and_first_delta_gate_explicit():
    launcher = (SCRIPTS / "301_launch_pricefm_stage_r94_exal_refit.py").read_text()
    runner = (SCRIPTS / "299_run_pricefm_stage_r94_exal_component.R").read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_R94_COHERENT_EXAL_REFIT"' in launcher
    assert "args.approval_token != APPROVAL_TOKEN" in launcher
    assert '"--preflight-only"' in launcher
    assert "first_state_delta_role = \"diagnostic_only_not_an_eligibility_gate\"" in runner
    assert "tail_to_first_state_ratio_role = \"diagnostic_only_not_an_eligibility_gate\"" in runner
    assert "beta_cov_diag = beta_cov_diag_init" in runner
    assert "postwarmup_damping = as.numeric(task$postwarmup_damping)" in runner
    assert ".rds" not in runner.lower()
    assert "quarantine_path" in launcher
    assert "scheduler_state.json" in launcher
    assert "validate_git_identity" in launcher
