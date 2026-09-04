import importlib.util
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/267_prepare_pricefm_stage_r80b_zero_freeze_probe.py"


def test_probe_changes_only_diagnostic_schedule(tmp_path):
    spec = importlib.util.spec_from_file_location("r80b", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    result = module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    task = json.loads((tmp_path / "grid/task.json").read_text())
    assert result["changed_scientific_fields"] == []
    assert task["sigmagam_freeze_warmup_iters"] == 0
    assert task["max_iter"] == 60 and task["min_postwarmup_updates"] == 35
    assert task["selection_split"] == "val"
    assert task["test_access_authorized"] is False
    assert task["launch_authorized"] is False
    assert not list((tmp_path / "grid").rglob("*.yaml"))
