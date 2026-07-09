"""Tests for preparing the PriceFM Stage-C median grid."""

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


def manifest_row(region, fold, queue, priority, caution="new_region_unverified"):
    return {
        "region": region,
        "fold": fold,
        "queue": queue,
        "stage_c_priority": priority,
        "recommended_next_gate": "median_screen",
        "selection_split": "val",
        "audit_split": "test",
        "selection_metric": "AQL",
        "selection_unit": "original",
        "target_quantile": 0.50,
        "paper_quantiles": "0.10,0.25,0.45,0.50,0.55,0.75,0.90",
        "candidate_strategy": "stage_c_local_median",
        "allowed_final_methods": "qdesn_exal_rhs_ns_exact_chunked,qdesn_al_rhs_ns_exact_chunked",
        "input_scope": "local_target_only",
        "output_scope": "target_region_path",
        "feature_policy": "target_only",
        "lead_covariate_status": "realized_ex_post",
        "spatial_information_set": "local_only_not_pricefm_graph",
        "shrink_intercept": False,
        "qdesn_likelihoods": "al,exal",
        "beta_prior": "rhs_ns",
        "exact_chunking": True,
        "cleanup_binary_artifacts": True,
        "preserve_pricefm_as_benchmark_only": True,
        "phase1_AQL": 7.0,
        "phase1_MAE": 12.0,
        "phase1_RMSE": 18.0,
        "median": 50.0,
        "spread_p99_p01": 500.0,
        "tail_range": 1000.0,
        "negative_rate": 0.01,
        "zero_rate": 0.0,
        "min": -10.0,
        "p01": 1.0,
        "p99": 501.0,
        "max": 900.0,
        "degree1_n": 4,
        "degree2_n": 12,
        "degree1_regions": "A|B",
        "degree2_regions": "A|B|C",
        "rationale": "unit_test",
        "caution_label": caution,
        "evaluated_folds": "",
    }


def manifest():
    rows = [
        manifest_row("AT", 1, "completion_folds", 0, caution="narrow_existing_win"),
        manifest_row("AT", 3, "completion_folds", 0, caution="narrow_existing_win"),
        manifest_row("BE", 1, "diverse_new_regions", 1),
        manifest_row("BE", 2, "diverse_new_regions", 1),
    ]
    return pd.DataFrame(rows)


def template_payload():
    return {
        "pricefm_desn_experiment_grid": {
            "grid_id": "template",
            "purpose": "unit test",
            "base": {
                "data_config": "application/config/pricefm_data_pipeline.yaml",
                "full_config": "application/config/pricefm_desn_model_median_de_lu_fold1_authoritative_reservoir_corrected_20260602.yaml",
                "generated_root": "application/data_local/pricefm/experiment_grids/template",
                "run_root": "application/data_local/pricefm/runs/template",
            },
            "scope": {
                "regions": ["AT"],
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
                "exact_equivalence_train_rows": 1000,
            },
            "launch": {},
            "experiments": [],
            "experiment_blocks": [],
        }
    }


def test_stage_c_grid_generates_one_experiment_per_row_and_geometry():
    mod = load_script("51_prepare_pricefm_stage_c_median_grid.py")
    payload = mod.build_grid(
        template_payload(),
        manifest(),
        "stage_c_test",
        "application/data_local/pricefm/experiment_grids/stage_c_test",
        "application/data_local/pricefm/runs/stage_c_test",
    )
    experiments = payload["pricefm_desn_experiment_grid"]["experiments"]

    assert len(experiments) == len(manifest()) * 3
    assert sum(1 for exp in experiments if exp["priority"] == 0) == 6
    assert sum(1 for exp in experiments if exp["priority"] == 1) == 6
    assert all(len(exp["regions"]) == 1 for exp in experiments)
    assert all(len(exp["folds"]) == 1 for exp in experiments)
    assert all(exp["stage"] == "stage_c_local_median" for exp in experiments)
    assert all(exp["feature_policy"] == "target_only" for exp in experiments)
    assert all(exp["input_scope"] == "local_target_only" for exp in experiments)
    assert all("stage_c_manifest" in exp["median_registry"] for exp in experiments)
    assert all(exp["median_registry"]["queue"] in {"completion_folds", "diverse_new_regions"} for exp in experiments)
    assert not any(exp["regions"] == ["FI"] and exp["folds"] == [3] for exp in experiments)


def test_stage_c_grid_rejects_fi_fold3_in_generic_manifest():
    mod = load_script("51_prepare_pricefm_stage_c_median_grid.py")
    bad = manifest()
    bad = pd.concat(
        [bad, pd.DataFrame([manifest_row("FI", 3, "completion_folds", 0, caution="existing_fold_exception")])],
        ignore_index=True,
    )

    try:
        mod.validate_manifest(bad)
    except ValueError as exc:
        assert "FI fold 3" in str(exc)
    else:
        raise AssertionError("FI fold 3 should not be allowed in generic Stage-C median grid")


def test_stage_c_grid_rejects_non_local_output_paths():
    mod = load_script("51_prepare_pricefm_stage_c_median_grid.py")

    try:
        mod.build_grid(
            template_payload(),
            manifest(),
            "stage_c_test",
            "application/data_local/pricefm/experiment_grids/stage_c_test",
            "/tmp/not_pricefm",
        )
    except ValueError as exc:
        assert "application/data_local/pricefm" in str(exc)
    else:
        raise AssertionError("non-PriceFM local output path should fail")


def test_stage_c_grid_yaml_loads_with_shared_materializer(tmp_path):
    mod = load_script("51_prepare_pricefm_stage_c_median_grid.py")
    prep = load_script("12_prepare_desn_experiment_grid.py")
    payload = mod.build_grid(
        template_payload(),
        manifest(),
        "stage_c_test",
        "application/data_local/pricefm/experiment_grids/stage_c_test",
        "application/data_local/pricefm/runs/stage_c_test",
    )
    path = tmp_path / "stage_c_grid.yaml"
    path.write_text(yaml.safe_dump(payload, sort_keys=False))

    grid = prep.load_grid(path)
    rows = prep.prepare_grid(grid, grid["base"]["generated_root"], write=False)
    assert len(rows) == len(manifest()) * 3
    assert all(row["stage"] == "stage_c_local_median" for row in rows)
    assert all(row["median_registry"] for row in rows)
    assert sorted({row["priority"] for row in rows}) == [0, 1]
