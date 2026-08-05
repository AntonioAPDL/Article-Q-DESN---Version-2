"""Tests for PriceFM Stage-R36 nested horizon-readout launch preparation."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pandas as pd
import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


def load_script():
    path = SCRIPT_DIR / "161_prepare_pricefm_stage_r36_nested_horizon_readout_launch.py"
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def selected_row(region: str, fold: int, experiment_id: str, method_id: str = "qdesn_al_rhs_ns_exact_chunked") -> dict:
    return {
        "experiment_id": experiment_id,
        "region": region,
        "fold": fold,
        "feature_policy": "graph_summary_mean_std",
        "lag_window": 96,
        "depth": 2,
        "n_per_layer": 48,
        "units": "[48, 48]",
        "feature_dim": 48,
        "state_output": "final_layer",
        "alpha": 0.2,
        "rho": 0.95,
        "input_scale": 0.2,
        "tau0": 1.0e-4,
        "seed": 20260804 + fold,
        "horizon_weighting_enabled": True,
        "horizon_weighting_mode": "integer_frequency_replication",
        "horizon_focus": "25-48",
        "horizon_weight_multiplier": 2.0,
        "graph_degree": 1,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": "abc",
        "neighbor_regions": '["DE_LU"]',
        "target_lag_features": '["price", "load", "solar", "wind"]',
        "target_lead_features": '["load", "solar", "wind"]',
        "neighbor_lag_features": '["price", "load"]',
        "neighbor_lead_features": '["load", "wind"]',
        "summary_stats": '["neighbor_mean", "neighbor_sd"]',
        "max_neighbor_regions": 1,
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_summary_mean_std",
        "input_scope": "pricefm_graph_summary_mean_std_degree1_n1",
        "method_id": method_id,
        "selection_is_validation_only": True,
        "selection_rule": "validation_AQL_only_within_case",
    }


def fixture(tmp_path: Path):
    r35 = tmp_path / "r35"
    r34 = tmp_path / "r34"
    output = tmp_path / "prep"
    grid = tmp_path / "grid"
    runs = tmp_path / "runs"
    write_json(r35 / "summary.json", {
        "status": "completed_read_only_new_mechanism_required",
        "r34_cases": 2,
    })
    pd.DataFrame([
        {
            "region": "NO_4",
            "fold": 1,
            "stage_r35_priority": 0,
            "stage_r35_queue": "priority0_current_qdesn_harm_guard",
            "protect_current_qdesn": True,
            "existing_test_role": "quarantined_audit_not_selection",
        },
        {
            "region": "NO_4",
            "fold": 2,
            "stage_r35_priority": 1,
            "stage_r35_queue": "priority1_near_gap_new_mechanism_qualification",
            "protect_current_qdesn": False,
            "existing_test_role": "quarantined_audit_not_selection",
        },
    ]).to_csv(r35 / "pricefm_stage_r35_case_specific_next_queue.csv", index=False)
    write_json(r34 / "summary.json", {"status": "completed_no_promotions"})
    pd.DataFrame([
        selected_row("NO_4", 1, "r34_no4_f1"),
        selected_row("NO_4", 2, "r34_no4_f2", "qdesn_exal_rhs_ns_exact_chunked"),
    ]).to_csv(r34 / "pricefm_stage_r34_validation_selected_cases.csv", index=False)
    return r35, r34, output, grid, runs


def args_for(mod, r35: Path, r34: Path, output: Path, grid: Path, runs: Path):
    return mod.parser().parse_args([
        "--stage-r35-dir", str(r35),
        "--stage-r34-dir", str(r34),
        "--output-dir", str(output),
        "--grid-generated-root", str(grid),
        "--run-root", str(runs),
        "--artifact-repo-root", str(ROOT),
        "--base-data-config", str(ROOT / "application" / "config" / "pricefm_data_pipeline.yaml"),
        "--base-full-config", str(
            ROOT
            / "application"
            / "config"
            / "pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml"
        ),
        "--python-bin", "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python",
        "--expected-targets", "2",
        "--expected-harm-guards", "1",
        "--experiment-jobs", "2",
        "--authorize-launch", "true",
        "--force", "true",
    ])


def test_stage_r36_materializes_case_specific_test_quarantined_launch(monkeypatch, tmp_path):
    mod = load_script()
    r35, r34, output, grid, runs = fixture(tmp_path)
    monkeypatch.setattr(mod, "missing_window_files", lambda *args, **kwargs: [])
    summary = mod.run(args_for(mod, r35, r34, output, grid, runs))

    assert summary["status"] == "completed_launch_ready"
    assert summary["n_cases"] == 2
    assert summary["n_harm_guards"] == 1
    assert summary["existing_test_loaded"] is False
    assert summary["readout_modes"] == ["shared_static", "separate_horizon_block"]
    manifest = pd.read_csv(output / "pricefm_stage_r36_launch_manifest.csv")
    assert len(manifest) == 2
    assert manifest["mechanism_qualification_only"].map(bool).all()
    assert not manifest["mutates_registry"].map(bool).any()
    assert not manifest["mutates_manuscript"].map(bool).any()
    assert manifest["configured_splits"].eq('["train", "val"]').all()
    assert set(manifest["source_r34_selected_method"]) == {
        "qdesn_al_rhs_ns_exact_chunked",
        "qdesn_exal_rhs_ns_exact_chunked",
    }
    gates = pd.read_csv(output / "pricefm_stage_r36_launch_prep_gates.csv")
    assert gates["passed"].map(bool).all()
    assert (output / "pricefm_stage_r36_nested_horizon_readout_grid.yaml").exists()
    assert (grid / "manifest.csv").exists()

    for full_path in manifest["full_config"]:
        full = yaml.safe_load(Path(full_path).read_text())["pricefm_desn_full"]
        assert full["scope"]["splits"] == ["train", "val"]
        assert full["qdesn_vb"]["likelihoods"] == ["al"]
        assert full["qdesn_vb"]["readout_modes"] == ["shared_static", "separate_horizon_block"]
        assert full["adapter"]["readout_interaction"] == "none"
        assert full["nested_validation"]["n_folds"] == 3
        assert full["normal"]["enabled"] is False
        assert full["exact_equivalence"]["enabled"] is False


def test_stage_r36_rejects_non_validation_r34_anchor(monkeypatch, tmp_path):
    mod = load_script()
    r35, r34, output, grid, runs = fixture(tmp_path)
    selected = pd.read_csv(r34 / "pricefm_stage_r34_validation_selected_cases.csv")
    selected.loc[0, "selection_is_validation_only"] = False
    selected.to_csv(r34 / "pricefm_stage_r34_validation_selected_cases.csv", index=False)
    monkeypatch.setattr(mod, "missing_window_files", lambda *args, **kwargs: [])
    with pytest.raises(ValueError, match="not selected validation-only"):
        mod.run(args_for(mod, r35, r34, output, grid, runs))
