"""Tests for graph/local PriceFM rescue diagnostics and overlay helpers."""

from pathlib import Path
import importlib.util
import sys
from types import SimpleNamespace

import pandas as pd
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


def write_panel_metric(root):
    rows = [
        {"region": "DE_LU", "fold": 1, "method_id": "pricefm_phase1_pretraining", "split": "test", "unit": "original", "AQL": 10.0},
        {"region": "DE_LU", "fold": 1, "method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": 11.0},
        {"region": "EE", "fold": 2, "method_id": "pricefm_phase1_pretraining", "split": "test", "unit": "original", "AQL": 20.0},
        {"region": "EE", "fold": 2, "method_id": "qdesn_exal_rhs_ns_exact_chunked", "split": "test", "unit": "original", "AQL": 18.0},
    ]
    pd.DataFrame(rows).to_csv(root / "panel_metric.csv", index=False)
    hrows = []
    for row in rows:
        for group in ["1-24", "25-48"]:
            h = dict(row)
            h["horizon_group"] = group
            hrows.append(h)
    pd.DataFrame(hrows).to_csv(root / "panel_horizon_group.csv", index=False)


def registry_rows():
    return pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "selected_source": "local",
            "feature_policy": "target_only",
            "experiment_id": "local_delu",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.25,
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 20260615,
            "test_improved": True,
        },
        {
            "region": "EE",
            "fold": 2,
            "selected_source": "graph",
            "feature_policy": "graph_khop",
            "experiment_id": "graph_ee",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.25,
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 20260615,
            "test_improved": True,
        },
    ])


def test_graph_local_diagnostics_select_rescue_scope(tmp_path):
    mod = load_script("39_diagnose_pricefm_graph_local_panel.py")
    comparison = tmp_path / "comparison"
    comparison.mkdir()
    write_panel_metric(comparison)
    registry = tmp_path / "registry.csv"
    registry_rows().to_csv(registry, index=False)
    args = SimpleNamespace(
        comparison_root=str(comparison),
        registry_csv=str(registry),
        output_dir=str(tmp_path / "diag"),
        baseline_method="pricefm_phase1_pretraining",
        split="test",
        unit="original",
        include_close=True,
        close_rel_threshold=0.05,
        severe_rel_threshold=0.10,
        dry_run=False,
    )
    diagnostics = mod.build_diagnostics(args)
    rescue = diagnostics["rescue"]
    assert rescue.shape[0] == 1
    row = rescue.iloc[0]
    assert row["region"] == "DE_LU"
    assert row["recommended_action"] == "retest_graph_geometry_validation"
    mod.main.__name__  # keep import side effects explicit


def test_graph_local_rescue_grid_generates_degree2_candidates(tmp_path):
    mod = load_script("40_prepare_pricefm_graph_local_rescue_median_grid.py")
    template = yaml.safe_load(
        (ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_region_panel_20260606.yaml").read_text()
    )
    registry = registry_rows()
    rescue = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "rescue_priority": 0,
            "recommended_action": "retest_graph_geometry_validation",
            "decision_label": "selected_lags_pricefm",
            "delta_rel": 0.10,
        },
    ])
    args = SimpleNamespace(
        grid_id="unit_rescue",
        generated_root="generated",
        run_root="runs",
        priority_offset=0,
        include_close=True,
        max_variants_per_row=8,
        candidate_source="unit_rescue_source",
    )
    payload = mod.build_grid(template, registry, rescue, args)
    exps = payload["pricefm_desn_experiment_grid"]["experiments"]
    assert len(exps) == 8
    assert any(exp["feature_policy"] == "graph_khop" and exp["graph_degree"] == 2 for exp in exps)
    assert all(exp["quantile"] == 0.50 for exp in exps)
    assert all(exp["selection_is_validation_only"] for exp in exps)


def make_summary_dir(root, region, fold, method, aql):
    out = root / f"region={region}" / f"fold={fold}"
    out.mkdir(parents=True)
    (out / "summary.json").write_text('{"status":"complete"}\n')
    pd.DataFrame([
        {
            "region": region,
            "fold": fold,
            "method_id": method,
            "split": "test",
            "unit": "original",
            "AQL": aql,
        }
    ]).to_csv(out / "paper_quantile_metric_summary.csv", index=False)
    pd.DataFrame([{"region": region, "fold": fold, "status": "completed"}]).to_csv(
        out / "quantile_cell_status.csv", index=False
    )
    pd.DataFrame([{"region": region, "fold": fold, "wall_seconds": 1.0}]).to_csv(
        out / "quantile_cell_runtime.csv", index=False
    )


