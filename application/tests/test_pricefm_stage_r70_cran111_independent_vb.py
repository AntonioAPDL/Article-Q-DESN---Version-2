import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
TAUS = [0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90]
METHOD_AL = "qdesn_al_rhs_ns_cran111_r69b"
METHOD_EXAL = "qdesn_exal_rhs_ns_cran111_r69b"


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_case_config(path, case_id="case_a", region="AA", fold=1, splits=None, blocked=False):
    splits = splits or ["train", "val"]
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "pricefm_desn_smoke": {
            "data_config": str(path.parent / "data.yaml"),
            "python_bin": "/tmp/python",
            "r_library": "/tmp/library",
            "runtime_manifest": str(path.parent / "runtime.json"),
            "runtime_adapter_script": str(SCRIPTS / "pricefm_stage_r67_cran111_adapter.R"),
            "package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
            "region": region,
            "fold": fold,
            "splits": splits,
            "horizons": [1, 2],
            "quantiles": TAUS,
            "feature_policy": "target_only",
            "adapter": {"output_dir": str(path.parent / "adapter"), "feature_map": "window_reservoir_v1"},
            "run": {"output_dir": str(path.parent / "model"), "seed": 70},
            "rhs_ns": {"tau0": 0.001},
            "qdesn_vb": {
                "likelihoods": ["al", "exal"],
                "public_api": "exalStaticLDVB",
                "fork_only_namespace_calls_authorized": False,
            },
        },
        "pricefm_stage_r69b": {
            "case_id": case_id,
            "method_ids": {"al": METHOD_AL, "exal": METHOD_EXAL},
            "launch_authorized": blocked,
            "launcher_invoked_by_prep": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        },
    }
    path.write_text(yaml.safe_dump(payload, sort_keys=False))
    return path


def manifest_frame(tmp_path, n=2):
    rows = []
    for idx in range(n):
        case_id = f"case_{idx}"
        config = write_case_config(
            tmp_path / "configs" / f"{case_id}.yaml",
            case_id=case_id,
            region=f"R{idx}",
            fold=idx + 1,
        )
        rows.append({
            "case_id": case_id,
            "region": f"R{idx}",
            "fold": idx + 1,
            "config": str(config),
            "output_dir": str(tmp_path / "runs" / case_id / "model"),
            "expected_al_method_id": METHOD_AL,
            "expected_exal_method_id": METHOD_EXAL,
            "package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
            "cran111_version": "1.1.1",
            "selection_split": "val",
            "selection_is_validation_only": True,
            "launch_authorized": False,
            "launcher_invoked_by_prep": False,
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "joint_model_authorized": False,
            "mcmc_authorized": False,
        })
    return pd.DataFrame(rows)


def test_r70_preflight_accepts_authorized_train_val_cran_manifest(tmp_path, monkeypatch):
    module = load("r70_launch", "239_launch_pricefm_stage_r70_cran111_independent_vb.py")
    manifest = manifest_frame(tmp_path)
    monkeypatch.setattr(module, "available_memory_gib", lambda: 200.0)
    monkeypatch.setattr(module.shutil, "disk_usage", lambda _path: type("DU", (), {"free": 300 * 1024**3})())
    args = module.parser().parse_args([
        "--code-root", str(ROOT),
        "--workers", "2",
        "--cpu-list", "0,1",
        "--expected-cases", "2",
        "--authorize", "true",
    ])
    audit = module.preflight(manifest, args, [0, 1])
    assert audit["manifest_cases"] == 2
    assert audit["expected_atomic_fits"] == 28
    assert audit["test_access"] is False
    assert audit["registry_mutation_authorized"] is False


def test_r70_launcher_preflight_only_does_not_schedule_workers(tmp_path, monkeypatch):
    module = load("r70_launch_preflight_only", "239_launch_pricefm_stage_r70_cran111_independent_vb.py")
    manifest = manifest_frame(tmp_path, n=1)
    manifest_path = tmp_path / "case_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    monkeypatch.setattr(module, "available_memory_gib", lambda: 200.0)
    monkeypatch.setattr(module.shutil, "disk_usage", lambda _path: type("DU", (), {"free": 300 * 1024**3})())
    monkeypatch.setattr(module, "run_one", lambda *args, **kwargs: pytest.fail("run_one should not be called"))
    args = module.parser().parse_args([
        "--code-root", str(ROOT),
        "--manifest", str(manifest_path),
        "--workers", "1",
        "--cpu-list", "0",
        "--expected-cases", "1",
        "--authorize", "true",
        "--preflight-only", "true",
    ])
    result = module.run(args)
    assert result["status"] == "preflight_passed_no_launch"
    assert (tmp_path / "launch_preflight.json").is_file()
    assert not (tmp_path / "launch_status.csv").exists()


