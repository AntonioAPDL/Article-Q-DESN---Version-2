import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(module, path):
    return module.sha256(Path(path))


def prep_fixture(tmp_path, module, with_test=False):
    source_root = tmp_path / "r65"
    adapter = source_root / "case/adapter"
    model = source_root / "case/model"
    adapter.mkdir(parents=True)
    model.mkdir(parents=True)
    for name in module.ADAPTER_FILES:
        (adapter / name).write_text("fixture\n")
    if with_test:
        (adapter / "X_test.csv").write_text("forbidden\n")
    data = source_root / "data.yaml"
    data.write_text("pricefm:\n  processed_dir: /tmp/processed\n")
    config = source_root / "case.yaml"
    smoke = {
        "data_config": str(data),
        "python_bin": "/tmp/python",
        "package_path": "/tmp/r65-package",
        "region": "AT",
        "fold": 1,
        "splits": ["train", "val"],
        "horizons": [1, 2],
        "quantiles": list(TAUS),
        "feature_policy": "target_only",
        "adapter": {"output_dir": str(adapter), "feature_map": "window_reservoir_v1", "feature_dim": 8},
        "run": {"output_dir": str(model), "seed": 66},
        "rhs_ns": {"tau0": 0.001},
        "normal": {"omega_prior": {"a": 2, "b": 1}, "vb_control": {"max_iter": 10}},
        "qdesn_vb": {
            "likelihoods": ["al", "exal"], "max_iter": 100, "min_iter_elbo": 50,
            "tol": 1e-4, "tol_par": 1e-4, "n_samp_xi": 10,
            "prior_sigma": {"a": 1, "b": 1}, "prior_gamma": {"mu0": 0, "s20": 10},
            "chunking": {"enabled": True, "mode": "exact", "chunk_size": 8},
        },
        "warm_start": {},
    }
    config.write_text(yaml.safe_dump({"pricefm_desn_smoke": smoke, "pricefm_stage_r65": {}}, sort_keys=False))
    config_hash = sha256(module, config)

    normal_dir = model / "normal_anchor"
    normal_dir.mkdir(parents=True)
    normal_fit = normal_dir / "normal_rhs_anchor.rds"
    normal_fit.write_bytes(b"normal-rds-fixture")
    normal_status = normal_dir / "normal_rhs_anchor.json"
    normal_status.write_text(json.dumps({
        "config_sha256": config_hash, "package_head": module.R65_PACKAGE_COMMIT,
        "case_id": module.GATE_CASE_ID, "role": "shared_normal_rhs_anchor",
        "fit_sha256": sha256(module, normal_fit), "converged": True,
    }))

    reuse_rows = []
    component_rows = []
    for tau in TAUS:
        component = model / "components" / f"tau={module.tau_slug(tau)}"
        component.mkdir(parents=True)
        fit = component / "al_fit.rds"
        fit.write_bytes(f"al-{tau}".encode())
        fit_hash = sha256(module, fit)
        status = component / "al_status.json"
        status.write_text(json.dumps({
            "config_sha256": config_hash, "package_head": module.R65_PACKAGE_COMMIT,
            "case_id": module.GATE_CASE_ID, "tau": module.tau_key(tau),
            "method_id": module.R65_METHOD_AL, "fit_sha256": fit_hash, "converged": True,
        }))
        prediction = component / "al_predictions_scaled.csv"
        prediction.write_text("pred_scaled\n0\n")
        reuse_rows.append({
            "case_id": module.GATE_CASE_ID, "region": "AT", "fold": 1, "tau": tau,
            "reuse_al_fit_authorized": True, "al_fit_path": str(fit),
            "al_status_path": str(status), "al_predictions_path": str(prediction),
            "al_fit_sha256": fit_hash,
        })
        component_rows.append({
            "case_id": module.GATE_CASE_ID, "region": "AT", "fold": 1, "tau": tau,
            "legacy_al_validation_AQL": tau, "legacy_exal_validation_AQL": tau + 0.1,
        })

    r65_manifest = tmp_path / "r65_manifest.csv"
    pd.DataFrame([{
        "case_id": module.GATE_CASE_ID, "region": "AT", "fold": 1,
        "config": str(config), "config_sha256": config_hash,
        "adapter_dir": str(adapter), "output_dir": str(model),
        "scientific_contract_sha256": "a" * 64, "feature_semantics_sha256": "b" * 64,
        "legacy_selected_family": "al", "legacy_selected_validation_AQL": 0.5,
        "legacy_al_validation_AQL": 0.5, "legacy_exal_validation_AQL": 0.6,
    }]).to_csv(r65_manifest, index=False)
    components = tmp_path / "r65_components.csv"
    pd.DataFrame(component_rows).to_csv(components, index=False)
    reuse = tmp_path / "r65_reuse.csv"
    pd.DataFrame(reuse_rows).to_csv(reuse, index=False)
    closeout = tmp_path / "r65_summary.json"
    closeout.write_text(json.dumps({"status": "scientifically_stopped_mechanism_failure"}))
    library = tmp_path / "library"
    (library / "exdqlm").mkdir(parents=True)
    (library / "pricefm_r66_install_manifest.json").write_text("{}\n")
    package = tmp_path / "package"
    package.mkdir()
    return r65_manifest, components, reuse, closeout, package, library