def test_overlay_uses_patch_when_available(tmp_path):
    mod = load_script("41_overlay_pricefm_region_panel_quantiles.py")
    base = tmp_path / "base"
    patch = tmp_path / "patch"
    make_summary_dir(base, "DE_LU", 1, "base_method", 10.0)
    make_summary_dir(base, "EE", 2, "base_method", 20.0)
    make_summary_dir(patch, "DE_LU", 1, "patch_method", 8.0)
    registry = tmp_path / "registry.csv"
    pd.DataFrame([
        {"region": "DE_LU", "fold": 1},
        {"region": "EE", "fold": 2},
    ]).to_csv(registry, index=False)
    args = SimpleNamespace(
        base_root=str(base),
        patch_root=[str(patch)],
        output_root=str(tmp_path / "overlay"),
        registry_csv=str(registry),
        link_mode="copy",
        force=False,
        dry_run=False,
    )
    summary = mod.build_overlay(args)
    manifest = pd.read_csv(tmp_path / "overlay" / "overlay_manifest.csv")
    metric = pd.read_csv(tmp_path / "overlay" / "panel_metric.csv")
    assert summary["n_patch_folds"] == 1
    assert manifest["source_kind"].tolist() == ["patch", "base"]
    assert "patch_method" in set(metric["method_id"])
    assert "base_method" in set(metric["method_id"])


def write_rescue_metric(run_dir, region, fold, method, val_aql, test_aql):
    model = run_dir / "cells" / f"region={region}" / f"fold={fold}" / "model"
    model.mkdir(parents=True)
    pd.DataFrame([
        {
            "method_id": method,
            "split": "val",
            "unit": "original",
            "AQL": val_aql,
            "AQCR": 0.0,
            "MAE": 2.0 * val_aql,
            "RMSE": 3.0 * val_aql,
        },
        {
            "method_id": method,
            "split": "test",
            "unit": "original",
            "AQL": test_aql,
            "AQCR": 0.0,
            "MAE": 2.0 * test_aql,
            "RMSE": 3.0 * test_aql,
        },
    ]).to_csv(model / "metric_summary.csv", index=False)


def rescue_manifest_row(root, experiment_id, region, fold, graph_degree=1):
    run_dir = root / experiment_id
    return {
        "id": experiment_id,
        "priority": 0,
        "regions": f'["{region}"]',
        "folds": f"[{fold}]",
        "feature_policy": "graph_khop",
        "graph_degree": graph_degree,
        "input_scope": f"pricefm_graph_khop_degree{graph_degree}",
        "spatial_information_set": "pricefm_released_graph_khop",
        "lag_window": 96,
        "depth": 2,
        "units": "[80, 80]",
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.25,
        "tau0": 1.0e-3,
        "seed": 20260615,
        "run_dir": str(run_dir),
        "full_config": str(root / experiment_id / "full.yaml"),
        "data_config": str(root / experiment_id / "data.yaml"),
        "rationale": "unit test rescue",
    }


