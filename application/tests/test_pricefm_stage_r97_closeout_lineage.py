"""Focused tests for the R97 quantile-to-normal closeout lineage."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


def load():
    path = SCRIPTS / "318_closeout_pricefm_stage_r97_region_quantile_surface.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def fixture(module, tmp_path: Path):
    config = tmp_path / "normal.yaml"
    config.write_text("pricefm_desn_full: {}\n")
    normal_output = tmp_path / "normal-task"
    adapter = tmp_path / "adapter"
    normal = {
        "task_id": "normal-fold-1",
        "fold": 1,
        "runner_type": "normal_full",
        "likelihood_family": "normal_rhs",
        "output_dir": str(normal_output),
        "adapter_dir": str(adapter),
        "normal_full_config": str(config),
        "normal_full_config_sha256": module.sha256_file(config),
    }
    atoms = [
        {
            "task_id": f"al-{index}",
            "fold": 1,
            "runner_type": "quantile_atom",
            "likelihood_family": "al",
            "normal_task_id": normal["task_id"],
            "normal_task_output": normal["output_dir"],
            "adapter_dir": normal["adapter_dir"],
        }
        for index in range(7)
    ]
    return config, normal, atoms


def test_closeout_resolves_config_through_normal_parent(tmp_path: Path) -> None:
    module = load()
    config, normal, atoms = fixture(module, tmp_path)
    observed, record = module.normal_parent([normal, *atoms], atoms, 1)
    assert observed is normal
    assert record["path"] == str(config.resolve())
    assert record["sha256"] == module.sha256_file(config)
    assert all("normal_full_config" not in atom for atom in atoms)


def test_closeout_rejects_mixed_normal_parent_lineage(tmp_path: Path) -> None:
    module = load()
    _, normal, atoms = fixture(module, tmp_path)
    atoms[-1]["normal_task_id"] = "another-normal"
    with pytest.raises(RuntimeError, match="do not share the normal parent"):
        module.normal_parent([normal, *atoms], atoms, 1)


def test_closeout_rejects_changed_normal_configuration(tmp_path: Path) -> None:
    module = load()
    config, normal, atoms = fixture(module, tmp_path)
    config.write_text("pricefm_desn_full: {changed: true}\n")
    with pytest.raises(RuntimeError, match="configuration hash changed"):
        module.normal_parent([normal, *atoms], atoms, 1)
