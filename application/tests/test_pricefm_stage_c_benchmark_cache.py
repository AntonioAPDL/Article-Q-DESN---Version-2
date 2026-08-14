"""Tests for Stage-C PriceFM benchmark-cache preparation."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import pandas as pd


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


def args(tmp_path, *, dry_run=True):
    return SimpleNamespace(
        registry_csv=str(tmp_path / "registry.csv"),
        output_root=str(tmp_path / "cache"),
        config="application/config/pricefm_data_pipeline.yaml",
        pricefm_python="application/data_local/pricefm/venv_pricefm_tf/bin/python",
        regions=None,
        folds=None,
        quantiles="0.10,0.50,0.90",
        splits="test",
        window_mode="operational",
        batch_size=128,
        jobs=1,
        resume=True,
        force=False,
        dry_run=dry_run,
        grid_id="unit_stage_c_cache",
    )


def write_registry(tmp_path, rows=None):
    if rows is None:
        rows = [
            {"region": "BE", "fold": 1},
            {"region": "BE", "fold": 2},
        ]
    pd.DataFrame(rows).to_csv(tmp_path / "registry.csv", index=False)


def write_cache_files(root, region="BE", fold=1):
    mod = load_script("54_prepare_pricefm_stage_c_benchmark_cache.py")
    path = root / f"region={region}" / f"fold={fold}"
    path.mkdir(parents=True)
    for name in mod.REQUIRED_CACHE_FILES:
        (path / name).write_text("x\n1\n")
    return path


def test_stage_c_benchmark_cache_dry_run_records_planned_rows(tmp_path):
    mod = load_script("54_prepare_pricefm_stage_c_benchmark_cache.py")
    write_registry(tmp_path)

    summary = mod.prepare_cache(args(tmp_path, dry_run=True))
    status = pd.read_csv(tmp_path / "cache" / "pricefm_stage_c_benchmark_cache_status.csv")

    assert summary["status"] == "planned"
    assert summary["n_region_folds"] == 2
    assert set(status["status"]) == {"planned_run"}
    assert "17_run_pricefm_phase1_predictions.py" in status["command"].iloc[0]
    assert "pricefm_stage_c_benchmark_cache_report.md" in summary["outputs"]["report"]


def test_stage_c_benchmark_cache_dry_run_detects_existing_cache(tmp_path):
    mod = load_script("54_prepare_pricefm_stage_c_benchmark_cache.py")
    write_registry(tmp_path, [{"region": "BE", "fold": 1}])
    write_cache_files(tmp_path / "cache", "BE", 1)

    summary = mod.prepare_cache(args(tmp_path, dry_run=True))
    status = pd.read_csv(tmp_path / "cache" / "pricefm_stage_c_benchmark_cache_status.csv")

    assert summary["status"] == "planned"
    assert status["status"].iloc[0] == "planned_cached"
    assert bool(status["cache_complete_after"].iloc[0])


def test_stage_c_benchmark_cache_rejects_duplicate_region_folds(tmp_path):
    mod = load_script("54_prepare_pricefm_stage_c_benchmark_cache.py")
    write_registry(tmp_path, [
        {"region": "BE", "fold": 1},
        {"region": "BE", "fold": 1},
    ])

    try:
        mod.prepare_cache(args(tmp_path, dry_run=True))
    except ValueError as exc:
        assert "duplicate region/fold" in str(exc)
    else:
        raise AssertionError("duplicate region/fold rows should fail")


def test_stage_c_benchmark_cache_missing_files_are_reported(tmp_path):
    mod = load_script("54_prepare_pricefm_stage_c_benchmark_cache.py")
    out = tmp_path / "cache" / "region=BE" / "fold=1"
    out.mkdir(parents=True)
    (out / "pricefm_phase1_metrics.csv").write_text("x\n1\n")

    missing = mod.cache_missing_files(out)

    assert "pricefm_phase1_predictions_original.csv" in missing
    assert not mod.cache_complete(out)
