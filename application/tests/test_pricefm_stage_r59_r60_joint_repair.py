import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def triage_row(case_id, index, improves):
    reference = 2.0
    contract = 1.5 if improves else 2.5
    return {
        "case_id": case_id, "region": f"R{index}", "fold": 1,
        "likelihood_family": "exal", "method_id": "joint_exal",
        "source_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "source_experiment_id": f"exp_{index}",
        "current_authoritative_validation_AQL": reference,
        "raw_joint_validation_AQL": contract + 0.1,
        "contract_validation_AQL": contract,
        "raw_relative_gain": (reference - contract - 0.1) / reference,
        "contract_relative_gain": (reference - contract) / reference,
        "postfit_complete": True, "integrity_pass": True, "fit_converged": False,
        "final_max_change": 0.2, "last5_change_slope": -0.01,
        "raw_crossing_rows": 4, "contract_crossing_pairs": 0,
        "checkpoint": f"/tmp/{case_id}.rds", "checkpoint_sha256": "a" * 64,
        "test_opened": False,
    }


def test_r59_freezes_monotone_contract_and_exact_two_case_repair_queue(tmp_path):
    module = load("r59_freeze", "208_freeze_pricefm_stage_r59_joint_scoring_contract.py")
    r58 = tmp_path / "r58"
    r58.mkdir()
    rows = [
        triage_row("winner", 0, True),
        triage_row("pricefm_joint_no_5_f2", 1, False),
        triage_row("pricefm_joint_se_2_f2", 2, False),
    ]
    pd.DataFrame(rows).to_csv(r58 / "pricefm_stage_r58_case_triage.csv", index=False)
    pd.DataFrame([
        {"gate": name, "passed": True, "observed": "fixture"}
        for name in (
            "full_114_case_surface_repaired", "all_completed_cases_pass_integrity",
            "contract_predictions_noncrossing", "selection_is_validation_only",
            "sealed_test_not_opened",
        )
    ]).to_csv(r58 / "pricefm_stage_r58_gates.csv", index=False)
    (r58 / "summary.json").write_text(json.dumps({
        "status": "full_surface_ready_for_scoring_contract_freeze",
        "postfit_complete": 3, "integrity_failures": 0, "test_opened": False,
    }))
    output = tmp_path / "r59"
    args = module.parser().parse_args([
        "--r58-dir", str(r58), "--output-dir", str(output), "--expected-cases", "3",
    ])
    summary = module.run(args)
    repair = pd.read_csv(output / "pricefm_stage_r59_joint_repair_queue.csv")
    assert summary["joint_scoring_contract_frozen"] is True
    assert summary["validation_selection_frozen"] is False
    assert summary["test_opened"] is False
    assert set(repair.case_id) == {"pricefm_joint_no_5_f2", "pricefm_joint_se_2_f2"}
    assert not list(output.glob("*.yaml"))


