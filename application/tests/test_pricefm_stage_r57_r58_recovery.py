import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]


def load(name, filename):
    sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def make_repair_fixture(tmp_path, case_id="case_a", prediction_split="val"):
    adapter = tmp_path / case_id / "adapter"
    model = tmp_path / case_id / "model"
    adapter.mkdir(parents=True)
    model.mkdir()
    source = tmp_path / case_id / "source.yaml"
    source.write_text("source: fixture\n")
    smoke = tmp_path / case_id / "smoke.yaml"
    smoke.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
        "region": "AA", "fold": 1, "splits": ["train", "val"],
        "adapter": {"output_dir": str(adapter)}, "run": {"output_dir": str(model)},
    }}, sort_keys=False))
    config = tmp_path / case_id / "runtime.yaml"
    config.write_text(yaml.safe_dump({"pricefm_stage_r57_joint_vb": {
        "case_id": case_id, "region": "AA", "fold": 1,
        "likelihood_family": "exal", "method_id": "joint_qdesn_exal_rhs_ns_vb1",
        "vb_method_id": "VB1_structured_v", "source_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "source_experiment_id": "fixture", "source_config": str(source),
        "smoke_config": str(smoke), "adapter_dir": str(adapter), "output_dir": str(model),
        "quantiles": TAUS, "tau0": 0.001, "tol": 1e-4,
    }}, sort_keys=False))

    np.savetxt(adapter / "X_train.csv", np.ones((4, 3)), delimiter=",")
    np.savetxt(adapter / "y_train.csv", np.arange(4)[:, None], delimiter=",")
    np.savetxt(adapter / "X_val.csv", np.ones((2, 3)), delimiter=",")
    np.savetxt(adapter / "y_val.csv", np.array([[0.0], [1.0]]), delimiter=",")
    pd.DataFrame({
        "split": ["val", "val"], "origin_id": [1, 2], "horizon": [1, 1],
        "origin_market_time": ["2026-01-01"] * 2,
        "response_market_time": ["2026-01-01"] * 2,
        "y_scaled": [0.0, 1.0],
    }).to_csv(adapter / "rows_val.csv", index=False)
    pd.DataFrame({"split": ["train"] * 4, "origin_id": range(4), "horizon": [1] * 4,
                  "y_scaled": range(4)}).to_csv(adapter / "rows_train.csv", index=False)
    (adapter / "rows_all.csv").write_text("fixture\n")
    (adapter / "adapter_manifest.json").write_text(json.dumps({"splits": {"train": {}, "val": {}}}))
    (adapter / "feature_manifest.json").write_text(json.dumps({"fixture": True}))

    raw_values = [-1.0, -0.5, 0.4, 0.2, 0.7, 1.0, 1.5]
    predictions = []
    for origin in (1, 2):
        for tau, value in zip(TAUS, raw_values):
            predictions.append({
                "method_id": "joint_qdesn_exal_rhs_ns_vb1", "split": prediction_split,
                "origin_id": origin, "horizon": 1, "tau": tau,
                "pred_scaled": value + origin - 1,
            })
    pd.DataFrame(predictions).to_csv(model / "model_predictions_scaled.csv", index=False)
    pd.DataFrame({
        "iter": [1, 2, 3], "max_beta_change": [1.0, 0.2, 0.05],
        "max_gamma_change": [0.5, 0.1, 0.04], "max_sigma_change": [0.4, 0.1, 0.03],
        "max_qhat_change": [0.8, 0.2, 0.02],
    }).to_csv(model / "model_trace_summary.csv", index=False)
    pd.DataFrame({"method_id": ["joint_qdesn_exal_rhs_ns_vb1"], "tau": [0.5]}).to_csv(
        model / "model_parameter_summary.csv", index=False
    )
    pd.DataFrame({
        "origin_id": [1, 2], "horizon": [1, 1], "n_crossing_pairs": [1, 1],
        "max_crossing_magnitude": [0.2, 0.2],
    }).to_csv(model / "crossing_diagnostics.csv", index=False)
    (model / "joint_vb_initialization.rds").write_bytes(b"fixture-rds")
    pd.DataFrame([{
        "method_id": "joint_qdesn_exal_rhs_ns_vb1", "split": "val", "unit": "scaled", "AQL": 0.4,
    }]).to_csv(model / "metric_summary.csv", index=False)
    (model / "job_summary.json").write_text(json.dumps({
        "status": "failed", "case_id": case_id, "elapsed_seconds": 12.5,
        "n_train": 4, "n_slopes": 2,
    }))
    os.utime(model / "job_summary.json", None)
    manifest = tmp_path / f"{case_id}_manifest.csv"
    pd.DataFrame([{
        "case_id": case_id, "region": "AA", "fold": 1,
        "config": str(config), "output_dir": str(model),
    }]).to_csv(manifest, index=False)
    return manifest, model, adapter


