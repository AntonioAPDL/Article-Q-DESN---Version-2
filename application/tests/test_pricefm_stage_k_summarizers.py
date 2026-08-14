"""Tests for Stage-K PriceFM diagnostic and multi-seed summarizers."""

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


def write_metric(run_root, exp_id, region, fold, *, val_aql, test_aql):
    path = (
        run_root / exp_id / "cells" / "region={}".format(region)
        / "fold={}".format(fold) / "model" / "metric_summary.csv"
    )
    rows = [
        {
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "val",
            "unit": "original",
            "AQL": val_aql,
            "MAE": val_aql * 2.0,
            "RMSE": val_aql * 3.0,
        },
        {
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": test_aql,
            "MAE": test_aql * 2.0,
            "RMSE": test_aql * 3.0,
        },
    ]
    write_csv(path, rows)
    return path


def manifest_row(exp_id, run_root, seed, *, feature_policy="graph_summary_mean"):
    return {
        "id": exp_id,
        "regions": "A",
        "folds": 1,
        "run_dir": str(run_root / exp_id),
        "feature_policy": feature_policy,
        "graph_degree": 1,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "tau0": 1.0e-3,
        "seed": seed,
        "candidate_source": "unit",
    }


def test_multiseed_screen_uses_validation_gate_and_keeps_test_audit_only(tmp_path):
    mod = load_script("62_summarize_pricefm_multiseed_median_screen.py")
    run_root = tmp_path / "runs"
    manifest = [
        manifest_row("good_s1", run_root, 101),
        manifest_row("good_s2", run_root, 102),
        manifest_row("good_s3", run_root, 103),
        manifest_row("bad_s1", run_root, 201, feature_policy="graph_summary_mean_std"),
    ]
    write_metric(run_root, "good_s1", "A", 1, val_aql=9.80, test_aql=9.20)
    write_metric(run_root, "good_s2", "A", 1, val_aql=9.90, test_aql=9.10)
    write_metric(run_root, "good_s3", "A", 1, val_aql=10.01, test_aql=9.50)
    write_metric(run_root, "bad_s1", "A", 1, val_aql=10.50, test_aql=8.00)
    write_csv(tmp_path / "manifest.csv", manifest)
    write_csv(tmp_path / "current.csv", [{
        "region": "A",
        "fold": 1,
        "selection_AQL": 10.0,
        "test_AQL": 9.0,
        "test_MAE": 18.0,
        "test_RMSE": 27.0,
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "experiment_id": "current",
    }])
    args = SimpleNamespace(
        manifest_csv=str(tmp_path / "manifest.csv"),
        current_registry_csv=str(tmp_path / "current.csv"),
        output_dir=str(tmp_path / "out"),
        split_select="val",
        split_audit="test",
        unit="original",
        model_methods="qdesn_exal_rhs_ns_exact_chunked",
        min_validation_win_rate=2.0 / 3.0,
        max_mean_validation_delta=0.0,
        max_validation_delta=0.02,
        max_mean_test_delta_warning=0.0,
        require_complete=True,
    )

    summary = mod.summarize(args)
    geom = pd.read_csv(tmp_path / "out" / "multiseed_geometry_summary.csv")
    queue = pd.read_csv(tmp_path / "out" / "multiseed_precloseout_queue.csv")

    assert summary["n_precloseout_rows"] == 1
    assert set(queue["feature_policy"]) == {"graph_summary_mean"}
    good = geom[geom["feature_policy"].eq("graph_summary_mean")].iloc[0]
    assert good["n_seeds"] == 3
    assert good["n_validation_improved"] == 2
    assert bool(good["pass_multiseed_validation_gate"]) is True
    bad = geom[geom["feature_policy"].eq("graph_summary_mean_std")].iloc[0]
    assert bool(bad["pass_multiseed_validation_gate"]) is False


def test_multiseed_screen_missing_metrics_fail_when_required(tmp_path):
    mod = load_script("62_summarize_pricefm_multiseed_median_screen.py")
    write_csv(tmp_path / "manifest.csv", [
        manifest_row("missing_s1", tmp_path / "runs", 101)
    ])
    write_csv(tmp_path / "current.csv", [{
        "region": "A",
        "fold": 1,
        "selection_AQL": 10.0,
        "test_AQL": 9.0,
    }])
    args = SimpleNamespace(
        manifest_csv=str(tmp_path / "manifest.csv"),
        current_registry_csv=str(tmp_path / "current.csv"),
        output_dir=str(tmp_path / "out"),
        split_select="val",
        split_audit="test",
        unit="original",
        model_methods="qdesn_exal_rhs_ns_exact_chunked",
        min_validation_win_rate=0.67,
        max_mean_validation_delta=0.0,
        max_validation_delta=0.02,
        max_mean_test_delta_warning=0.0,
        require_complete=True,
    )

    with pytest.raises(FileNotFoundError, match="Missing or unusable"):
        mod.summarize(args)


