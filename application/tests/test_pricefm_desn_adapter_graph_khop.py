"""Tests for graph-neighbor PriceFM DESN adapter inputs."""

import copy
import json
import os
import sys
from pathlib import Path

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application" / "scripts" / "pricefm"
sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_common import load_config  # noqa: E402
from pricefm_desn_adapter import build_adapter, load_smoke_config, window_npz_path  # noqa: E402
from pricefm_graph import get_k_hop_regions  # noqa: E402


SMOKE_CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_smoke.yaml"


def require_graph_window_data():
    cfg = load_smoke_config(SMOKE_CONFIG)
    data_cfg = load_config(cfg["data_config"])
    regions = get_k_hop_regions("DE_LU", data_cfg["pricefm"]["regions"], degree=1)
    missing = []
    for region in regions:
        path = window_npz_path(data_cfg, 1, region, "train")
        if not path.exists():
            missing.append(str(path))
    if not missing:
        return
    if os.environ.get("PRICEFM_REQUIRE_DATA") == "1":
        pytest.fail("Required graph PriceFM windows are missing: {}".format(missing))
    pytest.skip("Local graph PriceFM windows are absent: {}".format(missing[:2]))


def write_graph_config(tmp_path, graph_degree=1):
    with open(SMOKE_CONFIG, "r") as f:
        payload = yaml.safe_load(f)
    cfg = copy.deepcopy(payload)
    smoke = cfg["pricefm_desn_smoke"]
    smoke["splits"] = ["train"]
    smoke["feature_policy"] = "graph_khop"
    smoke["horizons"] = [1, 24, 48, 72, 96]
    smoke["training"] = {
        "train_origin_limit": 2,
        "train_origin_selection": "tail",
    }
    smoke["adapter"]["feature_map"] = "flat_direct"
    smoke["adapter"]["row_chunk_size"] = 3
    smoke["adapter"]["output_dir"] = str(tmp_path / "adapter")
    smoke["adapter"]["spatial"] = {
        "graph_degree": int(graph_degree),
        "graph_source": "PriceFM.graph_adj_matrix",
    }
    cfg_path = tmp_path / "graph_smoke.yaml"
    with open(cfg_path, "w") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)
    return cfg_path


def test_graph_khop_adapter_expands_input_columns_and_records_manifest(tmp_path):
    require_graph_window_data()
    cfg_path = write_graph_config(tmp_path, graph_degree=1)
    manifest = build_adapter(str(cfg_path), force=True)
    graph = manifest["feature_manifest"]["feature_policy_manifest"]["graph"]
    active = graph["active_regions"]
    assert active == [
        "DE_LU", "AT", "BE", "CZ", "DK_1", "DK_2",
        "FR", "NL", "NO_2", "PL", "SE_4",
    ]
    assert manifest["feature_manifest"]["feature_policy"] == "graph_khop"
    assert graph["graph_degree"] == 1
    assert len(manifest["splits"]["train"]["feature_policy_manifest"]["source_windows"]) == len(active)

    n_horizons = len(load_smoke_config(cfg_path)["horizons"])
    expected_features = 1 + 96 * (4 + 3) * len(active) + 3 + n_horizons
    assert manifest["splits"]["train"]["n_rows"] == 2 * n_horizons
    assert manifest["splits"]["train"]["n_features"] == expected_features

    with open(tmp_path / "adapter" / "adapter_manifest.json", "r") as f:
        saved = json.load(f)
    assert saved["feature_manifest"]["feature_policy_manifest"]["input_scope"] == "pricefm_graph_khop"


def test_graph_degree_zero_matches_target_only_feature_dimension(tmp_path):
    require_graph_window_data()
    cfg_path = write_graph_config(tmp_path, graph_degree=0)
    manifest = build_adapter(str(cfg_path), force=True)
    graph = manifest["feature_manifest"]["feature_policy_manifest"]["graph"]
    assert graph["active_regions"] == ["DE_LU"]
    n_horizons = len(load_smoke_config(cfg_path)["horizons"])
    expected_features = 1 + 96 * (4 + 3) + 3 + n_horizons
    assert manifest["splits"]["train"]["n_features"] == expected_features