def test_graph_local_rescue_closeout_classifies_candidates(tmp_path):
    mod = load_script("42_closeout_pricefm_graph_local_rescue.py")
    method = "qdesn_exal_rhs_ns_exact_chunked"
    run_root = tmp_path / "runs"
    manifest_rows = [
        rescue_manifest_row(run_root, "rescue_a", "DE_LU", 1),
        rescue_manifest_row(run_root, "rescue_b", "HU", 2),
        rescue_manifest_row(run_root, "rescue_c", "NO_4", 3),
    ]
    write_rescue_metric(run_root / "rescue_a", "DE_LU", 1, method, val_aql=8.0, test_aql=9.0)
    write_rescue_metric(run_root / "rescue_b", "HU", 2, method, val_aql=8.0, test_aql=10.8)
    write_rescue_metric(run_root / "rescue_c", "NO_4", 3, method, val_aql=10.5, test_aql=8.5)
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    registry = tmp_path / "current.csv"
    pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "selected_method_id": method,
            "experiment_id": "current_a",
            "selected_source": "graph",
            "selection_AQL": 10.0,
            "test_AQL": 10.0,
            "test_MAE": 20.0,
            "test_RMSE": 30.0,
        },
        {
            "region": "HU",
            "fold": 2,
            "selected_method_id": method,
            "experiment_id": "current_b",
            "selected_source": "graph",
            "selection_AQL": 10.0,
            "test_AQL": 10.0,
            "test_MAE": 20.0,
            "test_RMSE": 30.0,
        },
        {
            "region": "NO_4",
            "fold": 3,
            "selected_method_id": method,
            "experiment_id": "current_c",
            "selected_source": "local",
            "selection_AQL": 10.0,
            "test_AQL": 10.0,
            "test_MAE": 20.0,
            "test_RMSE": 30.0,
        },
    ]).to_csv(registry, index=False)
    args = SimpleNamespace(
        manifest_csv=str(manifest),
        run_root=str(run_root),
        current_registry_csv=str(registry),
        output_dir=str(tmp_path / "closeout"),
        split_select="val",
        split_audit="test",
        unit="original",
        metric="AQL",
        model_methods=method,
        validation_tolerance=0.0,
        test_tolerance=0.0,
        severe_test_rel_threshold=0.05,
        robustness_seeds="101,102",
    )
    summary = mod.closeout(args)
    decisions = pd.read_csv(tmp_path / "closeout" / "rescue_closeout_decisions.csv")
    labels = dict(zip(decisions["region"], decisions["closeout_label"]))
    assert labels["DE_LU"] == "robustness_candidate"
    assert labels["HU"] == "validation_overfit_warning"
    assert labels["NO_4"] == "test_only_diagnostic"
    seed_plan = pd.read_csv(tmp_path / "closeout" / "robustness_seed_plan.csv")
    assert seed_plan.shape[0] == 2
    assert set(seed_plan["robustness_seed"]) == {101, 102}
    assert summary["n_robustness_candidates"] == 1


def test_graph_local_rescue_closeout_accepts_plan_manifest_shape(tmp_path):
    mod = load_script("42_closeout_pricefm_graph_local_rescue.py")
    method = "qdesn_exal_rhs_ns_exact_chunked"
    run_root = tmp_path / "runs"
    exp_id = "stageg_dk2_f1_graphd1_lag48"
    write_rescue_metric(run_root / exp_id, "DK_2", 1, method, val_aql=7.0, test_aql=8.0)
    manifest = tmp_path / "manifest.csv"
    row = rescue_manifest_row(run_root, exp_id, "DK_2", 1)
    row.pop("run_dir")
    row.pop("full_config")
    row.pop("data_config")
    row["regions"] = "['DK_2']"
    row["folds"] = "[1]"
    unlaunched = dict(row)
    unlaunched["id"] = "stageg_dk2_f1_priority1_unlaunched"
    unlaunched["priority"] = 1
    pd.DataFrame([row, unlaunched]).to_csv(manifest, index=False)
    registry = tmp_path / "current.csv"
    pd.DataFrame([{
        "region": "DK_2",
        "fold": 1,
        "selected_method_id": method,
        "experiment_id": "current",
        "selected_source": "graph",
        "selection_AQL": 9.0,
        "test_AQL": 9.0,
        "test_MAE": 20.0,
        "test_RMSE": 30.0,
    }]).to_csv(registry, index=False)
    args = SimpleNamespace(
        manifest_csv=str(manifest),
        run_root=str(run_root),
        current_registry_csv=str(registry),
        output_dir=str(tmp_path / "closeout"),
        split_select="val",
        split_audit="test",
        unit="original",
        metric="AQL",
        model_methods=method,
        validation_tolerance=0.0,
        test_tolerance=0.0,
        severe_test_rel_threshold=0.05,
        robustness_seeds="101,102",
        priority=0,
    )
    summary = mod.closeout(args)
    decisions = pd.read_csv(tmp_path / "closeout" / "rescue_closeout_decisions.csv")
    assert summary["n_missing_metric_files"] == 0
    assert summary["n_experiments_in_manifest"] == 1
    assert summary["priority_filter"] == 0
    assert decisions.loc[0, "closeout_label"] == "robustness_candidate"
    assert decisions.loc[0, "run_dir"].endswith(exp_id)


