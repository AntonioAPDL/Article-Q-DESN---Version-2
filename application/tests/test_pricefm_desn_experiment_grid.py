"""Tests for non-launching PriceFM DESN experiment-grid preparation."""

from pathlib import Path
import importlib.util
import sys

import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

spec = importlib.util.spec_from_file_location(
    "pricefm_grid",
    ROOT / "application" / "scripts" / "pricefm" / "12_prepare_desn_experiment_grid.py",
)
grid_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grid_mod)

runner_spec = importlib.util.spec_from_file_location(
    "pricefm_grid_runner",
    ROOT / "application" / "scripts" / "pricefm" / "13_run_desn_experiment_grid.py",
)
runner_mod = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(runner_mod)

full_run_spec = importlib.util.spec_from_file_location(
    "pricefm_full_run",
    ROOT / "application" / "scripts" / "pricefm" / "pricefm_full_run.py",
)
full_run_mod = importlib.util.module_from_spec(full_run_spec)
full_run_spec.loader.exec_module(full_run_mod)

validator_spec = importlib.util.spec_from_file_location(
    "pricefm_reservoir_grid_validator",
    ROOT / "application" / "scripts" / "pricefm" / "14_validate_reservoir_grid_artifacts.py",
)
validator_mod = importlib.util.module_from_spec(validator_spec)
validator_spec.loader.exec_module(validator_mod)

GRID = ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_de_lu_refine_20260601.yaml"
RESERVOIR_GRID = ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_de_lu_reservoir_20260601.yaml"
CORRECTED_RESERVOIR_GRID = (
    ROOT
    / "application"
    / "config"
    / "pricefm_desn_experiment_grid_median_de_lu_reservoir_corrected_20260602.yaml"
)


def test_grid_spec_has_unique_experiments_and_required_controls():
    grid = grid_mod.load_grid(str(GRID))
    ids = [exp["id"] for exp in grid["experiments"]]
    assert len(ids) == len(set(ids))
    assert grid["scope"]["ranking_split"] == "val"
    assert grid["scope"]["audit_split"] == "test"
    assert grid["fixed"]["shrink_intercept"] is False
    assert grid["fixed"]["train_origin_limit"] == 3000
    assert {72, 96, 128, 144}.issubset({int(exp["lag_window"]) for exp in grid["experiments"]})
    assert {240, 360, 480, 720}.issubset({int(exp["feature_dim"]) for exp in grid["experiments"]})
    assert {1.0e-3} == {float(exp["tau0"]) for exp in grid["experiments"]}
    assert {"window_desn_v1"} == {
        str(exp.get("feature_map", grid["fixed"]["feature_map"]))
        for exp in grid["experiments"]
    }
    assert {0.35, 0.5, 0.75}.issubset({
        float(exp.get("projection_scale", grid["fixed"]["projection_scale"]))
        for exp in grid["experiments"]
    })


def test_prepare_grid_writes_configs_without_launching(tmp_path):
    grid = grid_mod.load_grid(str(GRID))
    rows = grid_mod.prepare_grid(grid, tmp_path / "grid", write=True)
    assert len(rows) == len(grid["experiments"])
    first = rows[0]
    full_path = ROOT / first["full_config"]
    if not full_path.exists():
        full_path = Path(first["full_config"])
    data_path = ROOT / first["data_config"]
    if not data_path.exists():
        data_path = Path(first["data_config"])
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    data = yaml.safe_load(data_path.read_text())["pricefm"]
    assert full["training"]["train_origin_limit"] == 3000
    assert full["rhs_ns"]["shrink_intercept"] is False
    assert full["scope"]["regions"] == ["DE_LU"]
    assert full["scope"]["folds"] == [1]
    assert "projection_scale" in full["adapter"]
    assert full["normal"]["vb_control"]["min_iter"] == 50
    assert full["normal"]["vb_control"]["max_iter"] == 100
    assert full["qdesn_vb"]["min_iter_elbo"] == 50
    assert full["qdesn_vb"]["max_iter"] == 100
    assert data["windows"]["lead_window"] == 96
    assert "run_qdesn" not in full
    assert (tmp_path / "grid" / "manifest.csv").exists()


