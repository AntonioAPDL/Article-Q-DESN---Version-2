import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r57_prep_materializes_114_firewalled_cases(tmp_path, monkeypatch):
    module = load("r57_prep", "201_prepare_pricefm_stage_r57_joint_vb.py")
    monkeypatch.setattr(module, "git_head", lambda path: "c" * 40)
    artifact = tmp_path / "artifact"
    authority_dir = tmp_path / "authority"
    authority_dir.mkdir()
    source_data = artifact / "data.yaml"
    source_data.parent.mkdir(parents=True)
    source_data.write_text(yaml.safe_dump({"pricefm": {
        "raw_dir": "application/data_local/pricefm/raw",
        "interim_dir": "application/data_local/pricefm/interim",
        "processed_dir": "application/data_local/pricefm/processed",
    }}))
    rows = []
    for index in range(114):
        region = f"R{index // 3:02d}"
        fold = index % 3 + 1
        case_id = f"pricefm_joint_{region.lower()}_f{fold}"
        source_config = artifact / f"source_{index}.yaml"
        source_config.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
            "data_config": str(source_data), "region": region, "fold": fold,
            "splits": ["train", "val", "test"], "quantiles": [0.5],
            "adapter": {"output_dir": "old", "feature_map": "window_reservoir_v1", "feature_dim": 4},
            "run": {"output_dir": "old"},
            "qdesn_vb": {"prior_sigma": {"a": 1, "b": 1}},
        }}, sort_keys=False))
        likelihood = "exal" if index < 87 else "al"
        rows.append({
            "case_id": case_id, "region": region, "fold": fold,
            "likelihood_family": likelihood,
            "vb_method_id": "VB1_structured_v" if likelihood == "exal" else "AL_joint_cavi",
            "source_method_id": f"qdesn_{likelihood}_rhs_ns_exact_chunked",
            "experiment_id": f"exp_{index}", "source_config": str(source_config),
            "source_config_sha256": "d" * 64, "source_data_config": str(source_data),
            "tau0": 0.001, "selection_split": "val", "selection_is_validation_only": True,
            "test_metrics_role": "audit_only",
        })
    pd.DataFrame(rows).to_csv(authority_dir / "pricefm_stage_r57_joint_case_authority.csv", index=False)
    args = module.parser().parse_args([
        "--artifact-repo", str(artifact), "--authority-dir", str(authority_dir),
        "--source-root", str(ROOT), "--output-dir", str(tmp_path / "prep"),
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--python-bin", sys.executable,
    ])
    summary = module.run(args)
    manifest = pd.read_csv(tmp_path / "grid/launch_manifest.csv")
    assert summary["cases"] == 114
    assert manifest.likelihood_family.value_counts().to_dict() == {"exal": 87, "al": 27}
    runtime = yaml.safe_load(Path(manifest.iloc[0].config).read_text())["pricefm_stage_r57_joint_vb"]
    smoke = yaml.safe_load(Path(manifest.iloc[0].smoke_config).read_text())["pricefm_desn_smoke"]
    assert runtime["allowed_splits"] == ["train", "val"]
    assert runtime["test_access_authorized"] is False
    assert runtime["python_bin"] == str(Path(sys.executable).absolute())
    assert smoke["splits"] == ["train", "val"]
    assert smoke["quantiles"] == list(module.TAUS)