def test_r66_prep_reuses_only_hash_valid_r65_inputs(tmp_path, monkeypatch):
    module = load("r66_prep", "229_prepare_pricefm_stage_r66_corrected_structured_exal_vb.py")
    r65, components, reuse, closeout, package, library = prep_fixture(tmp_path, module)
    monkeypatch.setattr(module, "verify_package", lambda path: {
        "path": str(package), "commit": module.PACKAGE_COMMIT,
        "source_sha256": module.PACKAGE_HASHES,
    })
    monkeypatch.setattr(module, "verify_runtime_library", lambda path: str(library))
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--r65-manifest", str(r65),
        "--r65-components", str(components), "--r65-reuse-manifest", str(reuse),
        "--r65-closeout-summary", str(closeout), "--package-path", str(package),
        "--package-library", str(library), "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"), "--output-dir", str(tmp_path / "output"),
        "--expected-cases", "1",
    ])
    summary = module.run(args)
    cases = pd.read_csv(tmp_path / "grid/case_manifest.csv")
    ledger = pd.read_csv(tmp_path / "grid/component_ledger.csv")
    payload = yaml.safe_load(Path(cases.iloc[0].config).read_text())
    smoke = payload["pricefm_desn_smoke"]
    r66 = payload["pricefm_stage_r66"]
    assert summary["reused_r65_adapters"] == 1
    assert summary["reused_r65_normal_anchors"] == 1
    assert summary["reused_r65_al_components"] == 7
    assert summary["fresh_corrected_exal_components"] == 7
    assert ledger.reuse_r65_al_authorized.all()
    assert not ledger.r65_exal_reuse_authorized.any()
    assert smoke["splits"] == ["train", "val"]
    assert smoke["qdesn_vb"]["max_iter"] == 150
    assert r66["structured_sigmagam"]["postwarmup_damping"] == 0.2
    assert r66["structured_sigmagam"]["min_postwarmup_updates"] == 35
    assert r66["reuse"]["r65_exal_reuse_authorized"] is False
    assert not list((tmp_path / "grid").glob("*.yaml"))


def test_r66_prep_rejects_reused_adapter_with_test_data(tmp_path, monkeypatch):
    module = load("r66_prep_firewall", "229_prepare_pricefm_stage_r66_corrected_structured_exal_vb.py")
    r65, components, reuse, closeout, package, library = prep_fixture(tmp_path, module, with_test=True)
    monkeypatch.setattr(module, "verify_package", lambda path: {
        "path": str(package), "commit": module.PACKAGE_COMMIT,
        "source_sha256": module.PACKAGE_HASHES,
    })
    monkeypatch.setattr(module, "verify_runtime_library", lambda path: str(library))
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--r65-manifest", str(r65),
        "--r65-components", str(components), "--r65-reuse-manifest", str(reuse),
        "--r65-closeout-summary", str(closeout), "--package-path", str(package),
        "--package-library", str(library), "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"), "--output-dir", str(tmp_path / "output"),
        "--expected-cases", "1",
    ])
    with pytest.raises(RuntimeError, match="test firewall"):
        module.run(args)


