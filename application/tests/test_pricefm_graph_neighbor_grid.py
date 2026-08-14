"""Tests for graph-neighbor median grid preparation."""

from pathlib import Path
import importlib.util
import sys

import pandas as pd
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
sys.path.insert(0, str(SCRIPT_DIR))


def load_script(name):
    path = SCRIPT_DIR / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_graph_neighbor_grid_clones_registry_geometry():
    mod = load_script("37_prepare_pricefm_graph_neighbor_median_grid.py")
    template = yaml.safe_load(
        (ROOT / "application" / "config" / "pricefm_desn_experiment_grid_median_region_panel_20260606.yaml").read_text()
    )
    registry = pd.DataFrame([
        {
            "region": "DE_LU",
            "fold": 1,
            "experiment_id": "local_winner",
            "selected_method_id": "qdesn_exal_rhs_ns_exact_chunked",
            "selection_metric_value": 7.0,
            "feature_map": "window_reservoir_v1",
            "lag_window": 96,
            "depth": 2,
            "units": "[80, 80]",
            "alpha": "0.4",
            "rho": "0.9",
            "input_scale": "0.35",
            "projection_scale": 1.0,
            "tau0": 1.0e-3,
            "seed": 20260603,
            "recurrent_sparsity": "0.05",
            "state_output": "final_layer",
        },
    ])
    payload = mod.build_grid(
        template,
        registry,
        "unit_graph",
        "generated",
        "runs",
        graph_degree=1,
        priority=2,
        candidate_source="unit_graph_source",
    )
    grid = payload["pricefm_desn_experiment_grid"]
    assert grid["grid_id"] == "unit_graph"
    assert grid["fixed"]["feature_policy"] == "graph_khop"
    assert grid["fixed"]["spatial"]["graph_degree"] == 1
    assert len(grid["experiments"]) == 1
    exp = grid["experiments"][0]
    assert exp["feature_policy"] == "graph_khop"
    assert exp["regions"] == ["DE_LU"]
    assert exp["folds"] == [1]
    assert exp["depth"] == 2
    assert exp["units"] == [80, 80]
    assert exp["alpha"] == 0.4
    assert exp["rho"] == 0.9
    assert exp["input_scope"] == "pricefm_graph_khop_degree1"
    assert exp["spatial_information_set"] == "pricefm_released_graph_khop"
    assert exp["median_registry"]["median_experiment_id"] == "local_winner"
