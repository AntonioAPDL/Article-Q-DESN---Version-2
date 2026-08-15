"""Tests for Stage-U PriceFM parity audit."""

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


stage_u = load_script("82_audit_pricefm_parity_contract.py")


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


def pricefm_config(processed_dir):
    return {
        "pricefm": {
            "processed_dir": str(processed_dir),
            "market_time_definition": "time_utc + 1 hour",
            "features": {
                "label": "price",
                "raw": ["generation", "load", "price", "solar", "wind"],
                "lag": ["price", "load", "solar", "wind"],
                "lead": ["load", "solar", "wind"],
            },
            "scaling": {
                "mode": "per_region_separate_xy",
                "scaler": "RobustScaler",
                "fit_on": "train_only",
            },
            "windows": {
                "lag_window": 96,
                "lead_window": 96,
                "train_boundary_mode": "contained_half_open",
                "validation_boundary_mode": "operational_half_open",
                "test_boundary_mode": "operational_half_open",
            },
        }
    }


def cell_config(region, fold, feature_policy, run_dir, *, seed=20260629):
    return {
        "pricefm_desn_smoke": {
            "region": region,
            "fold": int(fold),
            "horizons": list(range(1, 97)),
            "quantiles": [0.5],
            "feature_policy": feature_policy,
            "adapter": {
                "output_dir": str(run_dir / "cells" / f"region={region}" / f"fold={fold}" / "adapter"),
                "feature_map": "window_reservoir_v1",
                "feature_dim": 120,
                "seed": seed,
                "include_intercept": True,
                "projection_scale": 0.5,
                "depth": 1,
                "units": [120],
                "alpha": 0.4,
                "rho": 0.9,
                "input_scale": 0.25,
            },
        }
    }


def feature_manifest(region, feature_policy):
    graph = {}
    input_scope = "local_target_only"
    spatial = "local_only_not_pricefm_graph"
    active = [region]
    if feature_policy == "graph_khop":
        active = [region, "BB"]
        input_scope = "pricefm_graph_khop"
        spatial = "pricefm_released_graph_khop"
        graph = {
            "active_regions": active,
            "graph_degree": 1,
            "graph_hash": "abc123",
            "graph_source": "PriceFM.graph_adj_matrix",
            "n_active_regions": len(active),
            "target_region": region,
        }
    return {
        "feature_dim": 120,
        "feature_map": "window_reservoir_v1",
        "feature_names": ["intercept", "x1"],
        "feature_policy": feature_policy,
        "seed": 20260629,
        "feature_policy_manifest": {
            "feature_policy": feature_policy,
            "graph": graph,
            "input_scope": input_scope,
            "lead_covariate_status": "realized_ex_post",
            "output_scope": "target_region_path",
            "source_windows": [],
            "spatial_information_set": spatial,
        },
    }


def window_manifest(split):
    boundary = "contained_half_open" if split == "train" else "operational_half_open"
    context = {"train": "train", "val": "train+val", "test": "train+val+test"}[split]
    n_origins = {"train": 10, "val": 3, "test": 4}[split]
    return {
        "split": split,
        "context": context,
        "boundary_mode": boundary,
        "X_lag_shape": [n_origins, 96, 4],
        "X_lead_shape": [n_origins, 96, 3],
        "Y_shape": [n_origins, 96],
        "lag_features": ["price", "load", "solar", "wind"],
        "lead_features": ["load", "solar", "wind"],
        "market_time_definition": "time_utc + 1 hour",
        "n_origins": n_origins,
    }


def make_cell(root, region, fold, feature_policy, *, omit_test_window=False):
    run_dir = root / f"run_{region}_{fold}"
    cell = run_dir / "cells" / f"region={region}" / f"fold={fold}"
    write_yaml(cell / "config.yaml", cell_config(region, fold, feature_policy, run_dir))
    write_json(cell / "adapter" / "adapter_manifest.json", {
        "region": region,
        "fold": int(fold),
        "horizons": list(range(1, 97)),
        "quantiles": [0.5],
        "layout": "stacked_origin_by_horizon",
        "splits": {"train": {}, "val": {}, "test": {}},
    })
    write_json(cell / "adapter" / "feature_manifest.json", feature_manifest(region, feature_policy))
    method_id = "qdesn_exal_rhs_ns_exact_chunked"
    metric_rows = []
    for unit in ["original", "scaled"]:
        metric_rows.append({
            "method_id": method_id,
            "split": "test",
            "unit": unit,
            "AQL": 7.5,
            "AQCR": 0.8,
            "MAE": 15.0,
            "RMSE": 20.0,
        })
    write_csv(cell / "model" / "metric_summary.csv", metric_rows)
    write_csv(cell / "model" / "metric_by_horizon_group.csv", [
        {
            "method_id": method_id,
            "split": "test",
            "unit": "original",
            "horizon_group": group,
            "AQL": 5.0 + i,
            "AQCR": 0.8,
            "MAE": 10.0 + i,
            "RMSE": 15.0 + i,
        }
        for i, group in enumerate(["1-24", "25-48", "49-72", "73-96"])
    ])
    write_csv(cell / "model" / "model_method_summary.csv", [{
        "method_id": method_id,
        "model_family": "qdesn_static_readout",
        "converged": True,
        "iter": 50,
        "n_train": 960,
        "n_features": 120,
    }])
    return run_dir, (None if omit_test_window else method_id)