def gate_fixture(tmp_path, module, exal_aql=0.45):
    output = tmp_path / "model"
    output.mkdir(parents=True)
    gamma = {0.10: 1.4, 0.25: 0.5, 0.45: 0.1, 0.50: 0.0, 0.55: -0.1, 0.75: -0.5, 0.90: -1.4}
    pd.DataFrame([{
        "tau": tau, "al_converged": True, "exal_converged": True,
        "structured_telemetry_pass": True, "exact_conditional_gig_moment_pass": True,
        "continuation_start_pass": True, "exact_commit_count": 12,
        "moment_source": "conditional_gig_exact", "optimizer_start_source": "eta_start",
        "optimizer_used_fallback": False, "gamma": gamma[tau], "sigma": 0.1,
        "gamma_relative_boundary_margin": 0.2,
    } for tau in TAUS]).to_csv(output / "r66_component_status.csv", index=False)
    rows = []
    for method, offset in [(module.METHOD_AL, 0.0), (module.METHOD_EXAL, 0.02)]:
        for tau in TAUS:
            rows.append({
                "method_id": method, "split": "val", "origin_id": 1, "horizon": 1,
                "tau": tau, "pred_scaled": tau + offset,
            })
    pd.DataFrame(rows).to_csv(output / "model_predictions_scaled.csv", index=False)
    pd.DataFrame([
        {"method_id": module.METHOD_AL, "split": "val", "unit": "original", "AQL": 0.5},
        {"method_id": module.METHOD_EXAL, "split": "val", "unit": "original", "AQL": exal_aql},
    ]).to_csv(output / "metric_summary.csv", index=False)
    return output


def test_r66_real_case_gate_checks_mechanism_and_predictive_harm(tmp_path):
    module = load("r66_launcher_gate", "231_launch_pricefm_stage_r66_corrected_structured_exal_vb.py")
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--cpu-list", "0-19", "--authorize", "true",
    ])
    output = gate_fixture(tmp_path, module)
    frame, summary = module.evaluate_production_gate(output, args)
    assert summary["passed"] is True
    assert frame.loc[frame.required, "passed"].all()
    bad = gate_fixture(tmp_path / "bad", module, exal_aql=1.0)
    _, blocked = module.evaluate_production_gate(bad, args)
    assert blocked["passed"] is False
    assert blocked["status"] == "production_gate_blocked"


def test_r66_launcher_does_not_fan_out_when_gate_fails(tmp_path, monkeypatch):
    module = load("r66_launcher_block", "231_launch_pricefm_stage_r66_corrected_structured_exal_vb.py")
    manifest = tmp_path / "case_manifest.csv"
    pd.DataFrame([
        {"case_id": "gate", "region": "AA", "fold": 1, "output_dir": str(tmp_path / "gate"), "config": "x", "production_gate_case": True},
        {"case_id": "other", "region": "BB", "fold": 1, "output_dir": str(tmp_path / "other"), "config": "y", "production_gate_case": False},
    ]).to_csv(manifest, index=False)
    called = []
    monkeypatch.setattr(module, "parse_cpus", lambda value: list(range(20)))
    monkeypatch.setattr(module, "preflight", lambda manifest, args, cpus: {"manifest_cases": 2, "workers": 20})
    monkeypatch.setattr(module, "completion_state", lambda output: "completed")
    monkeypatch.setattr(module, "run_one", lambda row, cpu, code_root, python_bin: called.append(row["case_id"]) or {**row, "cpu": cpu, "status": "completed", "returncode": 0})
    monkeypatch.setattr(module, "evaluate_production_gate", lambda output, args: (
        pd.DataFrame([{"gate": "blocked", "required": True, "passed": False}]),
        {"status": "production_gate_blocked", "passed": False, "test_opened": False, "broad_launch_authorized_by_gate": False},
    ))
    args = module.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(manifest), "--cpu-list", "0-19",
        "--expected-cases", "2", "--authorize", "true",
    ])
    with pytest.raises(RuntimeError, match="broad launch blocked"):
        module.run(args)
    assert called == ["gate"]


