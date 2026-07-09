"""Tests for PriceFM/Q-DESN model-selection parity validation."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd
import pytest
import yaml


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


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def make_fixture(tmp_path, missing_horizon=False, launch_ready=False, missing_method=False):
    bridge = tmp_path / "bridge"
    registry = tmp_path / "registry"
    comp = tmp_path / "comparison_fold{fold}"
    cfg_path = bridge / "configs" / "de_lu_fold2.yaml"
    cfg_path.parent.mkdir(parents=True, exist_ok=True)
    yaml.safe_dump(
        {
            "pipeline": {
                "profile": "pricefm_bridge_dry_run",
                "pricefm_bridge_launch_ready": bool(launch_ready),
            },
            "pricefm_bridge": {
                "region": "DE_LU",
                "fold": 2,
                "package_launch_ready": bool(launch_ready),
            },
            "model_selection": {
                "stages": [
                    {
                        "candidate_grid": {
                            "candidates": [
                                {
                                    "id": "cand_a",
                                    "D": 1,
                                    "n": [120],
                                    "n_tilde": [],
                                    "m": 96,
                                    "alpha": 0.5,
                                    "rho": 0.9,
                                }
                            ]
                        }
                    }
                ]
            },
        },
        cfg_path.open("w"),
        sort_keys=False,
    )
    write_csv(
        bridge / "bridge_manifest.csv",
        [{
            "region": "DE_LU",
            "fold": 2,
            "n_candidates": 1,
            "quantile": 0.5,
            "tau0": 0.001,
            "selection_methods": "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
            "package_launch_ready": bool(launch_ready),
            "config_path": str(cfg_path),
        }],
    )
    write_csv(
        bridge / "bridge_compatibility.csv",
        [{
            "region": "DE_LU",
            "fold": 2,
            "experiment_id": "cand_a",
            "config_path": str(cfg_path),
            "representable_candidate_controls": True,
            "package_launch_ready": bool(launch_ready),
            "blocked_pricefm_controls": "direct_horizon_adapter,fold_horizon_scoring",
        }],
    )
    write_csv(
        registry / "median_selection_registry.csv",
        [{
            "region": "DE_LU",
            "fold": 2,
            "selected_on_split": "val",
            "selected_on_unit": "original",
            "selection_metric": "AQL",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_metric_value": 4.0,
            "experiment_id": "cand_a",
            "test_AQL": 5.0,
        }],
    )
    metric_rows = []
    methods = ["qdesn_exal_rhs_ns_exact_chunked"]
    if not missing_method:
        methods.append("qdesn_al_rhs_ns_exact_chunked")
    for method in methods:
        for split in ["val", "test"]:
            metric_rows.append({
                "region": "DE_LU",
                "fold": 2,
                "experiment_id": "cand_a",
                "method_id": method,
                "split": split,
                "unit": "original",
                "AQL": 4.0 if split == "val" else 5.0,
            })
    write_csv(registry / "median_candidate_metrics.csv", metric_rows)
    write_csv(
        registry / "median_selection_method_coverage.csv",
        [
            {
                "region": "DE_LU",
                "fold": 2,
                "method_id": "qdesn_exal_rhs_ns_exact_chunked",
                "selection_split": "val",
                "selection_unit": "original",
                "selection_metric": "AQL",
                "n_rows": 1,
                "n_finite_metric_rows": 1,
                "covered": True,
            },
            {
                "region": "DE_LU",
                "fold": 2,
                "method_id": "qdesn_al_rhs_ns_exact_chunked",
                "selection_split": "val",
                "selection_unit": "original",
                "selection_metric": "AQL",
                "n_rows": 0 if missing_method else 1,
                "n_finite_metric_rows": 0 if missing_method else 1,
                "covered": not missing_method,
            },
        ],
    )
    comp2 = tmp_path / "comparison_fold2"
    write_csv(
        comp2 / "pricefm_vs_desn_row_alignment_audit.csv",
        [
            {
                "method_id": method,
                "available_prediction_rows": 4,
                "available_unique_response_rows": 2,
                "aligned_prediction_rows": 4,
                "aligned_unique_response_rows": 2,
            }
            for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked", "qdesn_al_rhs_ns_exact_chunked"]
        ],
    )
    write_csv(
        comp2 / "pricefm_vs_desn_metric_summary.csv",
        [
            {"method_id": method, "split": "test", "unit": "original", "AQL": 4.0, "MAE": 8.0, "RMSE": 9.0}
            for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked", "qdesn_al_rhs_ns_exact_chunked"]
        ],
    )
    horizons = [1] if missing_horizon else [1, 2]
    pred_rows = []
    for method in ["pricefm_phase1_pretraining", "qdesn_exal_rhs_ns_exact_chunked", "qdesn_al_rhs_ns_exact_chunked"]:
        for horizon in horizons:
            pred_rows.append({
                "method_id": method,
                "split": "test",
                "origin_market_time": "2025-01-01T00:00:00+00:00",
                "response_market_time": "2025-01-01T00:{:02d}:00+00:00".format(15 * horizon),
                "origin_id": 1,
                "horizon": horizon,
                "tau": 0.5,
                "pred_original": 10.0,
                "y_original": 11.0,
            })
    write_csv(comp2 / "pricefm_vs_desn_predictions_original.csv", pred_rows)
    return bridge, registry, str(comp), tmp_path / "out"


def test_parity_validator_accepts_matching_artifacts(tmp_path):
    mod = load_script("30_validate_qdesn_model_selection_parity.py")
    bridge, registry, comp_template, out = make_fixture(tmp_path)
    result = mod.validate_parity(
        bridge_dir=bridge,
        registry_dir=registry,
        comparison_dir_template=comp_template,
        output_dir=out,
        regions=["DE_LU"],
        folds=[2],
        expected_horizons=[1, 2],
        write=True,
    )
    assert result["summary"]["overall_pass"] is True
    assert (out / "qdesn_model_selection_parity_report.md").exists()
    assert (out / "parity_candidate_match.csv").exists()


def test_parity_validator_rejects_launch_ready_bridge(tmp_path):
    mod = load_script("30_validate_qdesn_model_selection_parity.py")
    bridge, registry, comp_template, out = make_fixture(tmp_path, launch_ready=True)
    with pytest.raises(ValueError, match="bridge_configs_block_launch"):
        mod.validate_parity(
            bridge_dir=bridge,
            registry_dir=registry,
            comparison_dir_template=comp_template,
            output_dir=out,
            regions=["DE_LU"],
            folds=[2],
            expected_horizons=[1, 2],
            write=False,
        )


def test_parity_validator_rejects_missing_method_coverage(tmp_path):
    mod = load_script("30_validate_qdesn_model_selection_parity.py")
    bridge, registry, comp_template, out = make_fixture(tmp_path, missing_method=True)
    with pytest.raises(ValueError, match="method_coverage_complete"):
        mod.validate_parity(
            bridge_dir=bridge,
            registry_dir=registry,
            comparison_dir_template=comp_template,
            output_dir=out,
            regions=["DE_LU"],
            folds=[2],
            expected_horizons=[1, 2],
            write=False,
        )


def test_parity_validator_rejects_missing_horizon(tmp_path):
    mod = load_script("30_validate_qdesn_model_selection_parity.py")
    bridge, registry, comp_template, out = make_fixture(tmp_path, missing_horizon=True)
    with pytest.raises(ValueError, match="row_identity_pass"):
        mod.validate_parity(
            bridge_dir=bridge,
            registry_dir=registry,
            comparison_dir_template=comp_template,
            output_dir=out,
            regions=["DE_LU"],
            folds=[2],
            expected_horizons=[1, 2],
            write=False,
        )
