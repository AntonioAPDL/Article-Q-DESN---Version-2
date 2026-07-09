"""Tests for PriceFM DESN full-run orchestration helpers."""

from pathlib import Path
import copy
import json
import sys

import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_common import load_config  # noqa: E402
from pricefm_full_run import (  # noqa: E402
    cell_statuses_have_failures,
    cell_paths,
    cleanup_adapter_matrices,
    cleanup_success_artifacts,
    is_cell_complete,
    is_adapter_ready_for_model,
    load_full_config,
    make_cell_config,
    missing_window_files,
    parse_time_log,
    run_cells,
    write_cell_config,
)


CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_full.yaml"


def temp_full_config(tmp_path):
    full = copy.deepcopy(load_full_config(CONFIG))
    full["run"]["output_dir"] = str(tmp_path / "run")
    full["adapter"]["output_root"] = str(tmp_path / "run" / "cells")
    full["scope"]["regions"] = ["DE_LU"]
    full["scope"]["folds"] = [1]
    return full


def test_cell_config_generation_is_deterministic(tmp_path):
    full = temp_full_config(tmp_path)
    data = load_config(full["data_config"])
    first = make_cell_config(full, data, "DE_LU", 1)
    second = make_cell_config(full, data, "DE_LU", 1)
    assert first == second
    cell = first["pricefm_desn_smoke"]
    assert cell["region"] == "DE_LU"
    assert cell["fold"] == 1
    assert cell["horizons"] == list(range(1, 97))
    assert cell["quantiles"] == [0.05, 0.25, 0.50]
    assert cell["adapter"]["output_dir"].endswith("cells/region=DE_LU/fold=1/adapter")
    assert cell["run"]["output_dir"].endswith("cells/region=DE_LU/fold=1/model")


def test_cell_config_carries_optional_warm_start_block(tmp_path):
    full = temp_full_config(tmp_path)
    full["warm_start"] = {
        "enabled": True,
        "qdesn": {"al": {"components": ["beta"]}},
    }
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["warm_start"]["enabled"] is True
    assert cell["warm_start"]["qdesn"]["al"]["components"] == ["beta"]


def test_cell_config_carries_optional_training_cap(tmp_path):
    full = temp_full_config(tmp_path)
    full["training"] = {
        "train_origin_limit": 500,
        "train_origin_selection": "tail",
    }
    full["adapter"]["row_chunk_size"] = 512
    full["adapter"]["projection_scale"] = 2.0
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["training"]["train_origin_limit"] == 500
    assert cell["training"]["train_origin_selection"] == "tail"
    assert cell["adapter"]["row_chunk_size"] == 512
    assert cell["adapter"]["projection_scale"] == 2.0


def test_cell_config_carries_reservoir_controls(tmp_path):
    full = temp_full_config(tmp_path)
    full["adapter"].update({
        "feature_map": "window_reservoir_v1",
        "feature_dim": 3,
        "depth": 2,
        "units": [4, 3],
        "alpha": [0.5, 0.8],
        "rho": [0.7, 0.95],
        "input_scale": [0.25, 0.75],
        "recurrent_sparsity": [0.2, 0.4],
        "bias_scale": [0.0, 0.1],
        "reservoir_activation": "tanh",
        "state_output": "final_layer",
    })
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    adapter = cell["adapter"]
    assert adapter["feature_map"] == "window_reservoir_v1"
    assert adapter["feature_dim"] == 3
    assert adapter["depth"] == 2
    assert adapter["units"] == [4, 3]
    assert adapter["alpha"] == [0.5, 0.8]
    assert adapter["rho"] == [0.7, 0.95]
    assert adapter["input_scale"] == [0.25, 0.75]
    assert adapter["recurrent_sparsity"] == [0.2, 0.4]
    assert adapter["bias_scale"] == [0.0, 0.1]
    assert adapter["reservoir_activation"] == "tanh"
    assert adapter["state_output"] == "final_layer"


