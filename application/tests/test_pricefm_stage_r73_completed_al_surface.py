import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/249_closeout_pricefm_stage_r73_completed_al_surface.py"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def load():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("r73", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_atom(root, case, tau, stage, prediction, converged=True):
    slug = f"{tau:g}".replace(".", "p")
    if stage == "R69B":
        out = root / "r69" / case / "model" / "components" / f"tau={slug}"
        names = ("al_predictions_scaled.csv", "al_method_summary.csv", "al_parameter_summary.csv")
    else:
        out = root / "r72" / case / "components" / f"tau={slug}" / "al"
        names = ("predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv")
    out.mkdir(parents=True, exist_ok=True)
    pred = out / names[0]
    pd.DataFrame([
        {"method_id": "al", "split": "val", "origin_id": 0, "horizon": 1, "tau": tau, "pred_scaled": prediction},
        {"method_id": "al", "split": "val", "origin_id": 0, "horizon": 2, "tau": tau, "pred_scaled": prediction + 0.1},
    ]).to_csv(pred, index=False)
    pd.DataFrame([{"method_id": "al", "converged": converged, "iter": 10, "train_seconds": 1.0}]).to_csv(out / names[1], index=False)
    pd.DataFrame([{"method_id": "al", "sigma": 0.5}]).to_csv(out / names[2], index=False)
    if stage == "R69B":
        terminal = out / "component_terminal.json"
        terminal.write_text(json.dumps({"al_prediction_sha256": digest(pred), "test_loaded": False}))
    else:
        terminal = out / "terminal.json"
        terminal.write_text(json.dumps({
            "status": "completed", "test_loaded": False,
            "artifact_sha256": {name: digest(out / name) for name in names},
        }))
    return out, terminal


def fixture(tmp_path):
    processed = tmp_path / "processed"
    cases = []
    salvage = []
    tasks = []
    statuses = []
    for index, stage in enumerate(("R69B", "R72")):
        case = f"case_{index}"
        region = f"R{index}"
        fold = index + 1
        scaler_dir = processed / "scalers" / f"fold_{fold}"
        scaler_dir.mkdir(parents=True)
        scaler = RobustScaler().fit(np.array([[0.0], [2.0], [4.0]]))
        joblib.dump({region: {"y_scaler": scaler}}, scaler_dir / "per_region_separate_xy_scalers.joblib")
        data_config = tmp_path / f"data_{case}.yaml"
        data_config.write_text(yaml.safe_dump({"pricefm": {"processed_dir": str(processed)}}))
        adapter = tmp_path / "r69" / case / "adapter"
        adapter.mkdir(parents=True)
        pd.DataFrame([
            {"split": "val", "origin_id": 0, "horizon": 1, "y_scaled": 0.0},
            {"split": "val", "origin_id": 0, "horizon": 2, "y_scaled": 0.1},
        ]).to_csv(adapter / "rows_val.csv", index=False)
        cases.append({
            "case_id": case, "region": region, "fold": fold,
            "selected_family_anchor": "al" if index == 0 else "exal",
            "data_config": str(data_config), "adapter_dir": str(adapter),
            "r69a_validation_AQL_recomputed": 10.0,
            "qdesn_minus_operational_pricefm_AQL": 1.0,
            "qdesn_minus_cached_pricefm_AQL": 2.0,
            **{name: False for name in (
                "test_access_authorized", "registry_mutation_authorized",
                "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized",
            )},
        })
        for tau in TAUS:
            out, terminal = write_atom(tmp_path, case, tau, stage, tau, converged=index == 0)
            disposition = "reuse_r70_al_validation_artifact" if stage == "R69B" else "missing_requires_r72_refit"
            salvage.append({
                "case_id": case, "region": region, "fold": fold, "tau": tau,
                "likelihood_family": "al", "component_dir": str(out), "disposition": disposition,
            })
            if stage == "R72":
                task_id = f"{case}_{tau}"
                tasks.append({"task_id": task_id, "case_id": case, "tau": tau, "output_dir": str(out)})
                statuses.append({"task_id": task_id, "status": "completed", "returncode": 0})
    manifest = tmp_path / "case_manifest.csv"
    pd.DataFrame(cases).to_csv(manifest, index=False)
    r71 = tmp_path / "r71"
    r71.mkdir()
    pd.DataFrame(salvage).to_csv(r71 / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv", index=False)
    (r71 / "pricefm_stage_r71_closeout_summary.json").write_text(json.dumps({"status": "r70_frozen_closed_out_no_promotion"}))
    r72_manifest = tmp_path / "r72_manifest.csv"
    r72_status = tmp_path / "r72_status.csv"
    pd.DataFrame(tasks).to_csv(r72_manifest, index=False)
    pd.DataFrame(statuses).to_csv(r72_status, index=False)
    launch = tmp_path / "launch_summary.json"
    launch.write_text(json.dumps({"status": "completed", "failed": 0}))
    monitor = tmp_path / "monitor.json"
    monitor.write_text(json.dumps({"state": "running"}))
    return manifest, r71, r72_manifest, r72_status, launch, monitor


def test_r73_reconstructs_complete_validation_surface(tmp_path):
    module = load()
    inputs = fixture(tmp_path)
    output = tmp_path / "out"
    args = module.parser().parse_args([
        "--r69b-manifest", str(inputs[0]), "--r71-dir", str(inputs[1]),
        "--r72-manifest", str(inputs[2]), "--r72-status", str(inputs[3]),
        "--r72-launch-summary", str(inputs[4]), "--r72-monitor", str(inputs[5]),
        "--output-dir", str(output), "--expected-cases", "2", "--expected-atoms", "14",
        "--expected-r69b-atoms", "7", "--expected-r72-atoms", "7",
    ])
    summary = module.run(args)
    atoms = pd.read_csv(output / "pricefm_stage_r73_al_atom_ledger.csv")
    metrics = pd.read_csv(output / "pricefm_stage_r73_case_validation_metrics.csv")
    assert summary["status"] == "completed_al_surface_closed_out_no_automatic_promotion"
    assert summary["r72_stale_monitor_detected"] is True
    assert len(atoms) == 14 and set(atoms.source_stage) == {"R69B", "R72"}
    assert len(metrics) == 2 and metrics.test_opened.eq(False).all()
    assert not list(output.rglob("*.yaml")) and not list(output.rglob("*.rds"))


def test_r73_fails_closed_on_hash_mismatch(tmp_path):
    module = load()
    inputs = fixture(tmp_path)
    task = pd.read_csv(inputs[2]).iloc[0]
    Path(task.output_dir, "predictions_scaled.csv").write_text("corrupt\n")
    args = module.parser().parse_args([
        "--r69b-manifest", str(inputs[0]), "--r71-dir", str(inputs[1]),
        "--r72-manifest", str(inputs[2]), "--r72-status", str(inputs[3]),
        "--r72-launch-summary", str(inputs[4]), "--r72-monitor", str(inputs[5]),
        "--output-dir", str(tmp_path / "out"), "--expected-cases", "2",
        "--expected-atoms", "14", "--expected-r69b-atoms", "7", "--expected-r72-atoms", "7",
    ])
    try:
        module.run(args)
    except RuntimeError as error:
        assert "hash mismatch" in str(error)
    else:
        raise AssertionError("R73 accepted a changed R72 artifact")
