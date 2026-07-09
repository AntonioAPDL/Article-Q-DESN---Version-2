"""Tests for the PriceFM/Q-DESN model-selection bridge runner."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def args(**overrides):
    values = {
        "grid_config": "application/config/pricefm_desn_experiment_grid_median_de_lu_folds23_followup_20260605.yaml",
        "bridge_dir": "application/data_local/pricefm/authoritative/unit_bridge",
        "registry_dir": "application/data_local/pricefm/authoritative/unit_registry",
        "parity_dir": "application/data_local/pricefm/authoritative/unit_parity",
        "comparison_dir_template": "application/data_local/pricefm/authoritative/fold{fold}",
        "plan_dir": None,
        "regions": "DE_LU",
        "folds": "2,3",
        "priorities": "0",
        "stages": None,
        "ids": None,
        "quantile": "0.50",
        "selection_methods": "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
        "selection_split": "val",
        "selection_unit": "original",
        "selection_metric": "AQL",
        "expected_horizons": "1:96",
        "experiment_jobs": 10,
        "cell_jobs": 1,
        "build_windows": False,
        "resume": True,
        "force": False,
        "grid_dry_run": True,
        "run_grid": False,
        "select_existing": False,
        "validate_parity": False,
        "materialize_bridge": True,
        "execute": False,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def test_bridge_runner_plan_does_not_launch_by_default():
    mod = load_script("31_run_qdesn_model_selection_bridge.py")
    plan = mod.build_runner_plan(args())

    assert plan["will_launch_model_fits"] is False
    enabled = [row["step"] for row in plan["commands"] if row["enabled"]]
    assert enabled == ["materialize_bridge"]
    assert any("29_prepare_qdesn_model_selection_bridge.py" in x for x in plan["commands"][0]["command"])


def test_bridge_runner_marks_real_grid_launch_explicitly():
    mod = load_script("31_run_qdesn_model_selection_bridge.py")
    plan = mod.build_runner_plan(args(run_grid=True, grid_dry_run=False))

    grid_steps = [row for row in plan["commands"] if row["step"] == "run_pricefm_grid"]
    assert len(grid_steps) == 1
    assert grid_steps[0]["enabled"] is True
    assert grid_steps[0]["launches_model_fits"] is True
    assert plan["will_launch_model_fits"] is True


def test_bridge_runner_writes_plan_files(tmp_path):
    mod = load_script("31_run_qdesn_model_selection_bridge.py")
    plan = mod.build_runner_plan(args(plan_dir=str(tmp_path), select_existing=True, validate_parity=True))
    plan_dir = mod.write_plan(plan)

    assert plan_dir == tmp_path
    assert (tmp_path / "bridge_runner_plan.json").exists()
    commands = (tmp_path / "bridge_runner_commands.txt").read_text()
    assert "20_select_pricefm_desn_median_specs.py" in commands
    assert "30_validate_qdesn_model_selection_parity.py" in commands
