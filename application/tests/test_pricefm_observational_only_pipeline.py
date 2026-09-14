"""Focused tests for train/validation-only PriceFM data preparation."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import configured_split_names  # noqa: E402


def load_script(filename: str):
    path = SCRIPT_DIR / filename
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_train_validation_only_scaling_and_context():
    scaler = load_script("04_fit_scalers.py")
    windows = load_script("05_build_windows.py")
    split_spec = {
        "fold": 101,
        "train": ["2022-01-01", "2023-01-01"],
        "val": ["2023-01-01", "2023-02-01"],
    }
    assert configured_split_names(split_spec) == ["train", "val"]

    frames = {
        "train": pd.DataFrame({"SE_2-load": [1.0, 2.0, 4.0], "SE_2-price": [2.0, 4.0, 8.0]}),
        "val": pd.DataFrame({"SE_2-load": [3.0], "SE_2-price": [6.0]}),
    }
    scaled, fitted = scaler.fit_transform_scalers_per_region(
        frames, ["SE_2"], ["load"], ["price"]
    )
    assert list(scaled) == ["train", "val"]
    assert "SE_2" in fitted
    context, name = windows.build_context(scaled, "val")
    assert name == "train+val"
    assert len(context) == 4


def test_grid_runner_deduplicates_observational_data_prep(monkeypatch, tmp_path):
    runner = load_script("13_run_desn_experiment_grid.py")
    data_config = tmp_path / "data.yaml"
    processed = tmp_path / "processed_r93"
    data_config.write_text(yaml.safe_dump({
        "pricefm": {
            "interim_dir": str(tmp_path / "interim"),
            "processed_dir": str(processed),
            "regions": ["SE_2"],
            "scaling": {"mode": "per_region_separate_xy", "fit_on": "train_only"},
            "splits": [
                {"fold": 101, "train": ["2022-01-01", "2023-01-01"], "val": ["2023-01-01", "2023-02-01"]},
                {"fold": 102, "train": ["2022-01-01", "2023-02-01"], "val": ["2023-02-01", "2023-03-01"]},
            ],
        }
    }, sort_keys=False))
    rows = [{"data_config": str(data_config)}, {"data_config": str(data_config)}]
    jobs = runner.data_preparation_jobs(rows)
    assert len(jobs) == 1
    raw, scaled = runner.data_artifact_paths(jobs[0])
    assert all("test" not in path.name for path in raw + scaled)
    assert len([path for path in raw if path.suffix == ".parquet"]) == 4
    assert len([path for path in scaled if path.suffix == ".parquet"]) == 4

    captured = []

    def fake_sequence(commands, log_path, dry_run=False):
        captured.extend(commands)
        return {"status": "completed", "return_code": 0, "elapsed_seconds": 0.1}

    monkeypatch.setattr(runner, "run_logged_sequence", fake_sequence)
    status = runner.prepare_data_for_rows(rows, tmp_path / "logs", dry_run=False)
    assert len(status) == 1
    assert status[0]["status"] == "completed"
    assert [Path(command[1]).name for command in captured] == [
        "03_make_splits.py", "04_fit_scalers.py",
    ]