def test_pava_matches_monotone_pooling():
    module = load("r57_repair_pava", "205_repair_pricefm_stage_r57_joint_vb_postfit.py")
    fitted = module.pava(np.array([0.0, 2.0, 1.0, 3.0, 2.0]))
    assert np.allclose(fitted, [0.0, 1.5, 1.5, 2.5, 2.5])
    assert np.all(np.diff(fitted) >= 0)
    rng = np.random.default_rng(20260824)
    raw = rng.normal(size=(100, 7))
    vectorized = module.pava_rows(raw)
    scalar = np.vstack([module.pava(row) for row in raw])
    assert np.allclose(vectorized, scalar, atol=1e-12, rtol=0)


def test_r57_repair_recovers_without_refit_and_is_idempotent(tmp_path):
    module = load("r57_repair", "205_repair_pricefm_stage_r57_joint_vb_postfit.py")
    manifest, model, adapter = make_repair_fixture(tmp_path)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--output-dir", str(tmp_path / "repair"),
        "--skip-summarizer", "true", "--require-original-metrics", "false",
        "--cleanup-heavy", "true", "--workers", "2",
    ])
    summary = module.run(args)
    repaired = json.loads((model / "job_summary.json").read_text())
    contract_diag = pd.read_csv(model / "contract_crossing_diagnostics.csv")
    assert summary["postfit_complete"] == 1
    assert summary["models_refit"] == 0
    assert repaired["postfit_repaired"] is True
    assert repaired["test_accessed"] is False
    assert repaired["adapter_cleanup_completed"] is True
    assert set(repaired["adapter_heavy_files_removed"]) == {
        "X_train.csv", "X_val.csv", "y_train.csv", "y_val.csv",
        "rows_train.csv", "rows_val.csv", "rows_all.csv",
    }
    assert contract_diag.contract_crossing_pairs.sum() == 0
    assert (model / "model_method_summary.csv").is_file()
    assert (model / "joint_vb_initialization.rds").is_file()
    assert not (adapter / "X_train.csv").exists()
    second = module.run(args)
    assert second["status_counts"] == {"already_repaired": 1}


def test_r57_repair_reuses_complete_generic_metrics(tmp_path, monkeypatch):
    module = load("r57_repair_reuse", "205_repair_pricefm_stage_r57_joint_vb_postfit.py")
    manifest, model, _ = make_repair_fixture(tmp_path)
    pd.DataFrame([
        {"method_id": "joint_qdesn_exal_rhs_ns_vb1", "split": "val", "unit": "scaled", "AQL": 0.4},
        {"method_id": "joint_qdesn_exal_rhs_ns_vb1", "split": "val", "unit": "original", "AQL": 4.0},
    ]).to_csv(model / "metric_summary.csv", index=False)
    for name in (
        "metric_by_horizon.csv", "metric_by_horizon_group.csv",
        "predictions_with_naive_scaled.csv",
    ):
        pd.DataFrame([{"fixture": 1}]).to_csv(model / name, index=False)

    def forbidden(*_args, **_kwargs):
        raise AssertionError("Verified generic metrics must not be recomputed")

    monkeypatch.setattr(module.subprocess, "run", forbidden)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--output-dir", str(tmp_path / "repair"),
        "--require-original-metrics", "false",
    ])
    summary = module.run(args)
    repaired = json.loads((model / "job_summary.json").read_text())
    assert summary["postfit_complete"] == 1
    assert repaired["generic_summary_mode"] == "reused_and_replay_verified"
    assert not (model / "job_summary.json.tmp").exists()


