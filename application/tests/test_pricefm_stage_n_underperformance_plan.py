"""Tests for Stage-N PriceFM underperformance search preparation."""

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


stage_n_mod = load_script("73_prepare_pricefm_stage_n_underperformance_broad_search.py")
grid_mod = load_script("12_prepare_desn_experiment_grid.py")


TEMPLATE = ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_region_panel_20260606.yaml"


def surface_rows():
    return pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "best_local_method": "qdesn",
            "model_family": "qdesn",
            "information_set": "local",
            "local_AQL": 12.0,
            "pricefm_AQL": 10.0,
            "delta_abs": 2.0,
            "delta_rel": 0.20,
            "local_wins": False,
            "decision_label": "pricefm_wins",
            "stage_c_quantile_decision": "pricefm_better",
            "stage_c_recommendation": "rescue",
            "experiment_id": "surface_delu",
            "selected_method_id_median": "qdesn_exal_rhs_ns_exact_chunked",
            "median_selection_AQL": 8.0,
            "median_test_AQL": 12.0,
            "feature_policy": "target_only",
            "input_scope": "local_target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph_degree": "",
            "lag_window": 96,
            "depth": 1,
            "units": "[120]",
            "seed": 20260625,
            "run_dir": "runs/surface_delu",
        },
        {
            "region": "HU",
            "fold": 2,
            "best_local_method": "qdesn",
            "model_family": "qdesn",
            "information_set": "graph",
            "local_AQL": 10.5,
            "pricefm_AQL": 10.0,
            "delta_abs": 0.5,
            "delta_rel": 0.05,
            "local_wins": False,
            "decision_label": "pricefm_wins",
            "stage_c_quantile_decision": "pricefm_better",
            "stage_c_recommendation": "rescue",
            "experiment_id": "surface_hu",
            "selected_method_id_median": "qdesn_exal_rhs_ns_exact_chunked",
            "median_selection_AQL": 7.0,
            "median_test_AQL": 10.5,
            "feature_policy": "graph_khop",
            "input_scope": "pricefm_graph_khop_degree1",
            "spatial_information_set": "pricefm_released_graph_khop",
            "graph_degree": 1,
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "seed": 20260625,
            "run_dir": "runs/surface_hu",
        },
        {
            "region": "RO",
            "fold": 3,
            "best_local_method": "qdesn",
            "model_family": "qdesn",
            "information_set": "local",
            "local_AQL": 10.1,
            "pricefm_AQL": 10.0,
            "delta_abs": 0.1,
            "delta_rel": 0.01,
            "local_wins": False,
            "decision_label": "pricefm_wins",
            "stage_c_quantile_decision": "pricefm_better",
            "stage_c_recommendation": "monitor",
            "experiment_id": "surface_ro",
            "selected_method_id_median": "qdesn_al_rhs_ns_exact_chunked",
            "median_selection_AQL": 7.5,
            "median_test_AQL": 10.1,
            "feature_policy": "target_only",
            "input_scope": "local_target_only",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "graph_degree": "",
            "lag_window": 96,
            "depth": 1,
            "units": "[80]",
            "seed": 20260625,
            "run_dir": "runs/surface_ro",
        },
        {
            "region": "LV",
            "fold": 1,
            "best_local_method": "qdesn",
            "model_family": "qdesn",
            "information_set": "graph",
            "local_AQL": 9.9,
            "pricefm_AQL": 10.0,
            "delta_abs": -0.1,
            "delta_rel": -0.01,
            "local_wins": True,
            "decision_label": "qdesn_wins_close",
            "stage_c_quantile_decision": "qdesn_better",
            "stage_c_recommendation": "monitor",
            "experiment_id": "surface_lv",
            "selected_method_id_median": "qdesn_exal_rhs_ns_exact_chunked",
            "median_selection_AQL": 6.0,
            "median_test_AQL": 9.9,
            "feature_policy": "graph_khop",
            "input_scope": "pricefm_graph_khop_degree2",
            "spatial_information_set": "pricefm_released_graph_khop",
            "graph_degree": 2,
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "seed": 20260625,
            "run_dir": "runs/surface_lv",
        },
    ])


def median_rows():
    rows = []
    for row in surface_rows().to_dict("records"):
        rows.append({
            "region": row["region"],
            "fold": row["fold"],
            "selected_on_split": "val",
            "selected_on_unit": "original",
            "selection_metric": "AQL",
            "selected_method_id": row["selected_method_id_median"],
            "selection_metric_value": row["median_selection_AQL"],
            "selection_AQL": row["median_selection_AQL"],
            "selection_AQCR": 0.0,
            "selection_MAE": 2.0 * row["median_selection_AQL"],
            "selection_RMSE": 3.0 * row["median_selection_AQL"],
            "experiment_id": row["experiment_id"].replace("surface", "median"),
            "stage": "unit",
            "priority": 0,
            "lag_window": row["lag_window"],
            "feature_map": "window_reservoir_v1",
            "feature_dim": 120,
            "projection_scale": 1.0,
            "feature_policy": row["feature_policy"],
            "input_scope": row["input_scope"],
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": row["spatial_information_set"],
            "graph_degree": row["graph_degree"],
            "graph_source": "PriceFM.graph_adj_matrix" if row["feature_policy"] == "graph_khop" else "",
            "graph_hash": "unit_hash",
            "depth": row["depth"],
            "units": row["units"],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.35,
            "recurrent_sparsity": 0.05,
            "state_output": "final_layer",
            "quantiles": "[0.5]",
            "tau0": 1.0e-3,
            "seed": row["seed"],
            "data_config": "data.yaml",
            "full_config": "full.yaml",
            "run_dir": row["run_dir"],
            "model_dir": "model",
            "adapter_dir": "adapter",
            "rationale": "unit",
            "test_AQL": row["median_test_AQL"],
            "test_AQCR": 0.0,
            "test_MAE": 2.0 * row["median_test_AQL"],
            "test_RMSE": 3.0 * row["median_test_AQL"],
            "method_id": row["selected_method_id_median"],
            "selected_source": "graph" if row["feature_policy"] == "graph_khop" else "local",
            "candidate_source": "unit",
            "candidate_source_final": "unit",
            "selection_is_validation_only": True,
            "selection_decision_rule": "median_validation_AQL_only",
            "final_decision": "promote_candidate",
            "source_rescue_experiment_id": "",
            "source_current_experiment_id": row["experiment_id"],
        })
    return pd.DataFrame(rows)


