import csv
import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/165_cleanup_pricefm_legacy_run_artifacts.py"


def load_module():
    spec = importlib.util.spec_from_file_location("cleanup", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_selected_experiments_and_ledger_preserve_winner(tmp_path):
    module = load_module()
    data_root = tmp_path / "pricefm"
    run_tag = "pricefm_stage_r33_lean_capacity_history_20260722"
    winner = data_root / "runs" / run_tag / "winner" / "cells" / "model"
    loser = data_root / "runs" / run_tag / "loser" / "cells" / "model"
    winner.mkdir(parents=True)
    loser.mkdir(parents=True)
    (winner / "model_predictions_scaled.csv").write_text("keep")
    (loser / "model_predictions_scaled.csv").write_text("delete")
    (loser / "metric_summary.csv").write_text("keep")
    rows = module.build_ledger(data_root, {"winner"})
    assert [Path(row["path"]).name for row in rows] == ["model_predictions_scaled.csv"]
    assert rows[0]["experiment_id"] == "loser"


def test_selected_manifest_parser(tmp_path):
    module = load_module()
    path = tmp_path / "selected.csv"
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["experiment_id"])
        writer.writeheader()
        writer.writerow({"experiment_id": "a"})
        writer.writerow({"experiment_id": "b"})
    assert module.selected_experiments(path) == {"a", "b"}


def test_cleanup_allowlist_excludes_scientific_summaries():
    module = load_module()
    assert "metric_summary.csv" not in module.PRUNABLE_NAMES
    assert "run_manifest.json" not in module.PRUNABLE_NAMES
    assert "model_predictions_scaled.csv" in module.PRUNABLE_NAMES
    assert ".rds" not in module.PRUNABLE_SUFFIXES


def test_load_ledger_rejects_path_outside_allowed_roots(tmp_path):
    module = load_module()
    ledger = tmp_path / "ledger.csv"
    fields = [
        "run_tag", "policy", "experiment_id", "selected_by_r34", "path",
        "size_bytes", "sha256", "action", "applied",
    ]
    with ledger.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerow({
            "run_tag": "bad", "policy": "bad", "experiment_id": "bad",
            "selected_by_r34": "False", "path": str(tmp_path / "rows_all.csv"),
            "size_bytes": 0, "sha256": "x", "action": "delete", "applied": "False",
        })
    try:
        module.load_ledger(ledger, tmp_path / "pricefm")
    except RuntimeError as error:
        assert "escapes allowed run roots" in str(error)
    else:
        raise AssertionError("Unsafe ledger path was accepted")
