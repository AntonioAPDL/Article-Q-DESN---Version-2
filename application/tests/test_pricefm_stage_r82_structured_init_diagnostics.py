import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
PREP = SCRIPTS / "274_prepare_pricefm_stage_r82_structured_init_diagnostics.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_r82_diagnostics_are_exactly_three_bounded_controls(tmp_path):
    module = load("r82_diag", PREP)
    result = module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"),
        "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "out"),
    ]))
    manifest = pd.read_csv(tmp_path / "grid/diagnostic_manifest.csv")
    assert result["diagnostic_atoms"] == 3 and len(manifest) == 3
    assert set(manifest.case_id) == {"pricefm_joint_fr_f3", "pricefm_joint_se_4_f1"}
    for path in (tmp_path / "grid/tasks").glob("*.json"):
        task = json.loads(path.read_text())
        assert task["stage"] == "R82D" and task["diagnostic_mode"] is True
        assert task["sigmagam_freeze_warmup_iters"] == 0
        assert task["max_iter"] == 60 and task["min_postwarmup_updates"] == 35
        assert task["selection_split"] == "val"
        assert task["test_access_authorized"] is False
        assert task["registry_mutation_authorized"] is False
        assert task["article_mutation_authorized"] is False
        assert task["launch_authorized"] is False


def test_shared_diagnostic_launcher_accepts_only_r80_or_r82_diagnostics():
    text = (SCRIPTS / "266_launch_pricefm_stage_r80_diagnostic_replay.py").read_text()
    assert 'not in {"R80D", "R82D"}' in text
    assert "--authorize-diagnostic" in text
    assert 'env[name] = "1"' in text
