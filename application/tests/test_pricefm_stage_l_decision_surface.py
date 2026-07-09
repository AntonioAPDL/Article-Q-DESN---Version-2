"""Tests for Stage-L PriceFM decision-surface tooling."""

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

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


def write_y(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.Series(values).to_csv(path, index=False, header=False)


def base_args(tmp_path):
    return SimpleNamespace(
        median_registry_csv=str(tmp_path / "median.csv"),
        quantile_decision_registry_csv=str(tmp_path / "quantile.csv"),
        stage_j_closeout_csv=str(tmp_path / "stage_j.csv"),
        stage_k_summary_csv=str(tmp_path / "stage_k.csv"),
        output_dir=str(tmp_path / "surface"),
        expected_region_folds=2,
        force=True,
    )


def write_valid_surface_inputs(tmp_path):
    write_csv(tmp_path / "median.csv", [
        {"region": "A", "fold": 1, "selection_AQL": 10.0, "test_AQL": 9.0},
        {"region": "B", "fold": 2, "selection_AQL": 11.0, "test_AQL": 8.0},
    ])
    write_csv(tmp_path / "quantile.csv", [
        {
            "region": "A", "fold": 1, "local_AQL": 9.5, "pricefm_AQL": 10.0,
            "delta_abs": -0.5, "selection_AQL": 10.0, "test_AQL": 9.0,
        },
        {
            "region": "B", "fold": 2, "local_AQL": 8.5, "pricefm_AQL": 8.0,
            "delta_abs": 0.5, "selection_AQL": "", "test_AQL": "",
        },
    ])
    write_csv(tmp_path / "stage_j.csv", [
        {"region": "A", "fold": 1, "selection_AQL": 10.0, "test_AQL": 9.0},
    ])
    write_csv(tmp_path / "stage_k.csv", [
        {
            "region": "A", "fold": 1, "mean_val_delta_vs_current": 0.1,
            "max_val_delta_vs_current": 0.2, "pass_multiseed_validation_gate": False,
        },
    ])


def test_stage_l_current_decision_surface_allows_documented_quantile_median_gaps(tmp_path):
    mod = load_script("65_validate_pricefm_current_decision_surface.py")
    write_valid_surface_inputs(tmp_path)

    summary = mod.summarize(base_args(tmp_path))
    gaps = pd.read_csv(tmp_path / "surface" / "quantile_registry_median_field_gaps.csv")

    assert summary["fatal_failures"] == 0
    assert summary["n_quantile_median_field_gap_rows"] == 1
    assert set(gaps["region"]) == {"B"}
    assert (tmp_path / "surface" / "current_median_registry.csv").exists()
    assert (tmp_path / "surface" / "baseline_paths.json").exists()


def test_stage_l_current_decision_surface_rejects_nonfinite_median(tmp_path):
    mod = load_script("65_validate_pricefm_current_decision_surface.py")
    write_valid_surface_inputs(tmp_path)
    write_csv(tmp_path / "median.csv", [
        {"region": "A", "fold": 1, "selection_AQL": "", "test_AQL": 9.0},
        {"region": "B", "fold": 2, "selection_AQL": 11.0, "test_AQL": 8.0},
    ])

    with pytest.raises(ValueError, match="failed"):
        mod.summarize(base_args(tmp_path))


def test_stage_l_si_seed_expansion_preparer_writes_new_grid_and_existing_manifest(tmp_path):
    mod = load_script("66_prepare_pricefm_stage_l_si_seed_expansion.py")
    source_grid = {
        "pricefm_desn_experiment_grid": {
            "grid_id": "stage_k",
            "purpose": "unit",
            "base": {
                "data_config": "application/config/pricefm_data_pipeline.yaml",
                "full_config": "application/config/example.yaml",
                "generated_root": str(tmp_path / "old_generated"),
                "run_root": str(tmp_path / "old_runs"),
            },
            "scope": {"regions": ["SI"], "folds": [1], "quantiles": [0.5]},
            "fixed": {},
            "launch": {},
            "experiments": [{
                "id": "source_seed20260624",
                "stage": "stage_k",
                "priority": 0,
                "regions": ["SI"],
                "folds": [1],
                "quantile": 0.5,
                "feature_map": "window_reservoir_v1",
                "feature_policy": "graph_summary_mean",
                "graph_degree": 2,
                "lag_window": 96,
                "depth": 1,
                "units": [120],
                "alpha": 0.5,
                "rho": 0.9,
                "input_scale": 0.35,
                "projection_scale": 1.0,
                "tau0": 0.001,
                "seed": 20260624,
                "median_registry": {"region": "SI", "fold": 1},
            }],
        }
    }
    (tmp_path / "source.yaml").write_text(yaml.safe_dump(source_grid, sort_keys=False))
    write_csv(tmp_path / "manifest.csv", [
        {"id": "stagek_si_f1_graphd2_summary_mean_seed20260624", "regions": "[\"SI\"]", "folds": "[1]"},
        {"id": "stagek_si_f1_graphd2_summary_mean_seed20260625", "regions": "[\"SI\"]", "folds": "[1]"},
    ])
    args = SimpleNamespace(
        source_grid_config=str(tmp_path / "source.yaml"),
        source_manifest_csv=str(tmp_path / "manifest.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        generated_root=str(tmp_path / "generated"),
        run_root=str(tmp_path / "runs"),
        summary_dir=str(tmp_path / "summary"),
        grid_id="stage_l",
        source_experiment_id="source_seed20260624",
        existing_experiment_prefix="stagek_si_f1_graphd2_summary_mean_seed",
        new_seeds="20260626,20260627",
        existing_seeds="20260624,20260625",
        stage_name="stage_l",
        candidate_source="stage_l_unit",
        experiment_prefix="stagel_seed",
        write=True,
    )

    summary = mod.prepare(args)
    grid = yaml.safe_load((tmp_path / "grid.yaml").read_text())["pricefm_desn_experiment_grid"]

    assert summary["n_new_experiments"] == 2
    assert summary["n_existing_seed_rows"] == 2
    assert grid["grid_id"] == "stage_l"
    assert {exp["seed"] for exp in grid["experiments"]} == {20260626, 20260627}
    assert (tmp_path / "summary" / "existing_stage_k_seed_manifest.csv").exists()


def test_stage_l_split_diagnostics_summarizes_adapter_windows(tmp_path):
    mod = load_script("67_summarize_pricefm_stage_l_split_diagnostics.py")
    run_dir = tmp_path / "runs" / "exp1"
    adapter = run_dir / "cells" / "region=A" / "fold=1" / "adapter"
    for split, values in {
        "train": [1.0, 2.0, 3.0],
        "val": [2.0, 4.0],
        "test": [3.0, 6.0, 9.0],
    }.items():
        write_y(adapter / "y_{}.csv".format(split), values)
        write_csv(adapter / "rows_{}.csv".format(split), [
            {"response_market_time": "2026-01-0{}T00:00:00Z".format(i + 1), "origin_id": i, "horizon": i + 1}
            for i in range(len(values))
        ])
    write_csv(tmp_path / "manifest.csv", [{
        "id": "exp1",
        "regions": "A",
        "folds": 1,
        "run_dir": str(run_dir),
        "feature_policy": "graph_summary_mean",
        "graph_degree": 2,
    }])
    args = SimpleNamespace(
        manifest_csv=str(tmp_path / "manifest.csv"),
        output_dir=str(tmp_path / "split_diag"),
        regions="A",
        folds="1",
        splits="train,val,test",
    )

    summary = mod.summarize(args)
    split_summary = pd.read_csv(tmp_path / "split_diag" / "split_response_summary.csv")
    contrasts = pd.read_csv(tmp_path / "split_diag" / "split_response_contrasts.csv")

    assert summary["n_split_rows"] == 3
    assert summary["n_contrast_rows"] == 3
    assert set(split_summary["split"]) == {"train", "val", "test"}
    assert int(split_summary.loc[split_summary["split"].eq("test"), "n"].iloc[0]) == 3
    assert set(contrasts["contrast"]) == {"val_minus_train", "test_minus_val", "test_minus_train"}
    assert (tmp_path / "split_diag" / "stage_l_split_diagnostics_report.md").exists()


def test_stage_l_split_diagnostics_reads_current_registry_adapter_dirs(tmp_path):
    mod = load_script("67_summarize_pricefm_stage_l_split_diagnostics.py")
    adapter = tmp_path / "adapter_a1"
    for split, values in {
        "train": [1.0, 2.0],
        "val": [2.0, 3.0],
        "test": [4.0, 5.0],
    }.items():
        write_y(adapter / "y_{}.csv".format(split), values)
        write_csv(adapter / "rows_{}.csv".format(split), [
            {"response_market_time": "2026-01-0{}T00:00:00Z".format(i + 1), "origin_id": i, "horizon": i + 1}
            for i in range(len(values))
        ])
    write_csv(tmp_path / "registry.csv", [{
        "region": "A",
        "fold": 1,
        "experiment_id": "registry_exp",
        "adapter_dir": str(adapter),
        "feature_policy": "target_only",
        "graph_degree": "",
    }])
    args = SimpleNamespace(
        manifest_csv="unused.csv",
        registry_csv=str(tmp_path / "registry.csv"),
        output_dir=str(tmp_path / "registry_split_diag"),
        regions="A",
        folds="1",
        splits="train,val,test",
    )

    summary = mod.summarize(args)
    source = pd.read_csv(tmp_path / "registry_split_diag" / "source_cells.csv")

    assert summary["n_split_rows"] == 3
    assert source["experiment_id"].iloc[0] == "registry_exp"
    assert source["adapter_dir"].iloc[0].endswith("adapter_a1")