def test_cell_config_carries_graph_feature_policy_and_spatial_controls(tmp_path):
    full = temp_full_config(tmp_path)
    full["scope"]["feature_policy"] = "graph_khop"
    full["adapter"]["spatial"] = {
        "graph_degree": 1,
        "graph_source": "PriceFM.graph_adj_matrix",
    }
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["feature_policy"] == "graph_khop"
    assert cell["adapter"]["spatial"]["graph_degree"] == 1
    assert cell["adapter"]["spatial"]["graph_source"] == "PriceFM.graph_adj_matrix"


def test_cell_config_carries_graph_neighbor_direct_spatial_controls(tmp_path):
    full = temp_full_config(tmp_path)
    full["scope"]["feature_policy"] = "graph_neighbor_direct"
    full["adapter"]["spatial"] = {
        "graph_degree": 1,
        "neighbor_regions": ["DE_LU", "LT"],
        "neighbor_lag_features": ["price", "load"],
        "neighbor_lead_features": ["load", "wind"],
    }
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "PL", 3)["pricefm_desn_smoke"]
    assert cell["feature_policy"] == "graph_neighbor_direct"
    assert cell["adapter"]["spatial"]["neighbor_regions"] == ["DE_LU", "LT"]
    assert cell["adapter"]["spatial"]["neighbor_lag_features"] == ["price", "load"]


def test_missing_window_files_checks_graph_neighbor_direct_dependencies(tmp_path):
    full = temp_full_config(tmp_path)
    full["scope"]["feature_policy"] = "graph_neighbor_direct"
    full["scope"]["splits"] = ["train"]
    full["adapter"]["spatial"] = {
        "graph_degree": 1,
        "neighbor_regions": ["DE_LU", "LT"],
    }
    data = {
        "pricefm": {
            "processed_dir": str(tmp_path / "processed"),
            "regions": ["AT", "BE", "BG", "CZ", "DE_LU", "DK_1", "DK_2", "EE", "ES", "FI",
                        "FR", "GR", "HR", "HU", "IT_CALA", "IT_CNOR", "IT_CSUD", "IT_NORD",
                        "IT_SARD", "IT_SICI", "IT_SUD", "LT", "LV", "NL", "NO_1", "NO_2",
                        "NO_3", "NO_4", "NO_5", "PL", "PT", "RO", "SE_1", "SE_2", "SE_3",
                        "SE_4", "SI", "SK"],
            "windows": {
                "lag_window": 96,
                "lead_window": 96,
                "train_boundary_mode": "contained_half_open",
                "validation_boundary_mode": "operational_half_open",
                "test_boundary_mode": "operational_half_open",
            },
        }
    }
    missing = missing_window_files(full, data, "PL", 3)
    assert len(missing) == 3
    assert any("region=PL" in path for path in missing)
    assert any("region=DE_LU" in path for path in missing)
    assert any("region=LT" in path for path in missing)
    assert all(("region=PL" in path or "region=DE_LU" in path or "region=LT" in path) for path in missing)


def test_cell_config_carries_optional_artifact_hygiene_block(tmp_path):
    full = temp_full_config(tmp_path)
    full["artifact_hygiene"] = {
        "enabled": True,
        "clean_adapter_patterns": ["X_*.csv"],
        "clean_model_patterns": ["*.rds"],
    }
    data = load_config(full["data_config"])
    cell = make_cell_config(full, data, "DE_LU", 1)["pricefm_desn_smoke"]
    assert cell["artifact_hygiene"]["enabled"] is True
    assert cell["artifact_hygiene"]["clean_model_patterns"] == ["*.rds"]


def test_write_cell_config_and_completion_check(tmp_path):
    full = temp_full_config(tmp_path)
    data = load_config(full["data_config"])
    cfg_path = write_cell_config(full, data, "DE_LU", 1)
    assert cfg_path.exists()
    paths = cell_paths(full, "DE_LU", 1)
    assert is_cell_complete(full, "DE_LU", 1) is False
    paths["model"].mkdir(parents=True)
    for name in [
        "metric_summary.csv",
        "model_method_summary.csv",
        "predictions_with_naive_scaled.csv",
        "report.md",
    ]:
        (paths["model"] / name).write_text("x\n")
    assert is_cell_complete(full, "DE_LU", 1) is True


