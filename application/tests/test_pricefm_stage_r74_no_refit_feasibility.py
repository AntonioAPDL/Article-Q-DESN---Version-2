import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/250_audit_pricefm_stage_r74_no_refit_feasibility.py"
TAUS = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def load():
    sys.path.insert(0, str(SCRIPT.parent))
    spec = importlib.util.spec_from_file_location("r74", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixture(tmp_path):
    case, region = "case_1", "R1"
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    truth = []
    for origin in range(9):
        for horizon in (1, 25):
            truth.append({
                "split": "val", "origin_id": origin, "horizon": horizon,
                "origin_market_time": f"2026-01-{origin + 1:02d}T00:00:00Z",
                "y_scaled": origin / 10 + horizon / 1000,
            })
    pd.DataFrame(truth).to_csv(adapter / "rows_val.csv", index=False)
    scaler_path = tmp_path / "scaler.joblib"
    joblib.dump({region: {"y_scaler": RobustScaler().fit(np.array([[0.0], [2.0], [4.0]]))}}, scaler_path)
    prediction_dir = tmp_path / "predictions"
    prediction_dir.mkdir()
    atom_rows = []
    for index, tau in enumerate(TAUS):
        path = prediction_dir / f"q{index}.csv"
        rows = []
        # Deliberately reverse the quantile ordering so rearrangement must help.
        value = 1.0 - tau
        for item in truth:
            rows.append({
                "method_id": "al", "split": "val", "origin_id": item["origin_id"],
                "horizon": item["horizon"], "tau": tau, "pred_scaled": value,
            })
        pd.DataFrame(rows).to_csv(path, index=False)
        atom_rows.append({
            "case_id": case, "region": region, "fold": 1, "tau": tau,
            "prediction_path": str(path), "prediction_sha256": digest(path),
        })
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame([{
        "case_id": case, "region": region, "fold": 1, "adapter_dir": str(adapter),
    }]).to_csv(manifest, index=False)
    r73 = tmp_path / "r73"
    r73.mkdir()
    pd.DataFrame(atom_rows).to_csv(r73 / "pricefm_stage_r73_al_atom_ledger.csv", index=False)
    pd.DataFrame([{
        "case_id": case, "scaler_path": str(scaler_path),
        "prior_authoritative_qdesn_validation_AQL": 2.0,
        "operational_pricefm_validation_AQL": 1.5,
    }]).to_csv(r73 / "pricefm_stage_r73_case_validation_metrics.csv", index=False)
    (r73 / "summary.json").write_text(json.dumps({"status": "completed_al_surface_closed_out_no_automatic_promotion"}))
    return manifest, r73


def test_r74_uses_forward_blocks_and_never_promotes(tmp_path):
    module = load()
    manifest, r73 = fixture(tmp_path)
    output = tmp_path / "out"
    args = module.parser().parse_args([
        "--r69b-manifest", str(manifest), "--r73-dir", str(r73),
        "--output-dir", str(output), "--expected-cases", "1", "--expected-atoms", "7",
    ])
    summary = module.run(args)
    full = pd.read_csv(output / "pricefm_stage_r74_full_validation_rearrangement.csv")
    blocks = pd.read_csv(output / "pricefm_stage_r74_forward_calibration_arm_metrics.csv")
    assert summary["status"] == "completed_read_only_no_refit_feasibility_audit"
    assert summary["promotion_candidates"] == 0
    assert full.loc[full.arm.eq("rearranged"), "delta_vs_raw"].iloc[0] < 0
    assert set(blocks.forward_block) == {"early_to_middle", "expanding_to_late"}
    assert blocks.groupby("arm").size().eq(2).all()
    assert not list(output.rglob("*.yaml"))


def test_r74_fails_if_prediction_changes(tmp_path):
    module = load()
    manifest, r73 = fixture(tmp_path)
    atoms = pd.read_csv(r73 / "pricefm_stage_r73_al_atom_ledger.csv")
    Path(atoms.iloc[0].prediction_path).write_text("changed\n")
    args = module.parser().parse_args([
        "--r69b-manifest", str(manifest), "--r73-dir", str(r73),
        "--output-dir", str(tmp_path / "out"), "--expected-cases", "1", "--expected-atoms", "7",
    ])
    try:
        module.run(args)
    except RuntimeError as error:
        assert "Changed R73 prediction" in str(error)
    else:
        raise AssertionError("R74 accepted a modified source prediction")
