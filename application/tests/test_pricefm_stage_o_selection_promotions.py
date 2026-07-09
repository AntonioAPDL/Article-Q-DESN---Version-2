"""Tests for Stage-O PriceFM selection and promotion hardening."""

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


stage_o = load_script("75_harden_pricefm_stage_o_selection_promotions.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def current_rows():
    base = {
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selection_metric_value": 10.0,
        "selection_AQL": 10.0,
        "selection_AQCR": 0.0,
        "selection_MAE": 20.0,
        "selection_RMSE": 30.0,
        "stage": "current",
        "priority": 0,
        "lag_window": 96,
        "feature_map": "window_reservoir_v1",
        "feature_dim": 120,
        "projection_scale": 1.0,
        "feature_policy": "target_only",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
        "graph_degree": "",
        "graph_source": "",
        "graph_hash": "",
        "depth": 1,
        "units": "[120]",
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "recurrent_sparsity": 0.05,
        "state_output": "final_layer",
        "quantiles": "[0.5]",
        "tau0": 0.001,
        "seed": 20260601,
        "data_config": "old_data.yaml",
        "full_config": "old_full.yaml",
        "run_dir": "old_run",
        "model_dir": "old_model",
        "adapter_dir": "old_adapter",
        "rationale": "old",
        "test_AQL": 11.0,
        "test_AQCR": 0.0,
        "test_MAE": 22.0,
        "test_RMSE": 33.0,
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selected_source": "current",
        "candidate_source": "current",
        "candidate_source_final": "current",
        "selection_is_validation_only": True,
        "selection_decision_rule": "current_rule",
        "final_decision": "current",
        "source_rescue_experiment_id": "",
        "source_current_experiment_id": "",
    }
    rows = []
    for region, fold, exp_id, sel, test in [
        ("AA", 1, "current_aa", 10.0, 11.0),
        ("BB", 2, "current_bb", 8.0, 9.0),
    ]:
        row = dict(base)
        row.update({
            "region": region,
            "fold": fold,
            "experiment_id": exp_id,
            "selection_AQL": sel,
            "selection_metric_value": sel,
            "test_AQL": test,
        })
        rows.append(row)
    return rows


def candidate_row(region, fold, exp_id, val_aql, test_aql, promoted):
    return {
        "region": region,
        "fold": fold,
        "cell_status": "completed",
        "metric_summary": "metric.csv",
        "run_dir": "application/data_local/pricefm/runs/unit/{}".format(exp_id),
        "id": exp_id,
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
        "tau0": 0.001,
        "seed": 20260625,
        "graph_degree": 1,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": "unit_hash",
        "input_scope": "pricefm_graph_khop_degree1",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_khop",
        "candidate_family": "graph_geometry",
        "factor_changed": "unit_factor",
        "target_tier": "severe",
        "stage_n_rescue_reason": "unit",
        "selection_rule": "median_validation_AQL_only",
        "selection_is_validation_only": True,
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "test_metrics_role": "audit_only",
        "method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "test_AQL": test_aql,
        "test_AQCR": 0.0,
        "test_MAE": 2.0 * test_aql,
        "test_RMSE": 3.0 * test_aql,
        "val_AQL": val_aql,
        "val_AQCR": 0.0,
        "val_MAE": 2.0 * val_aql,
        "val_RMSE": 3.0 * val_aql,
        "selection_view": "validation_selected",
        "current_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "current_experiment_id": "current_{}_{}".format(region, fold),
        "current_val_AQL": 10.0,
        "current_test_AQL": 11.0 if region == "AA" else 9.0,
        "pricefm_AQL": 8.0,
        "decision_label": "pricefm_better",
        "information_set": "pricefm_graph_inputs",
        "delta_val_vs_current": val_aql - 10.0,
        "delta_test_vs_current": test_aql - (11.0 if region == "AA" else 9.0),
        "delta_test_vs_pricefm": test_aql - 8.0,
        "validation_beats_current": val_aql < 10.0,
        "test_beats_current": test_aql < (11.0 if region == "AA" else 9.0),
        "test_beats_pricefm": test_aql < 8.0,
        "test_close_to_pricefm": test_aql <= 8.25,
        "promotion_recommended": promoted,
        "promotion_decision": "promote_validation_and_test_gain" if promoted else "validation_gain_test_veto",
    }


def write_stage_n_closeout(tmp_path):
    closeout = tmp_path / "closeout"
    promotion = candidate_row("AA", 1, "promote_aa", 7.0, 9.0, True)
    veto = candidate_row("BB", 2, "veto_bb", 7.0, 10.0, False)
    oracle = candidate_row("BB", 2, "oracle_bb", 8.0, 8.5, True)
    write_csv(closeout / "promotion_candidates.csv", [promotion])
    write_csv(closeout / "validation_selected_closeout.csv", [promotion, veto])
    write_csv(closeout / "selection_rule_sensitivity.csv", [
        {
            "rule_id": "val_aql_min",
            "n_region_folds": 2,
            "n_test_improvements": 1,
            "n_beats_pricefm": 0,
            "n_promotions_strict": 1,
            "mean_test_delta_vs_current": 0.0,
            "median_test_delta_vs_current": 0.0,
            "mean_test_delta_vs_pricefm": 1.5,
            "median_test_delta_vs_pricefm": 1.5,
            "selection_uses_test_metrics": False,
            "method_counts": "{}",
        },
        {
            "rule_id": "robust_rank_val_aql_mae_rmse",
            "n_region_folds": 2,
            "n_test_improvements": 2,
            "n_beats_pricefm": 0,
            "n_promotions_strict": 2,
            "mean_test_delta_vs_current": -0.5,
            "median_test_delta_vs_current": -0.5,
            "mean_test_delta_vs_pricefm": 1.0,
            "median_test_delta_vs_pricefm": 1.0,
            "selection_uses_test_metrics": False,
            "method_counts": "{}",
        },
    ])
    selected = pd.DataFrame([promotion, oracle])
    selected["rule_id"] = ["val_aql_min", "robust_rank_val_aql_mae_rmse"]
    write_csv(closeout / "selection_rule_selected_rows.csv", selected.to_dict("records"))
    write_csv(closeout / "selection_instability_audit.csv", [
        {
            "region": "AA",
            "fold": 1,
            "validation_selected_id": "promote_aa",
            "test_oracle_id": "promote_aa",
            "same_candidate": True,
            "oracle_gain_missed_by_validation": False,
            "instability_label": "aligned",
        },
        {
            "region": "BB",
            "fold": 2,
            "validation_selected_id": "veto_bb",
            "test_oracle_id": "oracle_bb",
            "same_candidate": False,
            "oracle_gain_missed_by_validation": True,
            "instability_label": "oracle_gain_missed_by_validation",
        },
    ])
    horizon_rows = []
    for group, diff in [("1-24", -0.2), ("25-48", 0.1)]:
        horizon_rows.append({
            "region": "BB",
            "fold": 2,
            "horizon_group": group,
            "validation_selected_id": "veto_bb",
            "validation_selected_method": "qdesn_exal_rhs_ns_exact_chunked",
            "test_oracle_id": "oracle_bb",
            "test_oracle_method": "qdesn_exal_rhs_ns_exact_chunked",
            "validation_selected_val_AQL": 7.0,
            "validation_selected_test_AQL": 10.0,
            "test_oracle_val_AQL": 8.0,
            "test_oracle_test_AQL": 8.5,
            "oracle_minus_validation_test_AQL": diff,
            "oracle_better_on_test_group": diff < 0.0,
        })
    write_csv(closeout / "horizon_gap_summary.csv", horizon_rows)
    return closeout


def write_template(tmp_path):
    payload = {
        "pricefm_desn_experiment_grid": {
            "grid_id": "template",
            "purpose": "unit",
            "base": {
                "data_config": "application/config/pricefm_data_pipeline.yaml",
                "full_config": "application/config/example.yaml",
                "generated_root": "old_generated",
                "run_root": "old_runs",
            },
            "scope": {"regions": ["AA"], "folds": [1], "quantiles": [0.5]},
            "fixed": {"feature_map": "window_reservoir_v1"},
            "launch": {},
            "experiments": [],
        }
    }
    path = tmp_path / "template.yaml"
    path.write_text(yaml.safe_dump(payload, sort_keys=False))
    return path


def make_args(tmp_path):
    current = tmp_path / "current_median.csv"
    surface = tmp_path / "surface.csv"
    write_csv(current, current_rows())
    write_csv(surface, [
        {"region": "AA", "fold": 1, "local_AQL": 11.0, "pricefm_AQL": 8.0, "delta_abs": 3.0},
        {"region": "BB", "fold": 2, "local_AQL": 9.0, "pricefm_AQL": 8.0, "delta_abs": 1.0},
    ])
    return SimpleNamespace(
        current_median_registry_csv=str(current),
        current_decision_surface_csv=str(surface),
        stage_n_closeout_dir=str(write_stage_n_closeout(tmp_path)),
        stage_n_generated_root=str(tmp_path / "generated"),
        template_grid_config=str(write_template(tmp_path)),
        output_dir=str(tmp_path / "stage_o"),
        stage_p_grid_config=str(tmp_path / "stage_p.yaml"),
        stage_p_grid_id="unit_stage_p",
        stage_p_generated_root=str(tmp_path / "stage_p_generated"),
        stage_p_run_root=str(tmp_path / "stage_p_runs"),
        quantiles="0.1,0.5,0.9",
        force=True,
        write_stage_p_grid=True,
    )


def test_stage_o_patches_only_conservative_promotions_and_preserves_current_size(tmp_path):
    args = make_args(tmp_path)
    summary = stage_o.harden(args)

    out = Path(args.output_dir)
    patched = pd.read_csv(out / "patched_median_registry_candidate.csv")
    patches = pd.read_csv(out / "stage_o_median_patch_candidates.csv")
    do_not = pd.read_csv(out / "stage_o_do_not_promote.csv")

    assert summary["n_current_median_rows"] == 2
    assert summary["n_conservative_promotions"] == 1
    assert summary["n_do_not_promote"] == 1
    assert patched.shape[0] == 2
    assert patches["region"].tolist() == ["AA"]
    assert set(do_not["region"]) == {"BB"}
    assert patched.loc[patched["region"].eq("AA"), "experiment_id"].iloc[0] == "promote_aa"
    assert patched.loc[patched["region"].eq("BB"), "experiment_id"].iloc[0] == "current_bb"
    assert bool(summary["stage_m_surface_changed"]) is False
    assert bool(summary["test_oracle_promoted"]) is False


def test_stage_o_writes_rule_audit_and_stage_p_quantile_grid(tmp_path):
    args = make_args(tmp_path)
    summary = stage_o.harden(args)

    out = Path(args.output_dir)
    rules = pd.read_csv(out / "stage_o_selection_rule_audit.csv")
    grid = yaml.safe_load(Path(args.stage_p_grid_config).read_text())["pricefm_desn_experiment_grid"]
    local_grid = yaml.safe_load((out / "stage_p_quantile_confirmation_grid.yaml").read_text())["pricefm_desn_experiment_grid"]

    assert summary["best_diagnostic_validation_only_rule"] == "robust_rank_val_aql_mae_rmse"
    assert "adopt_without_confirmation" in rules.columns
    assert not rules["adopt_without_confirmation"].any()
    assert summary["n_stage_p_quantile_experiments"] == 3
    assert grid["grid_id"] == "unit_stage_p"
    assert len(grid["experiments"]) == 3
    assert [exp["quantile"] for exp in grid["experiments"]] == [0.1, 0.5, 0.9]
    assert local_grid["grid_id"] == "unit_stage_p"
