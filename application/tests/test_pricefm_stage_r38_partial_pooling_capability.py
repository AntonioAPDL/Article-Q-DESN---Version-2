"""Tests for the PriceFM Stage-R38 partial-pooling capability audit."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/163_audit_pricefm_stage_r38_partial_pooling_capability.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def load_module():
    spec = importlib.util.spec_from_file_location("stage_r38", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_csv(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def fixture(tmp_path: Path):
    runs, r37, splits, output = [tmp_path / x for x in ["runs", "r37", "splits", "output"]]
    for case, region in enumerate(["AA", "BB"]):
        model = runs / f"r36_{region}" / "cells" / f"region={region}" / "fold=1" / "model"
        adapter = model.parent / "adapter"
        horizons = np.tile(np.arange(1, 97), 2)
        origins = np.repeat(np.arange(2), 96)
        truth = np.sin(horizons / 8.0)
        shared = truth + np.where(horizons <= 48, 0.2, -0.05)
        separate = truth + np.where(horizons <= 48, -0.05, 0.2)
        rows = []
        for method, values in [("qdesn_al_rhs_ns_exact_chunked", shared), ("qdesn_al_rhs_ns_exact_chunked_horizon_separate", separate)]:
            rows += [{"method_id": method, "split": "val", "origin_id": o, "horizon": h, "tau": 0.5, "pred_scaled": v} for o, h, v in zip(origins, horizons, values)]
        write_csv(model / "model_predictions_scaled.csv", rows)
        write_csv(adapter / "rows_val.csv", [{"origin_id": o, "horizon": h, "y_scaled": y} for o, h, y in zip(origins, horizons, truth)])
    inner = []
    for region in ["AA", "BB"]:
        for fold in [1, 2, 3]:
            inner.append({"region": region, "fold": 1, "inner_fold": fold, "method_id": "qdesn_al_rhs_ns_exact_chunked_horizon_separate", "converged": not (region == "BB" and fold == 1)})
    write_csv(r37 / "pricefm_stage_r37_inner_fold_metrics.csv", inner)
    (r37 / "summary.json").write_text(json.dumps({"status": "completed_read_only_no_confirmation_candidates"}))
    for fold in [1, 2, 3]:
        path = splits / f"fold_{fold}" / "test.parquet"
        path.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame({"time_utc": pd.date_range("2025-09-01", periods=4, tz="UTC")}).to_parquet(path, index=False)
    return runs, r37, splits, output


def test_r38_materializes_oracle_headroom_without_authorizing_selection(tmp_path):
    module = load_module()
    paths = fixture(tmp_path)
    args = module.parser().parse_args([
        "--stage-r36-run-root", str(paths[0]), "--stage-r37-dir", str(paths[1]),
        "--split-root", str(paths[2]), "--output-dir", str(paths[3]),
        "--expected-cases", "2", "--force", "true",
    ])
    summary = module.run(args)
    assert summary["block_blend_headroom_cases"] == 2
    assert summary["r39_implementation_justified"] is True
    assert summary["post_2025_observations_available"] is False
    assert summary["launch_authorized"] is False
    atlas = pd.read_csv(paths[3] / "pricefm_stage_r38_partial_pooling_capability_atlas.csv")
    assert atlas["partial_pooling_headroom_observed"].all()
    assert not atlas["test_inspected"].any()
    gates = pd.read_csv(paths[3] / "pricefm_stage_r38_decision_gates.csv").set_index("gate")
    assert bool(gates.loc["r39_model_implementation_justified", "passed"])
    assert not bool(gates.loc["fresh_confirmation_data_ready", "passed"])


def test_r38_rejects_incomplete_prediction_surface(tmp_path):
    module = load_module()
    paths = fixture(tmp_path)
    prediction = next(paths[0].glob("*/cells/*/*/model/model_predictions_scaled.csv"))
    frame = pd.read_csv(prediction)
    frame = frame[~((frame["method_id"].str.endswith("horizon_separate")) & (frame["horizon"] == 96))]
    frame.to_csv(prediction, index=False)
    args = module.parser().parse_args([
        "--stage-r36-run-root", str(paths[0]), "--stage-r37-dir", str(paths[1]),
        "--split-root", str(paths[2]), "--output-dir", str(paths[3]),
        "--expected-cases", "2", "--force", "true",
    ])
    try:
        module.run(args)
    except ValueError as exc:
        assert "Incomplete paired prediction surface" in str(exc)
    else:
        raise AssertionError("Expected incomplete paired predictions to fail closed")