def test_prepare_grid_supports_per_experiment_quantile_override(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_quantile_override"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["scope"]["quantiles"] = [0.10, 0.50, 0.90]
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "single_tau_010",
            "stage": "unit",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [2],
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.10,
        },
        {
            "id": "pair_tau_025_075",
            "stage": "unit",
            "priority": 0,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantiles": [0.25, 0.75],
        },
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))

    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert len(rows) == 2
    by_id = {row["id"]: row for row in rows}
    assert by_id["single_tau_010"]["quantiles"] == "[0.1]"
    assert by_id["single_tau_010"]["regions"] == '["DE_LU"]'
    assert by_id["single_tau_010"]["folds"] == "[2]"
    assert by_id["pair_tau_025_075"]["quantiles"] == "[0.25, 0.75]"

    first_full = yaml.safe_load((tmp_path / "generated" / "configs" / "full" / "single_tau_010.yaml").read_text())
    first = first_full["pricefm_desn_full"]
    assert first["scope"]["quantiles"] == [0.10]
    assert first["scope"]["regions"] == ["DE_LU"]
    assert first["scope"]["folds"] == [2]
    assert first["exact_equivalence"]["quantile"] == 0.10

    second_full = yaml.safe_load((tmp_path / "generated" / "configs" / "full" / "pair_tau_025_075.yaml").read_text())
    second = second_full["pricefm_desn_full"]
    assert second["scope"]["quantiles"] == [0.25, 0.75]


def test_prepare_grid_preserves_experiment_metadata(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_metadata"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "metadata_cell",
            "stage": "unit",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [1],
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
            "input_scope": "local_target_only",
            "output_scope": "target_region_path",
            "lead_covariate_status": "realized_ex_post",
            "spatial_information_set": "local_only_not_pricefm_graph",
            "final_decision": "promote_candidate",
            "candidate_source_final": "local_ar_unit",
            "median_registry": {
                "median_experiment_id": "median_cell",
                "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            },
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))

    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert rows[0]["input_scope"] == "local_target_only"
    assert rows[0]["spatial_information_set"] == "local_only_not_pricefm_graph"

    manifest = yaml.safe_load((tmp_path / "generated" / "configs" / "full" / "metadata_cell.yaml").read_text())
    metadata = manifest["pricefm_desn_full"]["comparison_metadata"]
    assert metadata["input_scope"] == "local_target_only"
    assert metadata["final_decision"] == "promote_candidate"
    assert metadata["median_registry"]["median_experiment_id"] == "median_cell"

    import pandas as pd

    csv_manifest = pd.read_csv(tmp_path / "generated" / "manifest.csv")
    assert csv_manifest.loc[0, "input_scope"] == "local_target_only"
    assert csv_manifest.loc[0, "candidate_source_final"] == "local_ar_unit"


def test_prepare_grid_preserves_graph_feature_policy(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_graph_policy"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "graph_cell",
            "stage": "unit",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [1],
            "feature_policy": "graph_khop",
            "graph_degree": 1,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
            "input_scope": "pricefm_graph_khop",
            "spatial_information_set": "pricefm_released_graph_khop",
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))

    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert rows[0]["feature_policy"] == "graph_khop"
    assert rows[0]["graph_degree"] == 1
    full = yaml.safe_load((tmp_path / "generated" / "configs" / "full" / "graph_cell.yaml").read_text())
    cell = full["pricefm_desn_full"]
    assert cell["scope"]["feature_policy"] == "graph_khop"
    assert cell["adapter"]["spatial"]["graph_degree"] == 1
    assert cell["comparison_metadata"]["feature_policy"] == "graph_khop"
    assert cell["comparison_metadata"]["spatial_information_set"] == "pricefm_released_graph_khop"