def make_args(tmp_path, **overrides):
    surface = tmp_path / "surface.csv"
    median = tmp_path / "median.csv"
    surface_rows().to_csv(surface, index=False)
    median_rows().to_csv(median, index=False)
    values = {
        "template_grid_config": str(TEMPLATE),
        "decision_surface_csv": str(surface),
        "median_registry_csv": str(median),
        "output_grid_config": str(tmp_path / "stage_n_grid.yaml"),
        "grid_id": "unit_stage_n",
        "generated_root": str(tmp_path / "generated"),
        "run_root": str(tmp_path / "runs"),
        "summary_dir": str(tmp_path / "summary"),
        "stage_name": "unit_stage_n",
        "experiment_id_prefix": "unitn",
        "candidate_source": "unit_stage_n_source",
        "target_label": "unit_stage_n_validation",
        "severe_delta": 0.70,
        "moderate_delta": 0.25,
        "near_win_delta": 0.25,
        "max_variants_priority0": 12,
        "max_variants_priority1": 8,
        "max_variants_priority2": 3,
        "include_slight": True,
        "include_fragile_near_wins": False,
        "include_d4_smoke": False,
        "write": True,
    }
    values.update(overrides)
    return type("Args", (), values)()


def test_stage_n_targets_tiers_and_cleanup_metadata(tmp_path):
    args = make_args(tmp_path)
    summary = stage_n_mod.prepare(args)
    assert summary["n_underperformance_rows"] == 3
    assert summary["n_fragile_near_wins"] == 1
    assert summary["tier_counts"] == {"severe": 1, "moderate": 1, "slight": 1}

    tiers = pd.read_csv(tmp_path / "summary" / "target_tiers.csv")
    assert set(tiers["target_tier"]) == {"severe", "moderate", "slight"}
    assert "feature_policy_surface" in tiers.columns
    assert "experiment_id_surface" in tiers.columns

    grid = yaml.safe_load((tmp_path / "stage_n_grid.yaml").read_text())["pricefm_desn_experiment_grid"]
    assert grid["scope"]["quantiles"] == [0.50]
    assert grid["fixed"]["shrink_intercept"] is False
    assert "*.rdata" in grid["fixed"]["artifact_hygiene"]["clean_model_patterns"]
    assert set(grid["launch"]) == {
        "stage_n_dry_run_gate",
        "stage_n_smoke",
        "stage_n_priority0",
    }
    assert grid["launch"]["stage_n_smoke"]["ids"]


def test_stage_n_candidates_preserve_validation_only_contract(tmp_path):
    args = make_args(tmp_path)
    stage_n_mod.prepare(args)
    candidates = pd.read_csv(tmp_path / "summary" / "candidate_family_matrix.csv")
    assert not candidates.empty
    assert set(candidates["selection_rule"]) == {"median_validation_AQL_only"}
    assert set(candidates["selected_on_split"]) == {"val"}
    assert set(candidates["test_metrics_role"]) == {"audit_only"}
    assert set(candidates["selection_is_validation_only"]) == {True}

    severe = candidates[candidates["target_tier"].eq("severe")]
    assert "graph_khop" in set(severe["feature_policy"])
    assert "severe_target_only_graph_conversion" in set(severe["stage_n_rescue_reason"])

    moderate = candidates[candidates["target_tier"].eq("moderate")]
    assert "target_only_guardrail" in set(moderate["candidate_family"])
    assert "graph_geometry" in set(moderate["candidate_family"])


def test_stage_n_rejects_non_validation_registry(tmp_path):
    args = make_args(tmp_path)
    median = median_rows()
    median.loc[0, "selected_on_split"] = "test"
    Path(args.median_registry_csv).write_text(median.to_csv(index=False))
    with pytest.raises(ValueError, match="validation/original/AQL"):
        stage_n_mod.prepare(args)


def test_stage_n_grid_metadata_flows_to_generated_configs(tmp_path):
    args = make_args(tmp_path)
    summary = stage_n_mod.prepare(args)
    grid = grid_mod.load_grid(summary["output_grid_config"])
    rows = grid_mod.prepare_grid(grid, tmp_path / "prepared", write=True)
    assert rows
    first = rows[0]
    assert first["candidate_family"]
    assert first["target_tier"] in {"severe", "moderate", "slight"}
    assert first["test_metrics_role"] == "audit_only"
    assert first["selection_rule"] == "median_validation_AQL_only"

    full_path = Path(first["full_config"])
    if not full_path.is_absolute():
        full_path = ROOT / full_path
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    metadata = full["comparison_metadata"]
    assert metadata["candidate_family"] == first["candidate_family"]
    assert metadata["target_tier"] == first["target_tier"]
    assert metadata["selection_rule"] == "median_validation_AQL_only"
    assert metadata["test_metrics_role"] == "audit_only"
    assert metadata["median_registry"]["source_experiment_id"].startswith("median_")
