import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/272_prepare_pricefm_stage_r80d_warmup_ladder.py"


def test_warmup_ladder_is_small_and_changes_no_scientific_inputs(tmp_path):
    spec = importlib.util.spec_from_file_location("r80d", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    manifest = pd.read_csv(tmp_path / "grid/diagnostic_manifest.csv")
    assert len(manifest) == 4 and set(manifest.warmup_iters) == {1, 2, 3, 5}
    for path in (tmp_path / "grid/tasks").glob("*.json"):
        task = json.loads(path.read_text())
        assert task["max_iter"] == 20 and task["min_postwarmup_updates"] == 10
        assert task["test_access_authorized"] is False
        assert task["launch_authorized"] is False
        assert task["source_r80d_task_sha256"]