def test_r66_runner_contract_is_corrected_reuse_safe_and_test_sealed():
    runner = (SCRIPTS / "230_run_pricefm_stage_r66_corrected_structured_exal_vb_case.R").read_text()
    helper = (SCRIPTS / "pricefm_stage_r66_vb_helpers.R").read_text()
    assert "r65_exal_reuse_authorized" in runner
    assert "R66 may not reuse any R65 exAL fit" in runner
    assert "r66_external_fit_contract" in runner
    assert "conditional_gig_exact" in helper
    assert "structured_exact_commit_count" in helper
    assert "optimizer_start_source" in helper
    assert 'c("train", "val")' in runner
    assert "X_test.csv" in runner


def closeout_fixture(tmp_path, module):
    model = tmp_path / "case/model"
    adapter = tmp_path / "case/adapter"
    model.mkdir(parents=True)
    adapter.mkdir(parents=True)
    pd.DataFrame([{"origin_id": 1, "horizon": 1, "y_scaled": 1.0}]).to_csv(adapter / "rows_val.csv", index=False)
    predictions = []
    for tau in TAUS:
        predictions.extend([
            {"method_id": module.METHOD_AL, "split": "val", "origin_id": 1, "horizon": 1, "tau": tau, "pred_scaled": 0.0},
            {"method_id": module.METHOD_EXAL, "split": "val", "origin_id": 1, "horizon": 1, "tau": tau, "pred_scaled": 0.2},
        ])
    pd.DataFrame(predictions).to_csv(model / "model_predictions_scaled.csv", index=False)
    pd.DataFrame([
        {"method_id": method, "split": "val", "unit": unit, "AQL": value}
        for method, value in [(module.METHOD_AL, 0.5), (module.METHOD_EXAL, 0.4)]
        for unit in ["scaled", "original"]
    ]).to_csv(model / "metric_summary.csv", index=False)
    pd.DataFrame([{
        "tau": tau, "selection_eligible": True, "structured_telemetry_pass": True,
        "exact_conditional_gig_moment_pass": True, "continuation_start_pass": True,
        "optimizer_used_fallback": False, "exact_commit_count": 10,
        "gamma_relative_boundary_margin": 0.2,
    } for tau in TAUS]).to_csv(model / "r66_component_status.csv", index=False)
    (model / "r66_case_fit_summary.json").write_text("{}\n")
    (model / "checkpoint_provenance.csv").write_text("tau\n0.1\n")
    (model / "run_manifest.json").write_text("{}\n")
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame([{
        "case_id": "case", "region": "AA", "fold": 1, "output_dir": str(model),
        "adapter_dir": str(adapter), "legacy_selected_family": "al",
        "legacy_selected_validation_AQL": 0.5, "legacy_al_validation_AQL": 0.5,
        "legacy_exal_validation_AQL": 0.6,
    }]).to_csv(manifest, index=False)
    components = tmp_path / "components.csv"
    pd.DataFrame([{
        "case_id": "case", "region": "AA", "fold": 1, "tau": tau,
        "legacy_al_validation_AQL": tau, "legacy_exal_validation_AQL": tau + 0.1,
    } for tau in TAUS]).to_csv(components, index=False)
    status = tmp_path / "launch_status.csv"
    pd.DataFrame([{"case_id": "case", "status": "completed"}]).to_csv(status, index=False)
    gate = tmp_path / "gate.json"
    gate.write_text(json.dumps({"status": "production_gate_passed", "passed": True}))
    return manifest, components, status, gate


def test_r66_closeout_freezes_only_whole_bundle_validation_winner(tmp_path):
    module = load("r66_closeout", "233_closeout_pricefm_stage_r66_corrected_structured_exal_vb.py")
    manifest, components, status, gate = closeout_fixture(tmp_path, module)
    output = tmp_path / "closeout"
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--component-ledger", str(components),
        "--launch-status", str(status), "--production-gate", str(gate),
        "--output-dir", str(output), "--expected-cases", "1",
    ])
    summary = module.run(args)
    queue = pd.read_csv(output / "pricefm_stage_r66_frozen_test_audit_queue.csv")
    assert summary["structured_exal_validation_winners"] == 1
    assert len(queue) == 1
    assert queue.iloc[0].selected_family == "corrected_structured_exal"
    assert queue.iloc[0].test_opened in (False, np.bool_(False))