def test_adapter_ready_for_model_requires_design_matrices(tmp_path):
    full = temp_full_config(tmp_path)
    paths = cell_paths(full, "DE_LU", 1)
    paths["adapter"].mkdir(parents=True)
    for name in [
        "adapter_manifest.json",
        "X_train.csv",
        "X_val.csv",
        "X_test.csv",
        "y_train.csv",
        "y_val.csv",
        "y_test.csv",
        "rows_train.csv",
        "rows_val.csv",
        "rows_test.csv",
    ]:
        (paths["adapter"] / name).write_text("x\n")
    assert is_adapter_ready_for_model(paths) is True

    (paths["adapter"] / "X_train.csv").unlink()
    assert is_adapter_ready_for_model(paths) is False


def test_cleanup_adapter_matrices_only_removes_design_csvs(tmp_path):
    adapter = tmp_path / "adapter"
    adapter.mkdir()
    (adapter / "X_train.csv").write_text("1,2\n")
    (adapter / "y_train.csv").write_text("1\n")
    (adapter / "rows_train.csv").write_text("origin_id\n")
    removed = cleanup_adapter_matrices(adapter)
    assert len(removed) == 1
    assert not (adapter / "X_train.csv").exists()
    assert (adapter / "y_train.csv").exists()
    assert (adapter / "rows_train.csv").exists()


def test_cleanup_success_artifacts_removes_only_configured_large_outputs(tmp_path):
    adapter = tmp_path / "adapter"
    model = tmp_path / "model"
    adapter.mkdir()
    model.mkdir()
    (adapter / "X_train.csv").write_text("1,2\n")
    (adapter / "y_train.csv").write_text("1\n")
    (adapter / "adapter_manifest.json").write_text("{}\n")
    (model / "fit_state.rds").write_text("binary-ish\n")
    (model / "draws.RData").write_text("binary-ish\n")
    (model / "metric_summary.csv").write_text("x\n")
    (model / "report.md").write_text("# report\n")
    removed = cleanup_success_artifacts({
        "adapter": adapter,
        "model": model,
    }, {
        "enabled": True,
        "clean_adapter_patterns": ["X_*.csv"],
        "clean_model_patterns": ["*.rds", "*.RData"],
    })
    assert len(removed) == 3
    assert not (adapter / "X_train.csv").exists()
    assert not (model / "fit_state.rds").exists()
    assert not (model / "draws.RData").exists()
    assert (adapter / "y_train.csv").exists()
    assert (adapter / "adapter_manifest.json").exists()
    assert (model / "metric_summary.csv").exists()
    assert (model / "report.md").exists()


def test_parse_time_log_handles_time_label_colons(tmp_path):
    path = tmp_path / "time.log"
    path.write_text(
        "\tElapsed (wall clock) time (h:mm:ss or m:ss): 18:48.61\n"
        "\tMaximum resident set size (kbytes): 1192780\n"
    )
    parsed = parse_time_log(path)
    assert parsed["elapsed_wall"] == "18:48.61"
    assert parsed["max_rss_kb"] == 1192780


def test_cell_status_failure_classifier():
    ok_rows = [
        {"status": "completed"},
        {"status": "skipped_complete"},
        {"status": "planned"},
    ]
    assert cell_statuses_have_failures(ok_rows) is False

    for status in ["missing_windows", "adapter_failed", "model_failed", "summary_failed", ""]:
        assert cell_statuses_have_failures([{"status": "completed"}, {"status": status}]) is True


def test_dry_run_records_cell_status_without_launching(tmp_path):
    full = temp_full_config(tmp_path)
    data = load_config(full["data_config"])
    rows = run_cells(full, data, jobs=1, dry_run=True, max_cells=1)
    assert len(rows) == 1
    assert rows[0]["region"] == "DE_LU"
    assert rows[0]["fold"] == 1
    assert rows[0]["status"] in {"planned", "missing_windows"}
    assert not (tmp_path / "run" / "cells" / "region=DE_LU" / "fold=1" / "model").exists()
