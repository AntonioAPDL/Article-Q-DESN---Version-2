"""Tests for Stage-W region/fold-specific PriceFM screening preparation."""

from pathlib import Path
import importlib.util
import json
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


stage_w = load_script("84_prepare_pricefm_stage_w_region_fold_screening.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def template_grid():
    return {
        "pricefm_desn_experiment_grid": {
            "grid_id": "template",
            "purpose": "unit",
            "base": {
                "data_config": "application/config/pricefm_data_pipeline.yaml",
                "full_config": "application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml",
                "generated_root": "old/generated",
                "run_root": "old/run",
            },
            "scope": {
                "regions": ["AA"],
                "folds": [1],
                "quantiles": [0.5],
                "horizons": "all",
                "ranking_split": "val",
                "audit_split": "test",
                "ranking_unit": "original",
                "ranking_metric": "AQL",
            },
            "fixed": {
                "lead_window": 96,
                "feature_map": "window_reservoir_v1",
                "include_intercept": True,
                "shrink_intercept": False,
                "train_origin_limit": 3000,
                "train_origin_selection": "tail",
                "row_chunk_size": 512,
                "projection_scale": 1.0,
                "recurrent_sparsity": 0.05,
                "reservoir_activation": "tanh",
                "state_output": "final_layer",
                "qdesn_likelihoods": ["al", "exal"],
                "artifact_hygiene": {
                    "enabled": True,
                    "clean_adapter_patterns": ["X_*.csv"],
                    "clean_model_patterns": ["*.rds"],
                    "preserve_patterns": ["metric_summary.csv"],
                },
            },
            "launch": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    }


def surface_row(region, fold, delta, feature_policy, *, experiment_id=None):
    info = "target_only" if feature_policy == "target_only" else "pricefm_graph_inputs"
    return {
        "region": region,
        "fold": fold,
        "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
        "model_family": "qdesn_exal",
        "information_set": info,
        "local_AQL": 10.0 + delta,
        "pricefm_AQL": 10.0,
        "delta_abs": delta,
        "delta_rel": delta / 10.0,
        "local_wins": delta < 0.0,
        "decision_label": "local_beats_pricefm" if delta < 0.0 else "pricefm_better",
        "stage_c_quantile_decision": "unit",
        "stage_c_recommendation": "unit",
        "experiment_id": experiment_id or f"current_{region}_{fold}",
        "selected_method_id_median": "qdesn_exal_rhs_ns_exact_chunked",
        "median_selection_AQL": 9.0,
        "median_test_AQL": 10.0 + delta,
        "feature_policy": feature_policy,
        "input_scope": "local_target_only" if feature_policy == "target_only" else "pricefm_graph_khop_degree1",
        "spatial_information_set": "local_only_not_pricefm_graph" if feature_policy == "target_only" else "pricefm_released_graph_khop",
        "graph_degree": "" if feature_policy == "target_only" else 1,
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "seed": 20260629,
        "run_dir": f"/tmp/run_{region}_{fold}",
    }


def matrix_row(region, fold):
    return {
        "region": region,
        "fold": fold,
        "rule_id": "horizon_max_aql_min",
        "source_label": "stage_m_current_cells",
        "experiment_id": f"stage_v_{region}_{fold}",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "val_AQL": 9.0,
        "test_AQL": 10.0,
        "current_validation_AQL": 9.1,
        "current_median_test_AQL": 10.1,
        "pricefm_AQL": 10.0,
        "test_delta_vs_current_median": -0.1,
        "test_delta_vs_stage_m_surface": 0.0,
        "test_delta_vs_pricefm": 0.0,
    }


def make_fixture(tmp_path, *, bad_stage_v=False, duplicate_surface=False):
    root = tmp_path / "fixture"
    out = tmp_path / "out"
    rows = [
        surface_row("AA", 1, 1.1, "target_only"),
        surface_row("BB", 1, 0.5, "graph_khop"),
        surface_row("CC", 1, -0.1, "target_only"),
        surface_row("DD", 1, -0.8, "graph_khop"),
    ]
    for i in range(38):
        rows.append(surface_row(f"ZZ{i:02d}", 1 + i % 3, -1.0, "graph_khop"))
    if duplicate_surface:
        rows[1]["region"] = "AA"
        rows[1]["fold"] = 1
    write_csv(root / "surface.csv", rows)
    write_csv(root / "stage_v_matrix.csv", [matrix_row(r["region"], r["fold"]) for r in rows])
    write_json(root / "stage_v_summary.json", {
        "diagnostic_only": True,
        "fits_models": False,
        "writes_launch_configs": False,
        "stage_m_surface_changed": False,
        "selection_uses_test_metrics_any": True if bad_stage_v else False,
        "recommended_next_stage": "do_not_launch_more_capacity_until_selection_or_graph_model_changes",
    })
    write_yaml(root / "template.yaml", template_grid())
    args = stage_w.parser().parse_args([
        "--stage-m-surface-csv", str(root / "surface.csv"),
        "--stage-v-summary-json", str(root / "stage_v_summary.json"),
        "--stage-v-rule-matrix-csv", str(root / "stage_v_matrix.csv"),
        "--template-grid-config", str(root / "template.yaml"),
        "--output-dir", str(out),
        "--grid-config", str(root / "stage_w.yaml"),
        "--generated-root", str(out / "generated"),
        "--run-root", str(out / "runs"),
        "--max-total-experiments", "120",
        "--write-grid", "false",
    ])
    return args, root, out


def test_stage_w_writes_region_fold_specific_manifest(tmp_path):
    args, _, out = make_fixture(tmp_path)
    summary = stage_w.prepare(args)
    assert summary["status"] == "completed"
    assert summary["selection_is_region_fold_specific"] is True
    assert summary["selection_is_validation_only"] is True
    assert summary["launches_models"] is False
    assert summary["write_grid"] is False

    targets = pd.read_csv(out / "stage_w_target_rows.csv")
    manifest = pd.read_csv(out / "stage_w_experiment_manifest.csv")
    assert set(zip(targets["region"], targets["fold"])) == {("AA", 1), ("BB", 1), ("CC", 1)}
    assert ("DD", 1) not in set(zip(targets["region"], targets["fold"]))
    assert manifest["selection_is_validation_only"].astype(bool).all()
    assert manifest["test_metrics_role"].eq("audit_only").all()
    assert set(manifest["screening_family"]) == {
        "graph_information_conversion",
        "graph_geometry_refinement",
        "local_stability_guard",
    }
    severe = manifest[manifest["region"].eq("AA")]
    assert {"graph_khop", "graph_summary_mean"}.issubset(set(severe["feature_policy"]))


def test_stage_w_can_write_launch_ready_grid(tmp_path):
    args, root, out = make_fixture(tmp_path)
    args.write_grid = True
    summary = stage_w.prepare(args)
    grid_path = root / "stage_w.yaml"
    assert summary["write_grid"] is True
    assert summary["writes_launch_configs"] is True
    assert grid_path.exists()
    payload = yaml.safe_load(grid_path.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["grid_id"] == "pricefm_stage_w_region_fold_screening_20260629"
    assert len(grid["experiments"]) == summary["n_experiments"]
    target_only = [e for e in grid["experiments"] if e["feature_policy"] == "target_only"]
    assert target_only
    assert all("graph_degree" not in e for e in target_only)
    assert grid["fixed"]["artifact_hygiene"]["enabled"] is True
    assert "*.rda" in grid["fixed"]["artifact_hygiene"]["clean_model_patterns"]
    assert grid["launch"]["stage_w_priority0_severe_losses"]["experiment_jobs"] == 20
    assert (out / "stage_w_region_fold_screening_grid.yaml").exists()


def test_stage_w_rejects_stage_v_test_leakage(tmp_path):
    args, _, _ = make_fixture(tmp_path, bad_stage_v=True)
    with pytest.raises(ValueError, match="test metrics"):
        stage_w.prepare(args)


def test_stage_w_rejects_duplicate_stage_m_keys(tmp_path):
    args, _, _ = make_fixture(tmp_path, duplicate_surface=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_w.prepare(args)
