"""Tests for Stage-Q PriceFM near-miss refinement preparation."""

from pathlib import Path
import importlib.util
import sys

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


stage_q = load_script("76_prepare_pricefm_stage_q_nearmiss_refinement.py")


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_yaml(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        yaml.safe_dump(payload, f, sort_keys=False)


def flags_rows():
    return [
        {
            "region": "NL",
            "fold": 3,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 6.54,
            "AQCR": 0.0,
            "MAE": 16.0,
            "RMSE": 24.0,
            "pricefm_phase1_AQL": 6.41,
            "delta_abs": 0.13,
            "delta_rel": 0.02,
            "decision_label": "local_close_to_pricefm",
        },
        {
            "region": "RO",
            "fold": 1,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 7.89,
            "AQCR": 0.0,
            "MAE": 20.0,
            "RMSE": 29.0,
            "pricefm_phase1_AQL": 7.57,
            "delta_abs": 0.32,
            "delta_rel": 0.04,
            "decision_label": "local_close_to_pricefm",
        },
        {
            "region": "SE_4",
            "fold": 1,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 7.25,
            "AQCR": 0.0,
            "MAE": 18.0,
            "RMSE": 25.0,
            "pricefm_phase1_AQL": 7.70,
            "delta_abs": -0.45,
            "delta_rel": -0.06,
            "decision_label": "local_beats_pricefm",
        },
        {
            "region": "AT",
            "fold": 3,
            "method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "split": "test",
            "unit": "original",
            "AQL": 7.28,
            "AQCR": 0.0,
            "MAE": 18.0,
            "RMSE": 28.0,
            "pricefm_phase1_AQL": 6.76,
            "delta_abs": 0.52,
            "delta_rel": 0.078,
            "decision_label": "local_lags_pricefm",
        },
    ]


def registry_rows():
    base = {
        "selected_on_split": "val",
        "selected_on_unit": "original",
        "selection_metric": "AQL",
        "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
        "selection_metric_value": 5.0,
        "selection_AQL": 5.0,
        "selection_AQCR": 0.0,
        "selection_MAE": 10.0,
        "selection_RMSE": 15.0,
        "stage": "stage_p",
        "priority": 0,
        "lag_window": 96,
        "feature_map": "window_reservoir_v1",
        "feature_dim": 120,
        "projection_scale": 1.0,
        "feature_policy": "graph_khop",
        "input_scope": "pricefm_graph_khop_degree2",
        "output_scope": "target_region_path",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "pricefm_released_graph_khop",
        "graph_degree": 2,
        "graph_source": "PriceFM.graph_adj_matrix",
        "graph_hash": "hash",
        "depth": 1,
        "units": "[120]",
        "alpha": 0.35,
        "rho": 0.9,
        "input_scale": 0.1875,
        "recurrent_sparsity": 0.05,
        "state_output": "final_layer",
        "quantiles": "[0.5]",
        "tau0": 0.001,
        "seed": 20260626,
        "data_config": "data.yaml",
        "full_config": "full.yaml",
        "run_dir": "run",
        "model_dir": "model",
        "adapter_dir": "adapter",
        "rationale": "unit",
        "test_AQL": 8.0,
        "test_AQCR": 0.0,
        "test_MAE": 16.0,
        "test_RMSE": 24.0,
    }
    rows = []
    for region, fold, exp_id, units, alpha, input_scale, degree in [
        ("NL", 3, "nl_base", "[120]", 0.35, 0.1875, 2),
        ("RO", 1, "ro_base", "[120, 120]", 0.50, 0.1750, 2),
        ("SE_4", 1, "se_base", "[80, 80]", 0.25, 0.35, 1),
        ("AT", 3, "at_base", "[160, 160]", 0.50, 0.50, 2),
    ]:
        row = dict(base)
        row.update({
            "region": region,
            "fold": fold,
            "experiment_id": exp_id,
            "units": units,
            "depth": len(stage_q.parse_units(units)),
            "alpha": alpha,
            "input_scale": input_scale,
            "graph_degree": degree,
            "input_scope": "pricefm_graph_khop_degree{}".format(degree),
        })
        rows.append(row)
    return rows


def surface_rows():
    return [
        {"region": "NL", "fold": 3, "local_AQL": 6.78, "pricefm_AQL": 6.41, "best_local_method": "current"},
        {"region": "RO", "fold": 1, "local_AQL": 8.30, "pricefm_AQL": 7.57, "best_local_method": "current"},
        {"region": "SE_4", "fold": 1, "local_AQL": 8.48, "pricefm_AQL": 7.70, "best_local_method": "current"},
        {"region": "AT", "fold": 3, "local_AQL": 7.65, "pricefm_AQL": 6.76, "best_local_method": "current"},
    ]


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
                "regions": ["NL"],
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
                "default_jobs": 1,
                "qdesn_likelihoods": ["al", "exal"],
                "warm_start_enabled": True,
                "exact_equivalence_train_rows": 1000,
                "artifact_hygiene": {
                    "enabled": True,
                    "clean_adapter_patterns": ["X_*.csv"],
                    "clean_model_patterns": ["*.rds"],
                    "preserve_patterns": ["metric_summary.csv"],
                },
            },
            "experiments": [],
        }
    }


