"""Tests for Stage-N PriceFM underperformance closeout."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd


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


stage_n_closeout = load_script("74_closeout_pricefm_stage_n_underperformance.py")


def write_metric(run_root, exp_id, region, fold, rows, status="completed"):
    cell = run_root / exp_id / "cells" / ("region={}".format(region)) / ("fold={}".format(fold))
    model = cell / "model"
    model.mkdir(parents=True)
    pd.DataFrame(rows).to_csv(model / "metric_summary.csv", index=False)
    pd.DataFrame([{
        "region": region,
        "fold": fold,
        "status": status,
        "started_at": "2026-06-25T00:00:00Z",
        "ended_at": "2026-06-25T00:00:01Z",
        "elapsed_seconds": 1.0,
        "message": "unit",
    }]).to_csv(run_root / exp_id / "cell_status.csv", index=False)


def metric_rows(method, val_aql, test_aql):
    return [
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
    ]


def manifest_rows():
    common = {
        "stage": "unit_stage_n",
        "priority": 0,
        "lag_window": 96,
        "feature_policy": "graph_khop",
        "feature_dim": 80,
        "projection_scale": 1.0,
        "depth": 2,
        "units": "[80, 80]",
        "alpha": 0.4,
        "rho": 0.9,
        "input_scale": 0.35,
        "recurrent_sparsity": 0.05,
        "state_output": "final_layer",
        "tau0": 1.0e-3,
        "seed": 20260625,
        "graph_degree": 1,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": "unit_hash",
        "input_scope": "pricefm_graph_khop_degree1",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_khop",
        "candidate_family": "graph_geometry",
        "factor_changed": "base",
        "target_tier": "severe",
        "stage_n_rescue_reason": "unit",
        "selection_rule": "median_validation_AQL_only",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
    }
    rows = []
    for exp_id, factor in [
        ("exp_a_val_best_test_bad", "alpha_low"),
        ("exp_b_test_best", "input_scale_low"),
        ("exp_c_promote", "d2_120"),
    ]:
        row = dict(common)
        row["id"] = exp_id
        row["factor_changed"] = factor
        rows.append(row)
    return pd.DataFrame(rows)


def current_surface_rows():
    return pd.DataFrame([
        {
            "region": "AA",
            "fold": 1,
            "best_local_method": "qdesn_exal_rhs_ns_exact_chunked",
            "experiment_id": "current_aa",
            "median_selection_AQL": 10.0,
            "median_test_AQL": 10.0,
            "pricefm_AQL": 8.0,
            "decision_label": "pricefm_better",
            "information_set": "pricefm_graph_inputs",
        },
        {
            "region": "BB",
            "fold": 2,
            "best_local_method": "qdesn_al_rhs_ns_exact_chunked",
            "experiment_id": "current_bb",
            "median_selection_AQL": 8.0,
            "median_test_AQL": 9.0,
            "pricefm_AQL": 7.5,
            "decision_label": "pricefm_better",
            "information_set": "pricefm_graph_inputs",
        },
    ])


def make_args(tmp_path):
    manifest = tmp_path / "manifest.csv"
    current = tmp_path / "current.csv"
    run_root = tmp_path / "runs"
    out_dir = tmp_path / "out"
    manifest_rows().to_csv(manifest, index=False)
    current_surface_rows().to_csv(current, index=False)

    write_metric(
        run_root,
        "exp_a_val_best_test_bad",
        "AA",
        1,
        metric_rows("qdesn_exal_rhs_ns_exact_chunked", val_aql=7.0, test_aql=12.0),
        status="skipped_complete",
    )
    write_metric(
        run_root,
        "exp_b_test_best",
        "AA",
        1,
        metric_rows("qdesn_exal_rhs_ns_exact_chunked", val_aql=8.0, test_aql=9.0),
    )
    write_metric(
        run_root,
        "exp_c_promote",
        "BB",
        2,
        metric_rows("qdesn_al_rhs_ns_exact_chunked", val_aql=7.0, test_aql=8.5),
    )

    return type("Args", (), {
        "manifest_csv": str(manifest),
        "run_root": str(run_root),
        "current_decision_surface_csv": str(current),
        "output_dir": str(out_dir),
        "force": True,
        "validation_tolerance": 0.0,
        "test_veto_tolerance": 0.0,
        "pricefm_close_delta": 0.25,
    })()


def test_stage_n_closeout_separates_validation_selection_from_test_oracle(tmp_path):
    args = make_args(tmp_path)
    summary = stage_n_closeout.closeout(args)

    out = Path(args.output_dir)
    validation = pd.read_csv(out / "validation_selected_closeout.csv")
    oracle = pd.read_csv(out / "test_oracle_diagnostics.csv")
    instability = pd.read_csv(out / "selection_instability_audit.csv")
    promotions = pd.read_csv(out / "promotion_candidates.csv")

    aa_validation = validation[validation["region"].eq("AA")].iloc[0]
    aa_oracle = oracle[oracle["region"].eq("AA")].iloc[0]
    aa_instability = instability[instability["region"].eq("AA")].iloc[0]

    assert aa_validation["id"] == "exp_a_val_best_test_bad"
    assert aa_validation["promotion_decision"] == "validation_gain_test_veto"
    assert aa_oracle["id"] == "exp_b_test_best"
    assert aa_instability["instability_label"] == "oracle_gain_missed_by_validation"

    assert set(promotions["region"]) == {"BB"}
    assert summary["validation_selected_n_region_folds"] == 2
    assert summary["validation_selected_promotion_recommended"] == 1
    assert summary["missing_metric_rows"] == 0


def test_stage_n_closeout_writes_expected_artifacts(tmp_path):
    args = make_args(tmp_path)
    stage_n_closeout.closeout(args)
    out = Path(args.output_dir)
    expected = {
        "candidate_method_metrics.csv",
        "stage_n_cell_method_metrics.csv",
        "validation_selected_closeout.csv",
        "test_oracle_diagnostics.csv",
        "selection_instability_audit.csv",
        "split_shift_summary.csv",
        "horizon_gap_summary.csv",
        "selection_rule_sensitivity.csv",
        "selection_rule_selected_rows.csv",
        "promotion_candidates.csv",
        "remaining_pricefm_gap.csv",
        "method_summary.csv",
        "factor_summary.csv",
        "closeout_health.csv",
        "stage_n_underperformance_closeout_report.md",
        "summary.json",
    }
    assert expected.issubset({p.name for p in out.iterdir()})

    rules = pd.read_csv(out / "selection_rule_sensitivity.csv")
    assert set(rules["rule_id"]) == {
        "val_aql_min",
        "val_mae_min",
        "val_rmse_min",
        "robust_rank_val_aql_mae_rmse",
    }
    assert not rules["selection_uses_test_metrics"].any()