def test_prepare_grid_preserves_graph_neighbor_direct_controls(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_graph_neighbor_direct"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "graph_direct_cell",
            "stage": "unit",
            "priority": 0,
            "regions": ["PL"],
            "folds": [3],
            "feature_policy": "graph_neighbor_direct",
            "graph_degree": 1,
            "neighbor_regions": ["DE_LU", "LT"],
            "target_lag_features": ["price", "load", "solar", "wind"],
            "target_lead_features": ["load", "solar", "wind"],
            "neighbor_lag_features": ["price", "load"],
            "neighbor_lead_features": ["load", "wind"],
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
            "input_scope": "pricefm_graph_neighbor_direct_degree1_n2",
            "spatial_information_set": "pricefm_neighbor_augmented_direct",
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))

    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert rows[0]["feature_policy"] == "graph_neighbor_direct"
    assert rows[0]["neighbor_regions"] == '["DE_LU", "LT"]'
    full = yaml.safe_load((tmp_path / "generated" / "configs" / "full" / "graph_direct_cell.yaml").read_text())
    cell = full["pricefm_desn_full"]
    spatial = cell["adapter"]["spatial"]
    assert cell["scope"]["feature_policy"] == "graph_neighbor_direct"
    assert spatial["graph_degree"] == 1
    assert spatial["neighbor_regions"] == ["DE_LU", "LT"]
    assert spatial["neighbor_lag_features"] == ["price", "load"]
    assert cell["comparison_metadata"]["spatial_information_set"] == "pricefm_neighbor_augmented_direct"


def test_grid_runner_window_jobs_expand_graph_khop_dependencies(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_graph_window_dependencies"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "graph_dk2_lag48",
            "stage": "unit",
            "priority": 0,
            "regions": ["DK_2"],
            "folds": [1],
            "feature_policy": "graph_khop",
            "graph_degree": 1,
            "feature_map": "window_reservoir_v1",
            "lag_window": 48,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
            "input_scope": "pricefm_graph_khop_degree1",
            "spatial_information_set": "pricefm_released_graph_khop",
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)

    jobs = runner_mod.build_window_jobs(rows)
    assert len(jobs) == 1
    assert jobs[0]["regions"] == ["DK_2", "DE_LU", "DK_1", "SE_4"]
    assert jobs[0]["folds"] == [1]
    assert jobs[0]["lag_window"] == 48


def test_grid_runner_window_jobs_expand_graph_neighbor_direct_dependencies(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_graph_direct_window_dependencies"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "graph_direct_pl_lag96",
            "stage": "unit",
            "priority": 0,
            "regions": ["PL"],
            "folds": [3],
            "feature_policy": "graph_neighbor_direct",
            "graph_degree": 1,
            "neighbor_regions": ["DE_LU", "LT"],
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)

    jobs = runner_mod.build_window_jobs(rows)
    assert len(jobs) == 1
    assert jobs[0]["regions"] == ["PL", "DE_LU", "LT"]
    assert jobs[0]["folds"] == [3]
    assert jobs[0]["lag_window"] == 96


def test_prepare_grid_rejects_invalid_experiment_quantiles(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "bad_tau_order",
            "stage": "unit",
            "priority": 0,
            "lag_window": 96,
            "feature_dim": 120,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantiles": [0.75, 0.25],
        }
    ]
    cfg_path = tmp_path / "bad_grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    import pytest

    with pytest.raises(ValueError, match="quantiles"):
        grid_mod.load_grid(str(cfg_path))


def test_grid_runner_selects_experiments_for_parallel_launch():
    grid = grid_mod.load_grid(str(GRID))
    rows = grid_mod.prepare_grid(grid, GRID.parent / "_unused", write=False)
    selected = runner_mod.select_rows(rows, priorities=[1], max_experiments=3)
    assert len(selected) == 3
    assert all(int(row["priority"]) == 1 for row in selected)
    selected_by_stage = runner_mod.select_rows(rows, stages=["scale_refine"])
    assert {float(row["projection_scale"]) for row in selected_by_stage} == {0.35, 0.5, 0.75}


def test_grid_runner_window_jobs_follow_generated_full_scope(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_multifold_windows"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["scope"]["folds"] = [2, 3]
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "multifold_window_job",
            "stage": "unit",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [2, 3],
            "feature_map": "window_reservoir_v1",
            "lag_window": 72,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)

    jobs = runner_mod.build_window_jobs(rows)
    assert len(jobs) == 1
    assert jobs[0]["regions"] == ["DE_LU"]
    assert jobs[0]["folds"] == [2, 3]