def test_r60_prep_materializes_only_two_arms_per_failed_case(tmp_path, monkeypatch):
    module = load("r60_prep", "209_prepare_pricefm_stage_r60_joint_repair.py")
    monkeypatch.setattr(module, "git_head", lambda _path: "c" * 40)
    r59, authority_dir, grid57 = tmp_path / "r59", tmp_path / "authority", tmp_path / "grid57"
    r59.mkdir()
    authority_dir.mkdir()
    grid57.mkdir()
    (r59 / "summary.json").write_text(json.dumps({
        "status": "completed_joint_scoring_contract_freeze",
        "joint_scoring_contract_frozen": True, "test_opened": False,
    }))
    source_config = tmp_path / "source.yaml"
    source_config.write_text("source: fixture\n")
    repair_rows, authority_rows, manifest_rows = [], [], []
    for index, case_id in enumerate(sorted(module.TARGETS)):
        likelihood = "al" if "no_5" in case_id else "exal"
        checkpoint = tmp_path / f"{case_id}.rds"
        checkpoint.write_bytes(f"checkpoint-{case_id}".encode())
        smoke = tmp_path / f"{case_id}_smoke.yaml"
        smoke.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
            "region": f"R{index}", "fold": 2, "splits": ["train", "val"],
            "quantiles": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
            "data_config": str(tmp_path / "data.yaml"),
            "adapter": {"output_dir": "old", "feature_dim": 3},
            "run": {"output_dir": "old"},
        }}, sort_keys=False))
        runtime = tmp_path / f"{case_id}_runtime.yaml"
        runtime.write_text(yaml.safe_dump({"pricefm_stage_r57_joint_vb": {
            "stage": "R57", "case_id": case_id, "region": f"R{index}", "fold": 2,
            "likelihood_family": likelihood, "method_id": f"joint_{likelihood}",
            "vb_method_id": "VB1_structured_v" if likelihood == "exal" else "AL_joint_cavi",
            "source_method_id": f"qdesn_{likelihood}_rhs_ns_exact_chunked",
            "source_experiment_id": f"exp_{index}", "source_config": str(source_config),
            "source_config_sha256": digest(source_config), "smoke_config": str(smoke),
            "adapter_dir": "old", "output_dir": "old", "allowed_splits": ["train", "val"],
            "test_access_authorized": False,
            "quantiles": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
            "tau0": 0.001, "a_sigma": 1.0, "b_sigma": 1.0, "max_iter": 50,
            "tol": 1e-4, "rhs_vb_inner": 1, "max_dense_dim": 100,
            "crossproduct_chunk_size": 8, "cleanup_adapter_after_success": True,
        }}, sort_keys=False))
        repair_rows.append({
            "case_id": case_id, "current_authoritative_validation_AQL": 2.0,
            "checkpoint": str(checkpoint), "checkpoint_sha256": digest(checkpoint),
        })
        authority_rows.append({
            "case_id": case_id, "region": f"R{index}", "fold": 2,
            "likelihood_family": likelihood, "source_config": str(source_config),
        })
        manifest_rows.append({
            "case_id": case_id, "config": str(runtime), "smoke_config": str(smoke),
            "output_dir": str(tmp_path / "old" / case_id),
        })
    pd.DataFrame(repair_rows).to_csv(r59 / "pricefm_stage_r59_joint_repair_queue.csv", index=False)
    pd.DataFrame(authority_rows).to_csv(authority_dir / "pricefm_stage_r57_joint_case_authority.csv", index=False)
    pd.DataFrame(manifest_rows).to_csv(grid57 / "launch_manifest.csv", index=False)
    args = module.parser().parse_args([
        "--r59-dir", str(r59), "--r57-authority-dir", str(authority_dir),
        "--r57-grid-dir", str(grid57), "--source-root", str(ROOT),
        "--output-dir", str(tmp_path / "prep"), "--grid-dir", str(tmp_path / "grid60"),
        "--run-dir", str(tmp_path / "runs"), "--python-bin", sys.executable,
    ])
    summary = module.run(args)
    manifest = pd.read_csv(tmp_path / "grid60/launch_manifest.csv")
    assert summary["launch_cases"] == 4
    assert manifest.groupby("source_case_id").size().eq(2).all()
    assert set(manifest.initialization_mode) == {"cold", "core_plus_rhs_warm_restart_v1"}
    for path in manifest.config:
        cfg = yaml.safe_load(Path(path).read_text())["pricefm_stage_r57_joint_vb"]
        assert cfg["allowed_splits"] == ["train", "val"]
        assert cfg["test_access_authorized"] is False
        assert cfg["tau0"] == 0.001


def make_completed_arm(model, source_case_id, contract_aql, raw_aql, final_change, slope):
    model.mkdir(parents=True)
    checkpoint = model / "joint_vb_initialization.rds"
    checkpoint.write_bytes(b"v2-checkpoint")
    source_manifest = model / "source_manifest.csv"
    source_manifest.write_text("label,path,sha256\nfixture,fixture,abc\n")
    pd.DataFrame([
        {"prediction_role": "raw_joint", "split": "val", "unit": "original", "AQL": raw_aql},
        {"prediction_role": "monotone_contract", "split": "val", "unit": "original", "AQL": contract_aql},
    ]).to_csv(model / "raw_contract_metric_summary.csv", index=False)
    (model / "job_summary.json").write_text(json.dumps({
        "status": "completed", "postfit_repaired": True, "source_case_id": source_case_id,
        "converged": False, "final_max_change": final_change, "last5_change_slope": slope,
        "validation_crossing_rows": 3, "contract_crossing_pairs": 0,
        "checkpoint": str(checkpoint), "checkpoint_sha256": digest(checkpoint),
        "output_checkpoint_format": "pricefm_joint_vb_checkpoint_v2",
        "source_manifest": str(source_manifest), "source_manifest_sha256": digest(source_manifest),
        "split_firewall": "train_validation_only", "test_accessed": False,
    }))


