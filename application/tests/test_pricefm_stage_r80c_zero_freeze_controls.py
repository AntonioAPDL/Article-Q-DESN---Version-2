import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/268_prepare_pricefm_stage_r80c_zero_freeze_controls.py"


def test_two_zero_freeze_controls_are_bounded_and_blocked(tmp_path):
    spec = importlib.util.spec_from_file_location("r80c", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    manifest = pd.read_csv(tmp_path / "grid/diagnostic_manifest.csv")
    assert len(manifest) == 2 and set(manifest.tau) == {0.25, 0.75}
    for path in (tmp_path / "grid/tasks").glob("*.json"):
        task = json.loads(path.read_text())
        assert task["sigmagam_freeze_warmup_iters"] == 0
        assert task["max_iter"] == 60 and task["min_postwarmup_updates"] == 35
        assert task["test_access_authorized"] is False
        assert task["launch_authorized"] is False
