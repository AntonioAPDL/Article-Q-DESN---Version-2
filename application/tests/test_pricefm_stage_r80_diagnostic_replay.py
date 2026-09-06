import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/265_prepare_pricefm_stage_r80_diagnostic_replay.py"


def load():
    spec = importlib.util.spec_from_file_location("r80_prep", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_r80_prep_is_three_diagnostic_atoms_only(tmp_path):
    module = load()
    args = module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "output"),
    ])
    result = module.run(args)
    manifest = pd.read_csv(tmp_path / "grid/diagnostic_manifest.csv")
    assert result["diagnostic_atoms"] == 3
    assert len(manifest) == 3
    assert set(manifest.tau) == {0.25, 0.75}
    assert not manifest.launch_authorized.astype(bool).any()
    assert not manifest.test_access_authorized.astype(bool).any()
    assert not list((tmp_path / "grid").rglob("*.yaml"))


def test_r80_task_configs_preserve_sources_and_change_only_runtime_role(tmp_path):
    import json
    module = load()
    module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "output"),
    ]))
    for path in (tmp_path / "grid/tasks").glob("*.json"):
        task = json.loads(path.read_text())
        assert task["stage"] == "R80D" and task["diagnostic_mode"] is True
        assert task["selection_split"] == "val"
        assert task["test_access_authorized"] is False
        assert task["method_id"] == "diagnostic_only_not_scientific_fit"


def test_r80_launcher_preflight_does_not_execute(tmp_path):
    module = load()
    module.run(module.parser().parse_args([
        "--grid-dir", str(tmp_path / "grid"), "--run-dir", str(tmp_path / "runs"),
        "--output-dir", str(tmp_path / "output"),
    ]))
    launch_path = ROOT / "application/scripts/pricefm/266_launch_pricefm_stage_r80_diagnostic_replay.py"
    spec = importlib.util.spec_from_file_location("r80_launch", launch_path)
    launcher = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = launcher
    spec.loader.exec_module(launcher)
    result = launcher.run(launcher.parser().parse_args([
        "--code-root", str(ROOT), "--manifest", str(tmp_path / "grid/diagnostic_manifest.csv"),
        "--cpu-list", "30,31,32", "--preflight-only",
    ]))
    assert result["status"] == "preflight_passed_not_launched"
    assert not list((tmp_path / "runs").rglob("terminal.json"))
