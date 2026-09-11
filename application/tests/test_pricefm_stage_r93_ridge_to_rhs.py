"""Focused tests for the R93 validation-only Ridge-to-RHS handoff."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
SCRIPT = SCRIPT_DIR / "292_advance_pricefm_stage_r93_ridge_to_rhs.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_yaml(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def fixture(tmp_path: Path, *, include_test: bool = False, fail_candidate: str = ""):
    prep = tmp_path / "prep"
    generated = tmp_path / "ridge_generated"
    output = tmp_path / "output"
    rhs_generated = tmp_path / "rhs_generated"
    rhs_runs = tmp_path / "rhs_runs"
    runs = tmp_path / "ridge_runs"
    prep.mkdir()
    generated.mkdir()

    candidate_rows = []
    experiments = []
    manifest_rows = []
    for index in range(1, 6):
        candidate_id = f"candidate_{index:02d}"
        role = "authoritative_fold_geometry_control" if index <= 3 else "bounded_space_filling_search"
        candidate_rows.append({
            "candidate_id": candidate_id,
            "candidate_role": role,
            "source_fold": index if index <= 3 else "",
            "source_experiment_id": f"source_{index}" if index <= 3 else "",
            "region": "SE_2",
            "feature_policy": "target_only" if index < 5 else "graph_summary_mean",
            "lag_window": 48 + index,
            "depth": 2,
            "units": json.dumps([index * 8, index * 8]),
            "feature_dim": index * 8,
            "alpha": 0.2,
            "rho": 0.9,
            "input_scale": 0.2,
            "state_output": "final_layer",
            "seed": 100 + index,
            "semantic_fingerprint": f"fingerprint_{index}",
            "test_access_authorized": False,
        })
        experiments.append({
            "id": candidate_id, "stage": "ridge", "priority": 0,
            "regions": ["SE_2"], "folds": [101, 102], "quantiles": [0.1, 0.5, 0.9],
            "lag_window": 48 + index, "feature_map": "window_reservoir_v1",
            "feature_policy": candidate_rows[-1]["feature_policy"], "feature_dim": index * 8,
            "depth": 2, "units": [index * 8, index * 8], "alpha": 0.2,
            "rho": 0.9, "input_scale": 0.2, "state_output": "final_layer",
            "tau0": 0.001, "seed": 100 + index,
            "normal": {"enabled": True, "prior_types": ["scaled_ridge"]},
            "qdesn_vb": {"enabled": False},
        })
        run_dir = runs / candidate_id
        manifest_rows.append({"id": candidate_id, "run_dir": str(run_dir)})
        for fold in (101, 102):
            model = run_dir / "cells" / "region=SE_2" / f"fold={fold}" / "model"
            model.mkdir(parents=True)
            score = float(10 - index + (fold - 101) * 0.2)
            metrics = [{
                "method_id": "normal_scaled_ridge", "split": "val",
                "unit": "original", "AQL": score,
            }]
            if include_test and index == 1 and fold == 101:
                metrics.append({
                    "method_id": "normal_scaled_ridge", "split": "test",
                    "unit": "original", "AQL": 0.1,
                })
            pd.DataFrame(metrics).to_csv(model / "metric_summary.csv", index=False)
            pd.DataFrame([{
                "method_id": "normal_scaled_ridge",
                "converged": candidate_id != fail_candidate,
                "n_features": index * 8 + 1,
            }]).to_csv(model / "model_method_summary.csv", index=False)

    pd.DataFrame(candidate_rows).to_csv(
        prep / "pricefm_stage_r93_ridge_candidate_manifest.csv", index=False
    )
    pd.DataFrame(manifest_rows).to_csv(generated / "manifest.csv", index=False)
    data = tmp_path / "base_data.yaml"
    full = tmp_path / "base_full.yaml"
    write_yaml(data, {"pricefm": {"splits": [], "windows": {}, "pilot": {}}})
    write_yaml(full, {"pricefm_desn_full": {
        "data_config": str(data), "scope": {}, "adapter": {}, "run": {}, "rhs_ns": {},
        "normal": {}, "qdesn_vb": {}, "exact_equivalence": {},
    }})
    ridge_grid = prep / "pricefm_stage_r93_ridge_grid.yaml"
    write_yaml(ridge_grid, {"pricefm_desn_experiment_grid": {
        "grid_id": "ridge_fixture", "purpose": "fixture",
        "base": {"data_config": str(data), "full_config": str(full),
                 "generated_root": str(generated), "run_root": str(runs)},
        "scope": {"regions": ["SE_2"], "folds": [101, 102],
                  "splits": ["train", "val"], "quantiles": [0.1, 0.5, 0.9]},
        "fixed": {"normal": {"prior_types": ["scaled_ridge"]},
                  "qdesn_vb": {"enabled": False}},
        "launch": {}, "experiments": experiments, "experiment_blocks": [],
    }})
    return prep, generated, output, rhs_generated, rhs_runs


def args_for(module, tmp_path: Path, **kwargs):
    prep, generated, output, rhs_generated, rhs_runs = fixture(tmp_path, **kwargs)
    return module.parser().parse_args([
        "--prep-dir", str(prep), "--ridge-generated-root", str(generated),
        "--output-dir", str(output), "--rhs-generated-root", str(rhs_generated),
        "--rhs-run-root", str(rhs_runs), "--folds", "101,102",
        "--expected-candidates", "5", "--top-k", "2",
        "--tau0-values", "1e-4,1e-3,1e-2", "--allow-fixture-counts",
    ])


def test_ridge_closeout_selects_validation_top_k_and_prepares_rhs(tmp_path):
    module = load_script()
    args = args_for(module, tmp_path)
    summary = module.run(args)
    assert summary["status"] == "completed_rhs_prepared_not_launched"
    assert summary["ridge_cell_results"] == 10
    assert summary["ridge_top_k"] == 2
    assert summary["rhs_experiments"] == 6
    assert summary["planned_rhs_fits"] == 12
    assert summary["launcher_invoked"] is False

    ranking = pd.read_csv(args.output_dir / "pricefm_stage_r93_ridge_validation_ranking.csv")
    assert ranking.candidate_id.tolist()[:2] == ["candidate_05", "candidate_04"]
    assert not ranking.test_metrics_loaded_or_used.map(bool).any()
    rhs = pd.read_csv(args.output_dir / "pricefm_stage_r93_rhs_coarse_launch_manifest.csv")
    assert set(rhs.parent_ridge_candidate_id) == {"candidate_04", "candidate_05"}
    assert set(rhs.tau0.round(7)) == {0.0001, 0.001, 0.01}
    assert set(rhs.feature_dim) == {32, 40}
    assert not rhs.launch_authorized.map(bool).any()

    grid = yaml.safe_load(
        (args.output_dir / "pricefm_stage_r93_rhs_grid.yaml").read_text()
    )["pricefm_desn_experiment_grid"]
    assert grid["scope"]["splits"] == ["train", "val"]
    assert grid["fixed"]["normal"]["prior_types"] == ["rhs_ns"]
    assert grid["fixed"]["normal"]["predictive_quantile_mode"] == "analytic_normal"
    assert grid["fixed"]["qdesn_vb"]["enabled"] is False
    assert grid["launch"]["prepared_not_authorized"]["authorized"] is False
    assert len(grid["experiments"]) == 6


def test_ridge_closeout_rejects_test_contamination(tmp_path):
    module = load_script()
    args = args_for(module, tmp_path, include_test=True)
    with pytest.raises(RuntimeError, match="test metrics are forbidden"):
        module.run(args)


def test_ridge_closeout_rejects_nonconvergence(tmp_path):
    module = load_script()
    args = args_for(module, tmp_path, fail_candidate="candidate_03")
    with pytest.raises(RuntimeError, match="not converged"):
        module.run(args)


def test_source_fold_parser_accepts_csv_integer_floats_and_rejects_fractions():
    module = load_script()
    assert module.parse_source_folds(["1;3", 2.0, "2.000"]) == [1, 2, 3]
    with pytest.raises(RuntimeError, match="not integer-like"):
        module.parse_source_folds([1.5])