def test_r57_repair_rejects_nonvalidation_predictions(tmp_path):
    module = load("r57_repair_firewall", "205_repair_pricefm_stage_r57_joint_vb_postfit.py")
    manifest, _, _ = make_repair_fixture(tmp_path, prediction_split="test")
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--output-dir", str(tmp_path / "repair"),
        "--skip-summarizer", "true", "--require-original-metrics", "false",
    ])
    summary = module.run(args)
    status = pd.read_csv(tmp_path / "repair/pricefm_stage_r57_postfit_repair_status.csv")
    assert summary["repair_failures"] == 1
    assert "non-validation split" in status.iloc[0].error


def test_r58_audits_partial_surface_without_opening_test_ledger(tmp_path):
    module = load("r58_audit", "206_audit_pricefm_stage_r58_joint_recovery.py")
    authority = tmp_path / "authority.csv"
    manifest = tmp_path / "launch.csv"
    authority_rows = []
    manifest_rows = []
    for index in range(2):
        case_id = f"case_{index}"
        model = tmp_path / case_id
        model.mkdir()
        authority_rows.append({
            "case_id": case_id, "region": f"R{index}", "fold": 1,
            "likelihood_family": "exal", "source_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "experiment_id": f"exp_{index}", "current_authoritative_validation_AQL": 2.0,
            "selection_split": "val", "selection_is_validation_only": True,
            "test_metrics_role": "audit_only",
        })
        manifest_rows.append({
            "case_id": case_id, "method_id": "joint_qdesn_exal_rhs_ns_vb1",
            "output_dir": str(model),
        })
        if index == 0:
            checkpoint = model / "joint_vb_initialization.rds"
            source_manifest = model / "source_manifest.csv"
            checkpoint.write_bytes(b"checkpoint")
            source_manifest.write_text("path,sha256\nfixture,abc\n")
            pd.DataFrame([
                {"prediction_role": "raw_joint", "split": "val", "unit": "original", "AQL": 1.5},
                {"prediction_role": "monotone_contract", "split": "val", "unit": "original", "AQL": 1.4},
            ]).to_csv(model / "raw_contract_metric_summary.csv", index=False)
            (model / "job_summary.json").write_text(json.dumps({
                "status": "completed", "postfit_repaired": True, "converged": False,
                "iterations": 50, "final_max_change": 0.02, "last5_change_slope": -0.001,
                "validation_crossing_rows": 3, "validation_crossing_pairs": 4,
                "contract_crossing_rows": 0, "contract_crossing_pairs": 0,
                "contract_adjusted_rows": 3, "contract_max_abs_adjustment": 0.2,
                "contract_mean_abs_adjustment": 0.01,
                "checkpoint": str(checkpoint), "checkpoint_sha256": digest(checkpoint),
                "source_manifest": str(source_manifest), "source_manifest_sha256": digest(source_manifest),
                "split_firewall": "train_validation_only", "test_accessed": False,
            }))
    pd.DataFrame(authority_rows).to_csv(authority, index=False)
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    (tmp_path / "sealed_test_ledger.csv").write_text("must,not,open\n")
    args = module.parser().parse_args([
        "--authority", str(authority), "--manifest", str(manifest),
        "--output-dir", str(tmp_path / "audit"), "--expected-cases", "2",
    ])
    summary = module.run(args)
    cases = pd.read_csv(tmp_path / "audit/pricefm_stage_r58_case_triage.csv")
    assert summary["status"] == "partial_surface_continue_r57_and_repair"
    assert summary["postfit_complete"] == 1 and summary["remaining_cases"] == 1
    assert summary["provisional_vb_initializer_candidates"] == 1
    assert summary["mcmc_launch_authorized"] is False
    assert cases.loc[cases.case_id.eq("case_0"), "mechanism_queue"].iloc[0] == "convergence_and_raw_crossing_review"
    assert not list((tmp_path / "audit").glob("*.yaml"))