def test_rescue_seed_grid_preserves_source_geometry(tmp_path):
    mod = load_script("43_prepare_pricefm_graph_local_rescue_seed_grid.py")
    source_grid = {
        "pricefm_desn_experiment_grid": {
            "grid_id": "source",
            "purpose": "unit source",
            "base": {
                "generated_root": "old_generated",
                "run_root": "old_runs",
            },
            "scope": {
                "regions": ["IT_SICI"],
                "folds": [3],
                "quantiles": [0.5],
            },
            "experiments": [
                {
                    "id": "rescue_itsici_f3_graphd2_base",
                    "stage": "graph_local_median_rescue",
                    "priority": 0,
                    "regions": ["IT_SICI"],
                    "folds": [3],
                    "feature_policy": "graph_khop",
                    "graph_degree": 2,
                    "lag_window": 96,
                    "depth": 3,
                    "units": [80, 80, 80],
                    "alpha": 0.35,
                    "rho": 0.9,
                    "input_scale": 0.2,
                    "tau0": 1.0e-3,
                    "seed": 20260615,
                    "quantile": 0.5,
                    "median_registry": {"region": "IT_SICI", "fold": 3},
                }
            ],
            "experiment_blocks": [{"unused": True}],
        }
    }
    seed_plan = pd.DataFrame([
        {
            "region": "IT_SICI",
            "fold": 3,
            "source_experiment_id": "rescue_itsici_f3_graphd2_base",
            "robustness_seed": 20260616,
        },
        {
            "region": "IT_SICI",
            "fold": 3,
            "source_experiment_id": "rescue_itsici_f3_graphd2_base",
            "robustness_seed": 20260617,
        },
    ])
    args = SimpleNamespace(
        grid_id="unit_seedrob",
        generated_root="generated_seedrob",
        run_root="runs_seedrob",
        priority=0,
    )
    payload = mod.build_grid(source_grid, mod.required_seed_plan(seed_plan), args)
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["base"]["generated_root"] == "generated_seedrob"
    assert grid["base"]["run_root"] == "runs_seedrob"
    assert grid["experiment_blocks"] == []
    assert len(grid["experiments"]) == 2
    seeds = {exp["seed"] for exp in grid["experiments"]}
    assert seeds == {20260616, 20260617}
    for exp in grid["experiments"]:
        assert exp["stage"] == "graph_local_median_rescue_seed_robustness"
        assert exp["feature_policy"] == "graph_khop"
        assert exp["graph_degree"] == 2
        assert exp["units"] == [80, 80, 80]
        assert exp["alpha"] == 0.35
        assert exp["input_scale"] == 0.2
        assert exp["source_rescue_experiment_id"] == "rescue_itsici_f3_graphd2_base"


def test_rescue_seedrob_summary_passes_stable_candidate(tmp_path):
    mod = load_script("44_summarize_pricefm_graph_local_rescue_seedrob.py")
    method = "qdesn_exal_rhs_ns_exact_chunked"
    run_root = tmp_path / "runs"
    manifest_rows = []
    for seed, val_aql, test_aql in [
        (20260616, 8.0, 9.2),
        (20260617, 8.1, 9.1),
        (20260618, 8.2, 9.0),
    ]:
        exp_id = f"rescue_itsici_f3_graphd2_base_seedrob{seed}"
        manifest_rows.append({
            "id": exp_id,
            "regions": '["IT_SICI"]',
            "folds": "[3]",
            "run_dir": str(run_root / exp_id),
            "source_rescue_experiment_id": "rescue_itsici_f3_graphd2_base",
            "robustness_seed": seed,
            "seed": seed,
            "feature_policy": "graph_khop",
            "graph_degree": 2,
            "depth": 3,
            "units": "[80, 80, 80]",
            "alpha": 0.35,
            "rho": 0.9,
            "input_scale": 0.2,
            "tau0": 1.0e-3,
        })
        write_rescue_metric(run_root / exp_id, "IT_SICI", 3, method, val_aql=val_aql, test_aql=test_aql)
    manifest = tmp_path / "manifest.csv"
    pd.DataFrame(manifest_rows).to_csv(manifest, index=False)
    current = tmp_path / "current.csv"
    pd.DataFrame([
        {
            "region": "IT_SICI",
            "fold": 3,
            "selection_AQL": 9.0,
            "test_AQL": 10.0,
            "test_MAE": 20.0,
            "test_RMSE": 30.0,
            "selected_method_id": method,
            "experiment_id": "current",
        }
    ]).to_csv(current, index=False)
    args = SimpleNamespace(
        manifest_csv=str(manifest),
        current_registry_csv=str(current),
        output_dir=str(tmp_path / "summary"),
        split_select="val",
        split_audit="test",
        unit="original",
        model_methods=method,
        min_validation_win_rate=1.0,
        max_mean_test_delta=0.0,
        max_test_rel_deterioration=0.05,
    )
    payload = mod.summarize(args)
    summary = pd.read_csv(tmp_path / "summary" / "seedrob_candidate_summary.csv")
    ready = pd.read_csv(tmp_path / "summary" / "promotion_ready_queue.csv")
    assert payload["n_promotion_ready"] == 1
    assert bool(summary.loc[0, "pass_seed_robustness"])
    assert summary.loc[0, "recommended_action"] == "patch_median_registry_then_quantile_promotion"
    assert ready.shape[0] == 1