def test_r60_closeout_selects_validation_winner_and_retains_unresolved_authority(tmp_path):
    module = load("r60_closeout", "210_closeout_pricefm_stage_r60_joint_repair.py")
    r59 = tmp_path / "r59"
    r59.mkdir()
    (r59 / "summary.json").write_text(json.dumps({
        "status": "completed_joint_scoring_contract_freeze", "test_opened": False,
    }))
    sources = [("pricefm_joint_no_5_f2", "NO_5", 2.0), ("pricefm_joint_se_2_f2", "SE_2", 3.0)]
    decision_rows, manifest_rows = [], []
    for source_case, region, reference in sources:
        decision_rows.append({
            "case_id": source_case, "region": region, "fold": 2,
            "current_authoritative_validation_AQL": reference,
            "contract_validation_AQL": reference + 0.5,
            "checkpoint": "/old/checkpoint", "checkpoint_sha256": "a" * 64,
        })
        values = (1.7, 1.9) if region == "NO_5" else (3.2, 3.4)
        for index, (arm, value) in enumerate(zip(("warm", "cold"), values)):
            model = tmp_path / source_case / arm
            make_completed_arm(model, source_case, value, value + 0.1, 0.2 + index * 0.1, -0.01)
            manifest_rows.append({
                "case_id": f"{source_case}__{arm}", "source_case_id": source_case,
                "region": region, "fold": 2, "likelihood_family": "exal",
                "method_id": f"joint_{arm}", "arm_id": arm,
                "initialization_mode": "cold" if arm == "cold" else "core_plus_rhs_warm_restart_v1",
                "max_iter": 100, "output_dir": str(model),
            })
    pd.DataFrame(decision_rows).to_csv(r59 / "pricefm_stage_r59_joint_scoring_decisions.csv", index=False)
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    output = tmp_path / "closeout"
    args = module.parser().parse_args([
        "--r59-dir", str(r59), "--manifest", str(manifest), "--output-dir", str(output),
    ])
    summary = module.run(args)
    cases = pd.read_csv(output / "pricefm_stage_r60_joint_repair_case_decisions.csv")
    full = pd.read_csv(output / "pricefm_stage_r60_full_surface_validation_decision.csv")
    assert summary["joint_repair_validation_winners"] == 1
    assert summary["mechanism_unresolved_cases"] == 1
    assert summary["validation_selection_frozen"] is False
    assert summary["recommended_action"] == "design_case_specific_joint_mechanism_change_without_opening_test"
    assert cases.loc[cases.region.eq("NO_5"), "decision"].iloc[0] == "joint_repair_resolved_validation_winner"
    assert full.loc[full.region.eq("SE_2"), "final_validation_decision"].iloc[0] == "retain_current_individual_authority"
    assert full.test_opened.eq(False).all()
    assert not list(output.glob("*.yaml"))


def test_r60_monitor_recognizes_postfit_failure_as_repairable(tmp_path):
    module = load("r60_monitor_health", "211_monitor_pricefm_stage_r60_joint_repair.py")
    model = tmp_path / "model"
    model.mkdir()
    for name in (
        "model_predictions_scaled.csv", "model_trace_summary.csv",
        "model_parameter_summary.csv", "crossing_diagnostics.csv",
        "joint_vb_initialization.rds",
    ):
        (model / name).write_text("fixture\n")
    (model / "job_summary.json").write_text(json.dumps({
        "status": "failed", "error": "postfit summarizer failed", "test_accessed": False,
    }))
    manifest = pd.DataFrame([{
        "case_id": "arm", "source_case_id": "source", "region": "AA",
        "fold": 1, "arm_id": "warm", "output_dir": str(model),
    }])
    frame, counts = module.health(manifest)
    assert bool(frame.iloc[0].repairable)
    assert counts["repairable"] == 1
    assert counts["failed_unrepairable"] == 0
