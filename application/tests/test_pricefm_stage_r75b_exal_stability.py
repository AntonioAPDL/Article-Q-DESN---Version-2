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


def test_r75b_prep_preserves_surface_and_uses_late_stability_schedule(tmp_path):
    module = load("r75b_prep", "256_prepare_pricefm_stage_r75b_exal_stability_probe.py")
    result = module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    manifest = pd.read_csv(tmp_path / "grid/probe_manifest.csv")
    assert result["tasks"] == 9
    assert len(manifest) == 9 and manifest.case_id.nunique() == 3
    assert manifest.max_iter.eq(100).all()
    assert manifest.rhs_freeze_tau_iters.eq(50).all()
    assert manifest.sigmagam_freeze_warmup_iters.eq(10).all()
    assert manifest.min_postwarmup_updates.eq(35).all()
    assert manifest.launch_authorized.eq(False).all()
    assert not list((tmp_path / "grid").rglob("*.yaml"))
    for row in manifest.itertuples(index=False):
        task = json.loads(Path(row.task_config).read_text())
        assert task["probe_only"] is True
        assert task["selection_split"] == "train_stability_probe"
        assert task["test_access_authorized"] is False


def test_r75b_gate_rejects_changed_atomic_artifact(tmp_path):
    module = load("r75b_gate", "257_gate_pricefm_stage_r75b_exal_stability.py")
    rows = []
    for i in range(9):
        output = tmp_path / f"run{i}"
        output.mkdir()
        (output / "probe_summary.csv").write_text("value\n1\n")
        (output / "terminal.json").write_text(json.dumps({
            "status": "completed", "test_loaded": False,
            "artifact_sha256": {"probe_summary.csv": "not-the-real-hash"},
        }))
        rows.append({
            "task_id": f"t{i}", "region": "R", "fold": 1,
            "tau": 0.1 + i / 100, "output_dir": str(output),
        })
    manifest = pd.DataFrame(rows)
    status = manifest.assign(status="completed")
    manifest_path, status_path = tmp_path / "manifest.csv", tmp_path / "status.csv"
    manifest.to_csv(manifest_path, index=False)
    status.to_csv(status_path, index=False)
    launch = tmp_path / "launch.json"
    launch.write_text(json.dumps({"completed": 9, "failed": 0}))
    try:
        module.run(module.parser().parse_args([
            "--manifest", str(manifest_path), "--status", str(status_path),
            "--launch-summary", str(launch), "--output-dir", str(tmp_path / "out"),
        ]))
    except RuntimeError as error:
        assert "Changed R75B artifact" in str(error)
        pass
    else:
        raise AssertionError("Incomplete R75B atomic artifacts must be rejected")