def test_multiseed_screen_reports_unique_missing_current_registry_keys(tmp_path):
    mod = load_script("62_summarize_pricefm_multiseed_median_screen.py")
    run_root = tmp_path / "runs"
    manifest = [
        manifest_row("missing_key_s1", run_root, 101),
        manifest_row("missing_key_s2", run_root, 102),
    ]
    write_metric(run_root, "missing_key_s1", "A", 1, val_aql=9.8, test_aql=9.2)
    write_metric(run_root, "missing_key_s2", "A", 1, val_aql=9.9, test_aql=9.1)
    write_csv(tmp_path / "manifest.csv", manifest)
    write_csv(tmp_path / "current.csv", [{
        "region": "B",
        "fold": 1,
        "selection_AQL": 10.0,
        "test_AQL": 9.0,
    }])
    args = SimpleNamespace(
        manifest_csv=str(tmp_path / "manifest.csv"),
        current_registry_csv=str(tmp_path / "current.csv"),
        current_registry_label="unit_current",
        output_dir=str(tmp_path / "out"),
        split_select="val",
        split_audit="test",
        unit="original",
        model_methods="qdesn_exal_rhs_ns_exact_chunked",
        min_validation_win_rate=0.67,
        max_mean_validation_delta=0.0,
        max_validation_delta=0.02,
        max_mean_test_delta_warning=0.0,
        require_complete=True,
    )

    with pytest.raises(ValueError, match="unit_current"):
        mod.summarize(args)

    try:
        mod.summarize(args)
    except ValueError as exc:
        message = str(exc)
    assert message.count("'region': 'A'") == 1


def test_multiseed_screen_rejects_nonfinite_current_registry_metrics(tmp_path):
    mod = load_script("62_summarize_pricefm_multiseed_median_screen.py")
    run_root = tmp_path / "runs"
    write_metric(run_root, "seed_s1", "A", 1, val_aql=9.8, test_aql=9.2)
    write_csv(tmp_path / "manifest.csv", [manifest_row("seed_s1", run_root, 101)])
    write_csv(tmp_path / "current.csv", [{
        "region": "A",
        "fold": 1,
        "selection_AQL": "",
        "test_AQL": 9.0,
    }])
    args = SimpleNamespace(
        manifest_csv=str(tmp_path / "manifest.csv"),
        current_registry_csv=str(tmp_path / "current.csv"),
        output_dir=str(tmp_path / "out"),
        split_select="val",
        split_audit="test",
        unit="original",
        model_methods="qdesn_exal_rhs_ns_exact_chunked",
        min_validation_win_rate=0.67,
        max_mean_validation_delta=0.0,
        max_validation_delta=0.02,
        max_mean_test_delta_warning=0.0,
        require_complete=True,
    )

    with pytest.raises(ValueError, match="non-finite required metric fields"):
        mod.summarize(args)


