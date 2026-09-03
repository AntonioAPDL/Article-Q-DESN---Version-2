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


def test_r72_completion_requires_hash_valid_atomic_outputs(tmp_path):
    module = load("r72_launch", "246_launch_pricefm_stage_r72_missing_al_repair.py")
    output = tmp_path / "atom"
    output.mkdir()
    artifact = output / "predictions_scaled.csv"
    artifact.write_text("x\n1\n")
    (output / "terminal.json").write_text(json.dumps({
        "status": "completed", "test_loaded": False,
        "artifact_sha256": {artifact.name: module.sha256(artifact)},
    }))
    assert module.completion_state(output) == "completed"
    artifact.write_text("changed\n")
    assert module.completion_state(output) is None


def test_r72_monitor_counts_atomic_states(tmp_path, monkeypatch):
    module = load("r72_monitor", "247_monitor_pricefm_stage_r72_missing_al_repair.py")
    rows = []
    for index, state in enumerate(("completed", "failed", None)):
        output = tmp_path / f"task_{index}"
        output.mkdir()
        if state:
            (output / "terminal.json").write_text(json.dumps({"status": state, "converged": False}))
        rows.append({"task_id": f"task_{index}", "case_id": "case", "tau": index / 10,
                     "output_dir": str(output)})
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(rows).to_csv(manifest, index=False)
    monkeypatch.setattr(module, "active_processes", lambda: [])
    args = module.parser().parse_args(["--manifest", str(manifest)])
    result = module.run(args)
    assert result["completed_tasks"] == 1
    assert result["failed_tasks"] == 1
    assert result["remaining_tasks"] == 1
    assert result["state"] == "incomplete_with_failures"