def test_stage_q_classifies_close_win_and_optional_rows():
    args = stage_q.parser().parse_args([])
    decisions = stage_q.classify_stage_p_rows(
        pd.DataFrame(flags_rows()),
        pd.DataFrame(registry_rows()),
        pd.DataFrame(surface_rows()),
        args,
    )

    labels = {
        (row.region, int(row.fold)): row.stage_q_decision
        for row in decisions.itertuples()
    }
    assert labels[("NL", 3)] == "near_miss_refine"
    assert labels[("RO", 1)] == "near_miss_refine"
    assert labels[("SE_4", 1)] == "promote_article_candidate"
    assert labels[("AT", 3)] == "optional_modest_gap_refine"
    assert decisions.loc[decisions.region.eq("SE_4"), "stage_q_priority"].iloc[0] == 90


def test_stage_q_prepare_writes_guarded_grid_and_manifest(tmp_path):
    flags = tmp_path / "flags.csv"
    registry = tmp_path / "registry.csv"
    surface = tmp_path / "surface.csv"
    template = tmp_path / "template.yaml"
    out = tmp_path / "out"
    grid = tmp_path / "stage_q.yaml"
    write_csv(flags, flags_rows())
    write_csv(registry, registry_rows())
    write_csv(surface, surface_rows())
    write_yaml(template, template_grid())

    args = stage_q.parser().parse_args([
        "--stage-p-flags-csv", str(flags),
        "--stage-p-registry-csv", str(registry),
        "--current-decision-surface-csv", str(surface),
        "--template-grid-config", str(template),
        "--output-dir", str(out),
        "--stage-q-grid-config", str(grid),
        "--stage-q-generated-root", str(tmp_path / "generated"),
        "--stage-q-run-root", str(tmp_path / "runs"),
        "--max-variants-priority0", "5",
        "--max-variants-priority1", "3",
        "--write-grid", "true",
        "--force", "true",
    ])
    summary = stage_q.prepare(args)

    assert summary["n_promote_article_candidates"] == 1
    assert summary["n_priority0_nearmiss_targets"] == 2
    assert summary["n_priority1_optional_targets"] == 1
    assert summary["n_stage_q_priority0_experiments"] == 10
    assert summary["n_stage_q_priority1_experiments"] == 3
    assert summary["stage_m_surface_changed"] is False

    manifest = pd.read_csv(out / "stage_q_median_refinement_manifest.csv")
    assert set(manifest["priority"]) == {0, 1}
    assert not manifest["experiment_id"].duplicated().any()
    payload = yaml.safe_load(grid.read_text())
    grid_block = payload["pricefm_desn_experiment_grid"]
    assert grid_block["scope"]["quantiles"] == [0.5]
    assert grid_block["fixed"]["shrink_intercept"] is False
    assert "*.rds" in grid_block["fixed"]["artifact_hygiene"]["clean_model_patterns"]