def test_stage_k_instability_taxonomy_combines_closeout_and_seedrob(tmp_path):
    mod = load_script("63_summarize_pricefm_stage_k_instability.py")
    write_csv(tmp_path / "closeout.csv", [
        {
            "region": "NL",
            "fold": 3,
            "experiment_id": "raw_graph",
            "source_rescue_experiment_id": "raw_graph",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_policy": "graph_khop",
            "graph_degree": 2,
            "val_delta_vs_current": -0.1,
            "test_delta_vs_current": -0.2,
            "closeout_label": "robustness_candidate",
        },
        {
            "region": "BE",
            "fold": 3,
            "experiment_id": "audit_bad",
            "source_rescue_experiment_id": "audit_bad",
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "feature_policy": "graph_khop",
            "graph_degree": 1,
            "val_delta_vs_current": -0.1,
            "test_delta_vs_current": 0.2,
            "closeout_label": "validation_candidate_audit_worse",
        },
    ])
    write_csv(tmp_path / "seed_summary.csv", [{
        "region": "NL",
        "fold": 3,
        "source_rescue_experiment_id": "raw_graph",
        "n_seeds": 3,
        "n_validation_improved": 0,
        "n_test_improved": 1,
        "validation_win_rate": 0.0,
        "mean_val_delta_vs_current": 0.05,
        "max_val_delta_vs_current": 0.12,
        "mean_test_delta_vs_current": -0.02,
        "max_test_delta_vs_current": 0.04,
        "pass_seed_robustness": False,
        "recommended_action": "keep_current_registry",
    }])
    write_csv(tmp_path / "seed_decisions.csv", [
        {
            "region": "NL",
            "fold": 3,
            "source_rescue_experiment_id": "raw_graph",
            "val_delta_vs_current": 0.1,
            "test_delta_vs_current": 0.04,
            "validation_improved": False,
            "test_improved": False,
        },
        {
            "region": "NL",
            "fold": 3,
            "source_rescue_experiment_id": "raw_graph",
            "val_delta_vs_current": -0.02,
            "test_delta_vs_current": -0.08,
            "validation_improved": True,
            "test_improved": True,
        },
    ])
    write_csv(tmp_path / "candidates.csv", [])
    args = SimpleNamespace(
        closeout_decisions_csv=str(tmp_path / "closeout.csv"),
        candidate_metrics_csv=str(tmp_path / "candidates.csv"),
        seedrob_decisions_csv=str(tmp_path / "seed_decisions.csv"),
        seedrob_summary_csv=str(tmp_path / "seed_summary.csv"),
        output_dir=str(tmp_path / "out"),
    )

    summary = mod.summarize(args)
    taxonomy = pd.read_csv(tmp_path / "out" / "stage_j_failure_taxonomy.csv")
    flat = pd.read_csv(tmp_path / "out" / "stage_j_candidate_flat.csv")

    assert summary["n_flat_rows"] == 2
    assert "seed_unstable_audit_helpful" in set(taxonomy["stage_k_failure_class"])
    assert "validation_audit_mismatch" in set(taxonomy["stage_k_failure_class"])
    nl = flat[flat["region"].eq("NL")].iloc[0]
    assert nl["stage_k_next_action"] == "try_regularized_graph_summary_multiseed"


def test_stage_k_regularized_graph_preparer_emits_compact_multiseed_grid(tmp_path):
    mod = load_script("64_prepare_pricefm_stage_k_regularized_graph_pilot.py")
    data_cfg = tmp_path / "data.yaml"
    data_cfg.write_text(yaml.safe_dump({
        "pricefm": {
            "regions": [
                "DE_LU", "AT", "BE", "CZ", "DK_1", "DK_2",
                "FR", "NL", "NO_2", "PL", "SE_4",
            ]
        }
    }, sort_keys=False))
    template = {
        "pricefm_desn_experiment_grid": {
            "grid_id": "unit_template",
            "purpose": "unit",
            "base": {
                "data_config": str(data_cfg),
                "generated_root": str(tmp_path / "generated"),
                "run_root": str(tmp_path / "runs"),
            },
            "scope": {"regions": [], "folds": [], "quantiles": [0.5]},
            "fixed": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    }
    (tmp_path / "template.yaml").write_text(yaml.safe_dump(template, sort_keys=False))
    write_csv(tmp_path / "source.csv", [{
        "region": "DE_LU",
        "fold": 1,
        "experiment_id": "stagej_raw",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "feature_policy": "graph_khop",
        "graph_degree": 2,
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.25,
        "projection_scale": 1.0,
        "tau0": 0.001,
        "seed": 20260623,
        "stage_k_failure_class": "validation_audit_mismatch",
        "stage_k_next_action": "try_regularized_graph_summary_multiseed",
        "val_delta_vs_current": -0.1,
    }])
    args = SimpleNamespace(
        template_grid_config=str(tmp_path / "template.yaml"),
        source_csv=str(tmp_path / "source.csv"),
        output_grid_config=str(tmp_path / "grid.yaml"),
        grid_id="unit_stage_k",
        generated_root=str(tmp_path / "generated"),
        run_root=str(tmp_path / "runs"),
        summary_dir=str(tmp_path / "summary"),
        seeds="101,102",
        actions="try_regularized_graph_summary_multiseed",
        max_rows=10,
        max_variants_per_row=4,
        candidate_source="unit_stage_k",
        stage_name="stage_k_regularized_graph",
        experiment_id_prefix="stagek",
        target_label="stage_k_regularized_graph_validation",
        launch_key="stage_k_regularized_graph",
        summary_prefix="stage_k_regularized_graph",
        write=True,
    )

    summary = mod.prepare(args)
    grid = yaml.safe_load((tmp_path / "grid.yaml").read_text())[
        "pricefm_desn_experiment_grid"
    ]
    policies = {exp["feature_policy"] for exp in grid["experiments"]}
    seeds = {exp["seed"] for exp in grid["experiments"]}

    assert summary["n_experiments"] == 8
    assert {"target_only", "graph_summary_mean", "graph_summary_mean_std"}.issubset(policies)
    assert seeds == {101, 102}
    assert all(exp["selection_is_validation_only"] for exp in grid["experiments"])
    assert {exp["test_metrics_role"] for exp in grid["experiments"]} == {"audit_only"}