def test_r57_runner_completes_tiny_train_val_case(tmp_path):
    adapter = tmp_path / "adapter"
    model = tmp_path / "model"
    adapter.mkdir()
    rng = np.random.default_rng(20260824)
    X_train = np.column_stack([np.ones(36), rng.normal(size=(36, 3))])
    X_val = np.column_stack([np.ones(12), rng.normal(size=(12, 3))])
    beta = np.array([0.4, -0.2, 0.1])
    y_train = X_train[:, 1:] @ beta + rng.normal(scale=0.2, size=36)
    y_val = X_val[:, 1:] @ beta + rng.normal(scale=0.2, size=12)
    for split, X, y in (("train", X_train, y_train), ("val", X_val, y_val)):
        np.savetxt(adapter / f"X_{split}.csv", X, delimiter=",")
        np.savetxt(adapter / f"y_{split}.csv", y[:, None], delimiter=",")
        pd.DataFrame({
            "split": split, "origin_id": np.arange(len(y)), "horizon": 1,
            "origin_market_time": "2026-01-01", "response_market_time": "2026-01-01",
            "y_scaled": y,
        }).to_csv(adapter / f"rows_{split}.csv", index=False)
    (adapter / "adapter_manifest.json").write_text(json.dumps({"splits": {"train": {}, "val": {}}}))
    source_config = tmp_path / "source.yaml"
    source_config.write_text("source: fixture\n")
    smoke_path = tmp_path / "smoke.yaml"
    smoke_path.write_text(yaml.safe_dump({"pricefm_desn_smoke": {
        "region": "AA", "fold": 1, "splits": ["train", "val"],
        "adapter": {"output_dir": str(adapter)}, "run": {"output_dir": str(model)},
    }}, sort_keys=False))
    config = tmp_path / "runtime.yaml"
    config.write_text(yaml.safe_dump({"pricefm_stage_r57_joint_vb": {
        "case_id": "fixture", "region": "AA", "fold": 1,
        "likelihood_family": "al", "method_id": "joint_qdesn_al_rhs_ns_vb",
        "vb_method_id": "AL_joint_cavi", "source_method_id": "qdesn_al_rhs_ns_exact_chunked",
        "source_experiment_id": "fixture", "source_config": str(source_config),
        "source_config_sha256": "e" * 64, "smoke_config": str(smoke_path),
        "adapter_dir": str(adapter), "output_dir": str(model), "source_root": str(ROOT),
        "python_bin": sys.executable, "adapter_builder": "unused", "summarizer": "unused",
        "allowed_splits": ["train", "val"], "test_access_authorized": False,
        "quantiles": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9],
        "tau0": 0.001, "a_sigma": 1.0, "b_sigma": 1.0, "max_iter": 5,
        "tol": 1e-4, "rhs_vb_inner": 1, "max_dense_dim": 100,
        "crossproduct_chunk_size": 8, "cleanup_adapter_after_success": False,
        "skip_summary_for_test": True, "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }}, sort_keys=False))
    result = subprocess.run(
        ["Rscript", str(SCRIPT_DIR / "202_run_pricefm_stage_r57_joint_vb_case.R"),
         "--config", str(config), "--resume", "true", "--force", "false"],
        cwd=ROOT, text=True, capture_output=True, check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    summary = json.loads((model / "job_summary.json").read_text())
    assert summary["status"] == "completed"
    assert summary["test_accessed"] is False
    assert summary["joint_dimension"] == 21
    assert summary["postfit_contract_pending"] is True
    assert (model / "joint_vb_initialization.rds").is_file()
    method = pd.read_csv(model / "model_method_summary.csv")
    assert method.iloc[0].model_family == "joint_qdesn_readout"
    assert method.iloc[0].likelihood_family == "al"
    assert not (adapter / "X_test.csv").exists()


def test_r57_launcher_assigns_one_lane_per_cpu(tmp_path, monkeypatch):
    module = load("r57_launcher", "203_launch_pricefm_stage_r57_joint_vb.py")
    manifest = tmp_path / "launch_manifest.csv"
    rows = [
        {"case_id": f"c{i}", "region": f"R{i}", "fold": 1, "config": str(tmp_path / f"c{i}.yaml"),
         "output_dir": str(tmp_path / f"out{i}")} for i in range(4)
    ]
    pd.DataFrame(rows).to_csv(manifest, index=False)
    seen = []
    def fake(row, cpu, runner, resume, force):
        seen.append((row["case_id"], cpu))
        return {**row, "cpu": cpu, "status": "completed", "returncode": 0}
    monkeypatch.setattr(module, "launch_one", fake)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--runner", str(tmp_path / "runner.R"),
        "--cpu-list", "4,6", "--workers", "2",
    ])
    summary = module.run(args)
    assert summary["completed_or_skipped"] == 4
    assert {cpu for _, cpu in seen} == {4, 6}
    assert summary["one_process_per_cpu"] is True


def test_r57_launcher_honors_graceful_stop_before_dispatch(tmp_path, monkeypatch):
    module = load("r57_launcher_stop", "203_launch_pricefm_stage_r57_joint_vb.py")
    manifest = tmp_path / "launch_manifest.csv"
    rows = [
        {"case_id": f"c{i}", "region": f"R{i}", "fold": 1,
         "config": str(tmp_path / f"c{i}.yaml"), "output_dir": str(tmp_path / f"out{i}")}
        for i in range(3)
    ]
    pd.DataFrame(rows).to_csv(manifest, index=False)
    stop_file = tmp_path / "STOP"
    stop_file.touch()

    def forbidden_launch(*_args, **_kwargs):
        raise AssertionError("No case should be dispatched after the stop sentinel exists")

    monkeypatch.setattr(module, "launch_one", forbidden_launch)
    args = module.parser().parse_args([
        "--manifest", str(manifest), "--runner", str(tmp_path / "runner.R"),
        "--cpu-list", "4,6", "--workers", "2", "--stop-file", str(stop_file),
    ])
    summary = module.run(args)
    assert summary["status"] == "stopped_before_completion"
    assert summary["not_launched_stop_requested"] == 3
    assert summary["completed_or_skipped"] == 0


def test_r57_closeout_selects_on_validation_without_test_ledger(tmp_path):
    module = load("r57_closeout", "204_closeout_pricefm_stage_r57_joint_vb.py")
    authority_dir = tmp_path / "authority"
    grid_dir = tmp_path / "grid"
    output = tmp_path / "closeout"
    authority_dir.mkdir()
    grid_dir.mkdir()
    authority_rows, manifest_rows = [], []
    for index, (candidate, reference, crossing) in enumerate(((1.5, 2.0, 0), (2.5, 2.0, 0))):
        case_id = f"case_{index}"
        model = tmp_path / case_id
        model.mkdir()
        checkpoint = model / "joint_vb_initialization.rds"
        checkpoint.write_bytes(b"fixture")
        (model / "job_summary.json").write_text(json.dumps({
            "status": "completed", "converged": True,
            "validation_crossing_rows": crossing, "checkpoint": str(checkpoint),
            "checkpoint_sha256": "f" * 64,
        }))
        method = "joint_qdesn_al_rhs_ns_vb"
        pd.DataFrame([{"method_id": method, "split": "val", "unit": "original", "AQL": candidate}]).to_csv(
            model / "metric_summary.csv", index=False
        )
        authority_rows.append({
            "case_id": case_id, "region": f"R{index}", "fold": 1,
            "likelihood_family": "al", "source_method_id": "qdesn_al_rhs_ns_exact_chunked",
            "experiment_id": f"exp{index}", "current_authoritative_validation_AQL": reference,
        })
        manifest_rows.append({
            "case_id": case_id, "method_id": method, "output_dir": str(model),
        })
    pd.DataFrame(authority_rows).to_csv(authority_dir / "pricefm_stage_r57_joint_case_authority.csv", index=False)
    pd.DataFrame(manifest_rows).to_csv(grid_dir / "launch_manifest.csv", index=False)
    (authority_dir / "pricefm_stage_r57_sealed_test_reference_ledger.csv").write_text("this,is,not,read\n")
    args = module.parser().parse_args([
        "--authority-dir", str(authority_dir), "--grid-dir", str(grid_dir),
        "--output-dir", str(output), "--expected-cases", "2",
    ])
    with pytest.raises(RuntimeError, match="superseded by the Stage-R58"):
        module.run(args)
    args.legacy_raw_gate_authorized = True
    summary = module.run(args)
    decisions = pd.read_csv(output / "pricefm_stage_r57_joint_vb_validation_decision_freeze.csv")
    queue = pd.read_csv(output / "pricefm_stage_r57_joint_mcmc_confirmation_queue.csv")
    assert summary["mcmc_confirmation_candidates"] == 1
    assert len(queue) == 1 and queue.iloc[0].case_id == "case_0"
    assert decisions.test_opened.eq(False).all()