def test_patch_registry_from_seedrob_replaces_only_ready_row(tmp_path):
    mod = load_script("45_patch_pricefm_median_registry_from_seedrob.py")
    current = tmp_path / "current.csv"
    pd.DataFrame([
        {
            "region": "IT_SICI",
            "fold": 3,
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "experiment_id": "current_itsici",
            "selection_AQL": 6.3,
            "selection_metric_value": 6.3,
            "test_AQL": 6.5,
            "test_MAE": 13.0,
            "test_RMSE": 20.0,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.25,
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 1,
        },
        {
            "region": "NO_4",
            "fold": 1,
            "selected_method_id": "qdesn_al_rhs_ns_exact_chunked",
            "experiment_id": "current_no4",
            "selection_AQL": 1.0,
            "selection_metric_value": 1.0,
            "test_AQL": 2.0,
            "test_MAE": 4.0,
            "test_RMSE": 6.0,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": "[120]",
            "alpha": 0.4,
            "rho": 0.9,
            "input_scale": 0.25,
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 1,
        },
    ]).to_csv(current, index=False)
    decisions = tmp_path / "decisions.csv"
    pd.DataFrame([
        {
            "region": "IT_SICI",
            "fold": 3,
            "source_rescue_experiment_id": "rescue_itsici_f3_graphd2_base",
            "experiment_id": "seedrob_20260616",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_AQL": 6.0,
            "test_AQL": 6.1,
            "test_MAE": 12.2,
            "test_RMSE": 18.3,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 3,
            "units": "[80, 80, 80]",
            "alpha": 0.35,
            "rho": 0.9,
            "input_scale": 0.2,
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 20260616,
            "run_dir": "runs/seedrob",
            "full_config": "full.yaml",
            "data_config": "data.yaml",
            "feature_policy": "graph_khop",
            "graph_degree": 2,
        }
    ]).to_csv(decisions, index=False)
    ready = tmp_path / "ready.csv"
    pd.DataFrame([
        {
            "region": "IT_SICI",
            "fold": 3,
            "source_rescue_experiment_id": "rescue_itsici_f3_graphd2_base",
            "pass_seed_robustness": True,
        }
    ]).to_csv(ready, index=False)
    args = SimpleNamespace(
        current_registry_csv=str(current),
        seedrob_decisions_csv=str(decisions),
        promotion_ready_csv=str(ready),
        output_dir=str(tmp_path / "patch"),
        candidate_source="unit_seedrob",
        allow_empty="false",
    )
    payload = mod.patch_registry(args)
    patched = pd.read_csv(tmp_path / "patch" / "patched_selection_registry.csv")
    patch_rows = pd.read_csv(tmp_path / "patch" / "patch_rows_registry.csv")
    itsici = patched[patched["region"].eq("IT_SICI")].iloc[0]
    no4 = patched[patched["region"].eq("NO_4")].iloc[0]
    assert payload["n_patch_rows"] == 1
    assert patch_rows.shape[0] == 1
    assert itsici["experiment_id"] == "seedrob_20260616"
    assert itsici["selected_source"] == "rescue_seedrob"
    assert int(itsici["depth"]) == 3
    assert no4["experiment_id"] == "current_no4"