def test_grid_runner_deduplicates_window_jobs_by_window_scope(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_window_dedupe"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    common = {
        "stage": "unit",
        "priority": 0,
        "regions": ["DE_LU"],
        "folds": [1],
        "feature_map": "window_reservoir_v1",
        "lag_window": 96,
        "depth": 1,
        "units": [120],
        "alpha": 0.5,
        "rho": 0.9,
        "input_scale": 0.5,
        "tau0": 1.0e-3,
        "seed": 20260601,
    }
    grid["experiments"] = [
        {**common, "id": "tau010", "quantile": 0.10},
        {**common, "id": "tau050", "quantile": 0.50},
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert rows[0]["data_config"] != rows[1]["data_config"]
    jobs = runner_mod.build_window_jobs(rows)
    assert len(jobs) == 1
    assert jobs[0]["regions"] == ["DE_LU"]
    assert jobs[0]["folds"] == [1]
    assert jobs[0]["lag_window"] == 96


def test_reservoir_grid_expands_blocks_and_writes_controls(tmp_path):
    grid = grid_mod.load_grid(str(RESERVOIR_GRID))
    rows = grid_mod.prepare_grid(grid, tmp_path / "reservoir_grid", write=True)
    assert len(rows) == 79
    assert sum(int(row["priority"]) == 0 for row in rows) == 2
    assert sum(int(row["priority"]) == 1 for row in rows) == 65
    assert sum(int(row["priority"]) == 2 for row in rows) == 12
    assert {"window_reservoir_v1"} == {row["feature_map"] for row in rows}
    assert {"d1_memory_stability", "d2_compact", "seed_robustness"}.issubset({
        row["stage"] for row in rows
    })

    first = next(row for row in rows if row["id"] == "res_smoke_d1n120_a0p70_r0p90_in0p50_seed20260601")
    full_path = ROOT / first["full_config"]
    if not full_path.exists():
        full_path = Path(first["full_config"])
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    assert full["adapter"]["feature_map"] == "window_reservoir_v1"
    assert full["adapter"]["depth"] == 1
    assert full["adapter"]["units"] == [120]
    assert full["adapter"]["alpha"] == 0.70
    assert full["adapter"]["rho"] == 0.90
    assert full["adapter"]["input_scale"] == 0.50
    assert full["adapter"]["recurrent_sparsity"] == 0.05
    assert full["artifact_hygiene"]["enabled"] is True
    assert "X_*.csv" in full["artifact_hygiene"]["clean_adapter_patterns"]

    d2 = next(row for row in rows if row["id"] == "res_p1_d2n240x240_l096_alpha0p9_rho0p97_input_scale0p5")
    d2_full_path = ROOT / d2["full_config"]
    if not d2_full_path.exists():
        d2_full_path = Path(d2["full_config"])
    d2_full = yaml.safe_load(d2_full_path.read_text())["pricefm_desn_full"]
    data_path = ROOT / d2["data_config"]
    if not data_path.exists():
        data_path = Path(d2["data_config"])
    data = yaml.safe_load(data_path.read_text())
    cell = full_run_mod.make_cell_config(d2_full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["adapter"]["depth"] == 2
    assert cell["adapter"]["units"] == [240, 240]
    assert cell["adapter"]["alpha"] == 0.9
    assert cell["adapter"]["rho"] == 0.97
    assert cell["adapter"]["input_scale"] == 0.5


def test_grid_materializer_forwards_horizon_block_readout_controls(tmp_path):
    payload = yaml.safe_load(GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "test_horizon_block_readout"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "hb_readout",
            "stage": "test",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [1],
            "quantile": 0.5,
            "lag_window": 96,
            "feature_map": "window_reservoir_v1",
            "feature_policy": "target_only",
            "feature_dim": 96,
            "depth": 1,
            "units": [96],
            "alpha": 0.4,
            "rho": 0.86,
            "input_scale": 0.25,
            "state_output": "final_layer",
            "readout_interaction": "horizon_block",
            "horizon_block_size": 24,
            "readout_interaction_basis": "state_lead",
            "tau0": 0.001,
            "seed": 20260730,
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))
    loaded = grid_mod.load_grid(str(cfg_path))
    rows = grid_mod.prepare_grid(loaded, tmp_path / "generated", write=True)
    assert rows[0]["readout_interaction"] == "horizon_block"
    assert int(rows[0]["horizon_block_size"]) == 24
    full_path = ROOT / rows[0]["full_config"]
    if not full_path.exists():
        full_path = Path(rows[0]["full_config"])
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    assert full["adapter"]["readout_interaction"] == "horizon_block"
    assert full["adapter"]["horizon_block_size"] == 24
    assert full["adapter"]["readout_interaction_basis"] == "state_lead"


def test_corrected_reservoir_grid_is_focused_and_validates_controls(tmp_path):
    grid = grid_mod.load_grid(str(CORRECTED_RESERVOIR_GRID))
    rows = grid_mod.prepare_grid(grid, tmp_path / "corrected_reservoir_grid", write=True)
    assert len(rows) == 142
    assert sum(int(row["priority"]) == 0 for row in rows) == 5
    assert sum(int(row["priority"]) == 1 for row in rows) == 92
    assert sum(int(row["priority"]) == 2 for row in rows) == 45
    assert {"window_reservoir_v1"} == {row["feature_map"] for row in rows}

    priority1 = [row for row in rows if int(row["priority"]) == 1]
    assert max(int(row["feature_dim"]) for row in priority1) == 240
    assert {"d1_core_dynamics", "d2_core_dynamics", "context_check_small"}.issubset({
        row["stage"] for row in priority1
    })

    target = next(row for row in rows if row["id"] == "rc_p0_d2n80x80_l096_a0p70_r0p90_in0p50_seed20260601")
    full_path = ROOT / target["full_config"]
    if not full_path.exists():
        full_path = Path(target["full_config"])
    full = yaml.safe_load(full_path.read_text())["pricefm_desn_full"]
    data_path = ROOT / target["data_config"]
    if not data_path.exists():
        data_path = Path(target["data_config"])
    data = yaml.safe_load(data_path.read_text())
    cell = full_run_mod.make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["adapter"]["depth"] == 2
    assert cell["adapter"]["units"] == [80, 80]
    assert cell["adapter"]["alpha"] == 0.7
    assert cell["adapter"]["rho"] == 0.9
    assert cell["adapter"]["input_scale"] == 0.5


def test_reservoir_grid_validator_checks_generated_configs(tmp_path):
    result = validator_mod.validate_grid(
        str(CORRECTED_RESERVOIR_GRID),
        priorities=[0],
        write_generated=True,
        require_cell_configs=False,
        require_feature_manifests=False,
        generated_root=tmp_path / "corrected_reservoir_grid_validator",
    )
    assert result["status"] == "passed"
    assert result["n_selected"] == 5
    assert all(row["expected_reservoir_config_sha256"] for row in result["rows"])


def test_reservoir_grid_validator_checks_every_scoped_cell(tmp_path):
    payload = yaml.safe_load(CORRECTED_RESERVOIR_GRID.read_text())
    grid = payload["pricefm_desn_experiment_grid"]
    grid["grid_id"] = "unit_multifold_validator"
    grid["base"]["generated_root"] = str(tmp_path / "generated")
    grid["base"]["run_root"] = str(tmp_path / "runs")
    grid["scope"]["folds"] = [2, 3]
    grid["experiment_blocks"] = []
    grid["experiments"] = [
        {
            "id": "multifold_validator",
            "stage": "unit",
            "priority": 0,
            "regions": ["DE_LU"],
            "folds": [2, 3],
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 1,
            "units": [120],
            "alpha": 0.5,
            "rho": 0.9,
            "input_scale": 0.5,
            "tau0": 1.0e-3,
            "seed": 20260601,
            "quantile": 0.50,
        }
    ]
    cfg_path = tmp_path / "grid.yaml"
    cfg_path.write_text(yaml.safe_dump(payload, sort_keys=False))

    result = validator_mod.validate_grid(
        str(cfg_path),
        priorities=[0],
        write_generated=True,
        require_cell_configs=False,
        require_feature_manifests=False,
        generated_root=tmp_path / "generated",
    )
    assert result["status"] == "passed"
    assert result["n_selected"] == 1
    assert {(row["region"], row["fold"]) for row in result["rows"]} == {("DE_LU", 2), ("DE_LU", 3)}
