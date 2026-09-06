import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name, filename):
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_r75_probe_prep_uses_nine_hash_frozen_real_anchors(tmp_path):
    prep = load("r75_prep", "252_prepare_pricefm_stage_r75_exal_mechanism_probe.py")
    grid, runs, output = tmp_path / "grid", tmp_path / "runs", tmp_path / "out"
    result = prep.run(prep.parser().parse_args([
        "--grid-dir", str(grid), "--run-dir", str(runs), "--output-dir", str(output),
    ]))
    manifest = pd.read_csv(grid / "probe_manifest.csv")
    assert result["tasks"] == 9 and len(manifest) == 9
    assert manifest.case_id.nunique() == 3 and set(manifest.tau) == {0.1, 0.5, 0.9}
    assert manifest.launch_authorized.eq(False).all()
    assert all(digest(Path(row.task_config)) == row.task_config_sha256 for row in manifest.itertuples())
    assert not list(grid.rglob("*.yaml"))

    launcher = load("r75_launcher", "254_launch_pricefm_stage_r75_exal_mechanism_probe.py")
    audit = launcher.run(launcher.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(grid / "probe_manifest.csv"),
        "--workers", "2", "--cpu-list", "0,1", "--preflight-only",
    ]))
    assert audit["status"] == "preflight_passed_no_probe" and audit["tasks"] == 9


def gate_fixture(tmp_path):
    rows, statuses = [], []
    for index in range(9):
        output = tmp_path / f"task_{index}"
        output.mkdir()
        pd.DataFrame([{
            "task_id": f"task_{index}", "case_id": f"case_{index // 3}",
            "region": f"R{index // 3}", "fold": 1, "tau": (0.1, 0.5, 0.9)[index % 3],
            "n_probe": 5000, "p": 10, "iter": 12, "converged": False,
            "structured_updates": 10, "al_sigma": 0.2, "exal_sigma": 0.18,
            "exal_gamma": 0.1, "al_beta_l2": 2.0, "exal_beta_l2": 2.2,
            "beta_l2_ratio": 1.1, "sigma_ratio": 0.9,
            "al_train_probe_AQL": 0.2, "exal_train_probe_AQL": 0.21,
            "train_AQL_ratio": 1.05, "delta_s_nonzero": True,
            "large_n_bessel_backend": "uniform_large_order", "elapsed_seconds": 1.0,
            "test_loaded": False, "binary_model_artifact_written": False,
        }]).to_csv(output / "probe_summary.csv", index=False)
        pd.DataFrame([{"iter": 1, "delta_s": 0.1}]).to_csv(output / "vb_trace.csv", index=False)
        pd.DataFrame([{"factorization_path": "direct"}]).to_csv(output / "spd_factorization_trace.csv", index=False)
        pd.DataFrame([{"gamma": 0.1, "weight": 1.0}]).to_csv(output / "structured_grid.csv", index=False)
        files = ["probe_summary.csv", "vb_trace.csv", "spd_factorization_trace.csv", "structured_grid.csv"]
        (output / "terminal.json").write_text(json.dumps({
            "status": "completed", "test_loaded": False,
            "artifact_sha256": {name: digest(output / name) for name in files},
        }))
        rows.append({"task_id": f"task_{index}", "output_dir": str(output)})
        statuses.append({"task_id": f"task_{index}", "status": "completed", "returncode": 0})
    manifest, status, launch = tmp_path / "manifest.csv", tmp_path / "status.csv", tmp_path / "launch.json"
    pd.DataFrame(rows).to_csv(manifest, index=False)
    pd.DataFrame(statuses).to_csv(status, index=False)
    launch.write_text(json.dumps({"status": "completed", "completed": 9, "failed": 0}))
    return manifest, status, launch


def test_r75_gate_authorizes_only_r76_prep(tmp_path):
    gate = load("r75_gate", "255_gate_pricefm_stage_r75_exal_mechanism.py")
    manifest, status, launch = gate_fixture(tmp_path)
    output = tmp_path / "gate"
    result = gate.run(gate.parser().parse_args([
        "--manifest", str(manifest), "--status", str(status),
        "--launch-summary", str(launch), "--output-dir", str(output),
    ]))
    assert result["status"] == "large_n_structured_exal_mechanism_gate_passed"
    assert result["r76_launch_prep_authorized"] is True
    assert result["r76_broad_launch_authorized"] is False
    assert result["test_opened"] is False and not list(output.rglob("*.yaml"))


def test_r75_gate_rejects_changed_probe_artifact(tmp_path):
    gate = load("r75_gate_changed", "255_gate_pricefm_stage_r75_exal_mechanism.py")
    manifest, status, launch = gate_fixture(tmp_path)
    first = Path(pd.read_csv(manifest).iloc[0].output_dir) / "probe_summary.csv"
    first.write_text("changed\n")
    args = gate.parser().parse_args([
        "--manifest", str(manifest), "--status", str(status),
        "--launch-summary", str(launch), "--output-dir", str(tmp_path / "gate"),
    ])
    try:
        gate.run(args)
    except RuntimeError as error:
        assert "Changed R75 probe artifact" in str(error)
    else:
        raise AssertionError("R75 gate accepted a modified probe artifact")