def test_r70_preflight_rejects_unauthorized_or_test_split(tmp_path, monkeypatch):
    module = load("r70_launch_reject", "239_launch_pricefm_stage_r70_cran111_independent_vb.py")
    manifest = manifest_frame(tmp_path, n=1)
    monkeypatch.setattr(module, "available_memory_gib", lambda: 200.0)
    monkeypatch.setattr(module.shutil, "disk_usage", lambda _path: type("DU", (), {"free": 300 * 1024**3})())
    args = module.parser().parse_args([
        "--code-root", str(ROOT),
        "--workers", "1",
        "--cpu-list", "0",
        "--expected-cases", "1",
    ])
    with pytest.raises(RuntimeError, match="requires --authorize true"):
        module.preflight(manifest, args, [0])

    bad = manifest.copy()
    write_case_config(Path(bad.iloc[0].config), case_id=bad.iloc[0].case_id, splits=["train", "val", "test"])
    args = module.parser().parse_args([
        "--code-root", str(ROOT),
        "--workers", "1",
        "--cpu-list", "0",
        "--expected-cases", "1",
        "--authorize", "true",
    ])
    with pytest.raises(RuntimeError, match="train/validation only"):
        module.preflight(bad, args, [0])


def write_completed_case(output):
    output.mkdir(parents=True, exist_ok=True)
    (output / "r70_case_fit_summary.json").write_text(json.dumps({
        "terminal_components": 7,
        "eligible_components": 7,
        "test_loaded": False,
        "binary_model_artifacts_written": False,
    }))
    (output / "run_manifest.json").write_text("{}\n")
    pd.DataFrame([{"tau": tau, "selection_eligible": True} for tau in TAUS]).to_csv(
        output / "r70_component_status.csv", index=False
    )
    pred_rows = []
    for method in [METHOD_AL, METHOD_EXAL]:
        for tau in TAUS:
            pred_rows.append({
                "method_id": method,
                "split": "val",
                "origin_id": 1,
                "horizon": 1,
                "tau": tau,
                "pred_scaled": tau,
            })
    pd.DataFrame(pred_rows).to_csv(output / "model_predictions_scaled.csv", index=False)
    pd.DataFrame([
        {"method_id": METHOD_AL, "split": "val", "unit": "original", "AQL": 1.0},
        {"method_id": METHOD_EXAL, "split": "val", "unit": "original", "AQL": 0.9},
    ]).to_csv(output / "metric_summary.csv", index=False)
    pd.DataFrame([{"method_id": METHOD_AL}]).to_csv(output / "model_method_summary.csv", index=False)
    pd.DataFrame([{"method_id": METHOD_AL, "feature_index": 1, "beta_mean": 0.1}]).to_csv(
        output / "model_beta_mean.csv", index=False
    )


def test_r70_completion_state_requires_validation_only_and_no_binary_outputs(tmp_path):
    module = load("r70_completion", "239_launch_pricefm_stage_r70_cran111_independent_vb.py")
    output = tmp_path / "model"
    write_completed_case(output)
    assert module.completion_state(output) == "completed"
    (output / "bad.rds").write_bytes(b"binary")
    assert module.completion_state(output) is None


def test_r70_monitor_counts_progress_and_never_mutates(tmp_path, monkeypatch):
    launcher = load("r70_launch_for_monitor", "239_launch_pricefm_stage_r70_cran111_independent_vb.py")
    monitor = load("r70_monitor", "240_monitor_pricefm_stage_r70_cran111_independent_vb.py")
    manifest = manifest_frame(tmp_path, n=2)
    manifest_path = tmp_path / "case_manifest.csv"
    manifest.to_csv(manifest_path, index=False)
    write_completed_case(Path(manifest.iloc[0].output_dir))
    pd.DataFrame([{"case_id": manifest.iloc[0].case_id, "status": "completed"}]).to_csv(
        tmp_path / "launch_status.csv", index=False
    )
    monkeypatch.setattr(monitor, "active_processes", lambda: [])
    args = monitor.parser().parse_args(["--manifest", str(manifest_path)])
    result = monitor.run(args)
    assert result["state"] == "incomplete_stalled"
    assert result["metric_complete_cases"] == 1
    assert result["remaining_cases"] == 1
    assert result["binary_model_artifact_count"] == 0
    assert result["test_opened"] is False
    assert launcher.completion_state(Path(manifest.iloc[0].output_dir)) == "completed"


def test_r70_runner_uses_cran_public_api_and_no_model_rds_persistence():
    runner = (SCRIPTS / "238_run_pricefm_stage_r70_cran111_independent_vb_case.R").read_text()
    assert "pricefm_stage_r67_cran111_adapter.R" in runner
    assert "r67_fit_quantile" in runner
    assert "exalStaticLDVB" in runner
    assert "X_test.csv" in runner
    assert "binary_model_artifact_written = FALSE" in runner
    assert "python_bin <- normalizePath" not in runner
    assert "saveRDS(" not in runner
    assert "::normal_desn_fit" not in runner
    assert "::qdesn_fit_vb" not in runner
    assert "::exal_ldvb_fit" not in runner
    assert "::beta_prior" not in runner
