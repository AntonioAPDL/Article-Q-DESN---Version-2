"""Focused tests for R94 closeout and reusable region-frozen preparation."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
from types import SimpleNamespace

import joblib
import numpy as np
import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


class IdentityScaler:
    def inverse_transform(self, values):
        return np.asarray(values, dtype=float)


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


def make_r94_closeout_fixture(tmp_path: Path, *, exal_eligible: bool = True):
    module = load("303_closeout_pricefm_stage_r94_validation_family.py")
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    rows = pd.DataFrame({
        "origin_id": [1] * 96,
        "horizon": list(range(1, 97)),
        "y_scaled": np.zeros(96),
    })
    rows.to_csv(adapter / "rows_val.csv", index=False)
    np.savetxt(adapter / "y_val.csv", np.zeros(96), delimiter=",")

    processed = tmp_path / "processed"
    scaler_path = processed / "scalers/fold_1/per_region_separate_xy_scalers.joblib"
    scaler_path.parent.mkdir(parents=True)
    joblib.dump({"SE_2": {"y_scaler": IdentityScaler()}}, scaler_path)
    data_config = tmp_path / "data.yaml"
    data_config.write_text(yaml.safe_dump({"pricefm": {"processed_dir": str(processed)}}))
    r93_task = tmp_path / "r93_task.json"
    write_json(r93_task, {"data_config": str(data_config)})

    manifest_rows = []
    for tau in module.PAPER_QUANTILES:
        token = f"{tau:.2f}".replace(".", "p")
        al = tmp_path / "r93" / token
        al.mkdir(parents=True)
        al_beta = al / "beta_summary.csv"
        pd.DataFrame({"feature_index": [1], "beta_mean": [0.0]}).to_csv(al_beta, index=False)
        al_prediction = al / "predictions_scaled.csv"
        al_frame = rows[["origin_id", "horizon"]].copy()
        al_frame.insert(0, "split", "val")
        al_frame.insert(0, "method_id", "qdesn_al")
        al_frame["tau"] = tau
        al_frame["pred_scaled"] = 1.0
        al_frame.to_csv(al_prediction, index=False)
        al_terminal = al / "terminal.json"
        write_json(al_terminal, {"numerical_gate_passed": True})

        output = tmp_path / "r94" / token
        output.mkdir(parents=True)
        exal_prediction = output / "predictions_scaled.csv"
        exal_frame = al_frame.copy()
        exal_frame["method_id"] = "qdesn_exal"
        exal_frame["pred_scaled"] = 0.5
        exal_frame.to_csv(exal_prediction, index=False)
        beta = output / "beta_summary.csv"
        pd.DataFrame({"feature_index": [1], "beta_mean": [0.0]}).to_csv(beta, index=False)
        pd.DataFrame([{"train_seconds": 1.0}]).to_csv(output / "method_summary.csv", index=False)
        write_json(output / "numerical_gate.json", {"first_state_delta_below_100": False})
        terminal = output / "terminal.json"
        status = "completed" if exal_eligible else "completed_numerically_ineligible"
        write_json(terminal, {
            "status": status, "task_id": f"task_{token}",
            "numerical_gate_passed": exal_eligible,
            "formal_converged": True, "iter": 80, "structured_updates": 79,
            "test_loaded": False, "test_opened": False,
            "test_access_authorized": False,
            "artifact_sha256": {
                "predictions_scaled.csv": module.sha256_file(exal_prediction),
            },
        })
        task = {
            "task_id": f"task_{token}", "pipeline_contract_sha256": "pipeline",
            "region": "SE_2", "fold": 1, "tau": tau,
            "adapter_dir": str(adapter), "source_r93_task": str(r93_task),
            "al_source_terminal": str(al_terminal),
            "al_prediction_path": str(al_prediction),
            "al_prediction_sha256": module.sha256_file(al_prediction),
            "al_beta_path": str(al_beta),
            "output_dir": str(output),
            "frozen_desn": {"depth": 2, "units": "[120,64]"},
            "rhs_tau0": 0.01,
            "adapter_files": [],
        }
        task_path = tmp_path / "tasks" / f"task_{token}.json"
        write_json(task_path, task)
        manifest_rows.append({
            "task_id": task["task_id"], "tau": tau, "likelihood_family": "exal",
            "task_config": str(task_path),
            "task_config_sha256": module.sha256_file(task_path),
        })
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    return module, manifest


def test_r94_closeout_selects_one_complete_family_on_validation(tmp_path):
    module, manifest = make_r94_closeout_fixture(tmp_path)
    summary = module.run(SimpleNamespace(
        manifest=manifest, output_dir=tmp_path / "closeout",
        quarantine_root=None, quarantine_existing=False,
    ))
    assert summary["selected_family"] == "exal"
    assert summary["exal_validation_AQL_original"] < summary["al_validation_AQL_original"]
    assert summary["test_opened"] is False
    frozen = json.loads((tmp_path / "closeout/pricefm_stage_r94_frozen_validation_family.json").read_text())
    assert len(frozen["selected_atoms"]) == 7
    assert frozen["per_quantile_family_mixing"] is False


def test_r94_closeout_falls_back_to_al_for_ineligible_exal(tmp_path):
    module, manifest = make_r94_closeout_fixture(tmp_path, exal_eligible=False)
    summary = module.run(SimpleNamespace(
        manifest=manifest, output_dir=tmp_path / "closeout",
        quarantine_root=None, quarantine_existing=False,
    ))
    assert summary["selected_family"] == "al"
    assert summary["exal_numerically_eligible"] is False


def test_generic_region_contract_has_no_hardcoded_se2_controls(monkeypatch, tmp_path):
    module = load("304_prepare_pricefm_region_frozen_contract.py")
    monkeypatch.setattr(module, "graph_contract", lambda region, regions: {
        policy: {"target_region": region, "neighbor_regions": []}
        for policy in module.POLICIES
    })
    authority = tmp_path / "authority.csv"
    controls = tmp_path / "controls.csv"
    frame = pd.DataFrame({"region": ["FI"] * 3, "fold": [1, 2, 3], "value": [1, 2, 3]})
    frame.to_csv(authority, index=False)
    frame.to_csv(controls, index=False)
    data = tmp_path / "data.yaml"
    data.write_text(yaml.safe_dump({"pricefm": {
        "regions": ["FI"],
        "splits": [{"fold": fold, "train": ["a", "b"], "val": ["b", "c"]} for fold in (1, 2, 3)],
    }}))
    summary = module.run(SimpleNamespace(
        pipeline_id="fi_fixture", target_region="FI", authority_registry=authority,
        control_registry=controls, data_config=data, artifact_root=tmp_path / "artifacts",
        output_dir=tmp_path / "contract", selection_fold=1, real_folds="1,2,3",
        candidate_count=240, ridge_top_k=30, coarse_tau0="1e-4,1e-3,1e-2",
        quarantine_root=None, quarantine_existing=False,
    ))
    assert summary["target_region"] == "FI"
    contract = json.loads((tmp_path / "contract/pricefm_region_frozen_contract.json").read_text())
    assert contract["target_region"] == "FI"
    assert contract["selection"]["fold_or_quantile_specific_retuning"] is False
    assert not list((tmp_path / "contract").rglob("*launch*.yaml"))


def test_allfold_graph_counts_depend_on_frozen_family(tmp_path):
    contract_module = load("pricefm_region_frozen_contract.py")
    module = load("305_prepare_pricefm_region_frozen_allfold.py")
    region = tmp_path / "region.json"
    write_json(region, {
        "target_region": "FI", "selection_fold": 1, "real_folds": [1, 2, 3],
        "quantiles": list(module.PAPER_QUANTILES), "test_opened": False,
        "test_access_authorized": False,
    })
    for family, expected in (("al", 16), ("exal", 30)):
        atoms = []
        for tau in module.PAPER_QUANTILES:
            records = {}
            for role in ("beta", "prediction", "terminal"):
                path = tmp_path / family / str(tau) / f"{role}.txt"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"{family}-{tau}-{role}\n")
                records[role] = contract_module.file_record(path, role)
            atoms.append({"tau": tau, **records})
        frozen = tmp_path / f"frozen_{family}.json"
        write_json(frozen, {
            "region": "FI", "selection_fold": 1, "quantiles": list(module.PAPER_QUANTILES),
            "selected_family": family, "per_quantile_family_mixing": False,
            "frozen_desn": {"depth": 2}, "rhs_tau0": 0.01,
            "selected_atoms": atoms, "test_opened": False,
            "test_access_authorized": False,
        })
        output = tmp_path / f"allfold_{family}"
        summary = module.run(SimpleNamespace(
            region_contract=region, frozen_family=frozen, output_dir=output,
            run_root=tmp_path / "runs", quarantine_root=None,
            quarantine_existing=False,
        ))
        assert summary["new_fits"] == expected
        manifest = pd.read_csv(output / "task_manifest.csv")
        assert int(manifest.execution_required.sum()) == expected
        assert not manifest.test_access_authorized.any()


def test_r94_controller_stops_before_test_and_requires_token():
    text = (SCRIPTS / "306_orchestrate_pricefm_stage_r94.py").read_text()
    assert 'APPROVAL_TOKEN = "RUN_PRICEFM_R94_THROUGH_VALIDATION_FREEZE"' in text
    assert '"stopped_before_allfold_and_test"' in text
    assert '"test_access_authorized": False' in text
    assert "303_closeout_pricefm_stage_r94_validation_family.py" in text