def make_fixture(tmp_path, *, bad_stage_t=False, duplicate_surface=False, omit_test_window=False):
    root = tmp_path / "fixture"
    out = tmp_path / "out"
    processed = root / "processed"
    config = root / "pricefm.yaml"
    write_yaml(config, pricefm_config(processed))
    write_json(root / "stage_t_summary.json", {
        "diagnostic_only": True,
        "writes_launch_configs": False,
        "fits_models": False,
        "recommended_next_stage": (
            "not_this" if bad_stage_t
            else "pricefm_information_set_transform_horizon_parity_audit"
        ),
    })
    write_csv(root / "paper.txt", [{"text": "placeholder"}])
    (root / "pipeline.md").write_text("RobustScaler generation quantile graph 96", encoding="utf-8")
    (root / "paper_body.txt").write_text("Price load solar wind graph quantile 96", encoding="utf-8")

    surface = []
    for region, fold, feature_policy, delta in [
        ("AA", 1, "target_only", -0.1),
        ("BB", 1, "graph_khop", 0.5),
    ]:
        run_dir, _ = make_cell(root, region, fold, feature_policy)
        surface.append({
            "region": region,
            "fold": fold,
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "model_family": "qdesn_exal",
            "information_set": "pricefm_graph_inputs" if feature_policy == "graph_khop" else "target_only",
            "local_AQL": 7.5,
            "pricefm_AQL": 7.0,
            "delta_abs": delta,
            "feature_policy": feature_policy,
            "spatial_information_set": "pricefm_released_graph_khop" if feature_policy == "graph_khop" else "local_only_not_pricefm_graph",
            "lag_window": 96,
            "run_dir": str(run_dir),
        })
    if duplicate_surface:
        surface[1]["region"] = "AA"
    write_csv(root / "surface.csv", surface)

    for fold in [1]:
        write_json(processed / "scalers" / f"fold_{fold}" / "scaling_manifest.json", {
            "fold": fold,
            "scaling_mode": "per_region_separate_xy",
            "scaler": "sklearn.preprocessing.RobustScaler",
            "fit_on": "training split only",
            "x_features": ["load", "solar", "wind"],
            "y_features": ["price"],
            "regions": ["AA", "BB"],
        })
    for region in ["AA", "BB"]:
        for split in ["train", "val", "test"]:
            if omit_test_window and region == "BB" and split == "test":
                continue
            boundary = "contained_half_open" if split == "train" else "operational_half_open"
            path = processed / "windows" / "fold_1" / f"region={region}" / f"{split}_L96_H96_{boundary}.manifest.json"
            write_json(path, window_manifest(split))

    return [
        "--stage-m-surface-csv", str(root / "surface.csv"),
        "--stage-t-summary-json", str(root / "stage_t_summary.json"),
        "--pricefm-config", str(config),
        "--pipeline-report", str(root / "pipeline.md"),
        "--paper-text", str(root / "paper_body.txt"),
        "--output-dir", str(out),
        "--expected-region-folds", "2",
    ], out


def test_stage_u_audit_generates_contract_outputs(tmp_path):
    argv, out = make_fixture(tmp_path)
    summary = stage_u.summarize(stage_u.parser().parse_args(argv))

    assert summary["diagnostic_only"] is True
    assert summary["writes_launch_configs"] is False
    assert summary["fits_models"] is False
    assert summary["stage_m_rows"] == 2
    assert summary["row_parity_passes"] == 1
    assert summary["row_parity_warnings"] == 1
    assert summary["row_parity_failures"] == 0
    assert summary["hard_parity_failures"] == 0
    assert summary["recommended_next_stage"] == "horizon_aware_validation_contract_after_parity"
    assert (out / "stage_u_row_parity_matrix.csv").exists()
    assert (out / "stage_u_window_contract.csv").exists()
    assert (out / "stage_u_parity_audit_report.md").exists()

    parity = pd.read_csv(out / "stage_u_row_parity_matrix.csv")
    assert set(parity["parity_status"]) == {"pass", "warn"}
    graph = parity[parity["feature_policy"].eq("graph_khop")].iloc[0]
    assert "not the PriceFM joint" in graph["structural_caveat"]


def test_stage_u_rejects_wrong_stage_t_recommendation(tmp_path):
    argv, _ = make_fixture(tmp_path, bad_stage_t=True)
    with pytest.raises(ValueError, match="recommended_next_stage"):
        stage_u.summarize(stage_u.parser().parse_args(argv))


def test_stage_u_rejects_duplicate_stage_m_keys(tmp_path):
    argv, _ = make_fixture(tmp_path, duplicate_surface=True)
    with pytest.raises(ValueError, match="duplicate region/fold"):
        stage_u.summarize(stage_u.parser().parse_args(argv))


def test_stage_u_flags_missing_window_manifest(tmp_path):
    argv, out = make_fixture(tmp_path, omit_test_window=True)
    summary = stage_u.summarize(stage_u.parser().parse_args(argv))

    assert summary["row_parity_failures"] == 1
    assert summary["hard_parity_failures"] == 1
    parity = pd.read_csv(out / "stage_u_row_parity_matrix.csv")
    failed = parity[parity["parity_status"].eq("fail")].iloc[0]
    assert "all_window_manifests_ok" in failed["hard_failures"]