def test_r58_rejects_test_outcomes_in_authority(tmp_path):
    module = load("r58_audit_firewall", "206_audit_pricefm_stage_r58_joint_recovery.py")
    authority = tmp_path / "authority.csv"
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame([{
        "case_id": "c", "region": "AA", "fold": 1, "likelihood_family": "al",
        "source_method_id": "qdesn_al_rhs_ns_exact_chunked", "experiment_id": "e",
        "current_authoritative_validation_AQL": 1.0, "qdesn_AQL": 0.9,
        "selection_split": "val", "selection_is_validation_only": True,
        "test_metrics_role": "audit_only",
    }]).to_csv(authority, index=False)
    pd.DataFrame([{"case_id": "c", "method_id": "m", "output_dir": str(tmp_path / "m")}]).to_csv(
        manifest, index=False
    )
    args = module.parser().parse_args([
        "--authority", str(authority), "--manifest", str(manifest),
        "--output-dir", str(tmp_path / "audit"), "--expected-cases", "1",
    ])
    with pytest.raises(RuntimeError, match="Sealed test outcomes"):
        module.run(args)


def test_r58_full_surface_report_does_not_instruct_r57_to_continue():
    module = load("r58_complete_report", "206_audit_pricefm_stage_r58_joint_recovery.py")
    summary = {
        "status": "full_surface_ready_for_scoring_contract_freeze",
        "expected_cases": 114, "postfit_complete": 114, "remaining_cases": 0,
        "dual_role_validation_improvements": 112,
        "provisional_vb_initializer_candidates": 112, "strict_raw_candidates": 0,
    }
    report = module.render_report(
        summary,
        pd.DataFrame([{"likelihood_family": "al", "postfit_complete": 27}]),
        pd.DataFrame([{"gate": "full", "passed": True}]),
    )
    assert "No further Stage-R57 fitting or postfit repair is required" in report
    assert "Let R57 finish" not in report
    assert "Freeze monotone-contract validation AQL" in report


def test_recovery_monitor_only_repairs_and_audits(tmp_path, monkeypatch):
    module = load("r57_recovery_monitor", "207_monitor_pricefm_stage_r57_recovery.py")
    manifest = tmp_path / "manifest.csv"
    authority = tmp_path / "authority.csv"
    pd.DataFrame([{"case_id": "c"}]).to_csv(manifest, index=False)
    authority.write_text("case_id\nc\n")
    seen = []

    def fake(command):
        seen.append(command)
        if "205_repair_pricefm_stage_r57_joint_vb_postfit.py" in " ".join(command):
            return {"postfit_complete": 1, "repair_failures": 0}
        return {
            "postfit_complete": 1, "remaining_cases": 0,
            "status": "full_surface_ready_for_scoring_contract_freeze",
        }

    monkeypatch.setattr(module, "run_json_command", fake)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--authority", str(authority),
        "--output-dir", str(tmp_path / "monitor"),
        "--repair-output-dir", str(tmp_path / "repair"),
        "--audit-output-dir", str(tmp_path / "audit"),
        "--expected-cases", "1", "--poll-seconds", "0",
    ])
    summary = module.run(args)
    joined = " ".join(part for command in seen for part in command)
    assert summary["status"] == "completed"
    assert len(seen) == 2
    assert "--cleanup-heavy true" in joined
    assert "launch" not in joined.lower()
    assert "mcmc" not in joined.lower()
