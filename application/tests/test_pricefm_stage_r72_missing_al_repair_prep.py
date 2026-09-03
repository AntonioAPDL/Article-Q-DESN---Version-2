import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r72_prep", SCRIPTS / "244_prepare_pricefm_stage_r72_missing_al_repair.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r72_prep_materializes_only_missing_al_atoms(tmp_path):
    module = load()
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    for name in ("X_train.csv", "y_train.csv", "X_val.csv", "rows_val.csv"):
        (adapter / name).write_text("1\n")
    source_config = tmp_path / "case.yaml"
    source_config.write_text(yaml.safe_dump({
        "pricefm_desn_smoke": {
            "splits": ["train", "val"],
            "qdesn_vb": {"max_iter": 150, "n_samp": 200, "n_samp_xi": 200},
        }
    }))
    r69b = pd.DataFrame([{
        "case_id": "case_a", "config": str(source_config),
        "config_sha256": module.sha256(source_config), "adapter_dir": str(adapter),
        "rhs_tau0": 0.001, "feature_policy": "target_only", "depth_D": 2,
        "units_json": "[80,80]", "lag_window": 96, "alpha": 0.4,
        "rho": 0.9, "input_scale": 0.35,
        **{name: False for name in module.BLOCKED},
    }])
    r69b_path = tmp_path / "r69b.csv"
    r69b.to_csv(r69b_path, index=False)
    r71 = tmp_path / "r71"
    r71.mkdir()
    pd.DataFrame([
        {"case_id": "case_a", "region": "AA", "fold": 1, "tau": 0.25,
         "likelihood_family": "al", "disposition": "missing_requires_r72_refit"},
        {"case_id": "case_a", "region": "AA", "fold": 1, "tau": 0.25,
         "likelihood_family": "exal", "disposition": "missing_exal_blocked"},
    ]).to_csv(r71 / "pricefm_stage_r71_atomic_fit_salvage_ledger.csv", index=False)
    (r71 / "pricefm_stage_r71_closeout_summary.json").write_text(json.dumps({
        "status": "r70_frozen_closed_out_no_promotion"
    }))
    runtime = tmp_path / "runtime.json"
    runtime.write_text(json.dumps({
        "status": "installed_pricefm_local_spd_repair",
        "base_tarball_sha256": module.BASE_SHA256,
        "patch_sha256": "abc", "library": str(tmp_path / "lib"),
        "installed_package": {"version": "1.1.1.9001", "repository": "PriceFM-local"},
    }))
    args = module.parser().parse_args([
        "--r69b-manifest", str(r69b_path), "--r71-dir", str(r71),
        "--runtime-manifest", str(runtime), "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"), "--output-dir", str(tmp_path / "out"),
        "--expected-tasks", "1",
    ])
    summary = module.run(args)
    manifest = pd.read_csv(tmp_path / "grid/task_manifest.csv")
    task = json.loads(Path(manifest.iloc[0].task_config).read_text())
    assert summary["tasks"] == 1
    assert set(manifest.likelihood_family) == {"al"}
    assert task["rhs_tau0"] == 0.001
    assert task["rhs_init_tau"] == 1
    assert task["rhs_freeze_tau_iters"] == 50
    assert task["exal_mechanism_gate_passed"] is False
    assert not list((tmp_path / "grid").rglob("*.yaml"))
