"""Static contract tests for the PriceFM DESN full-run config."""

from pathlib import Path
import sys

import yaml


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "application" / "scripts" / "pricefm"))

from pricefm_common import load_config  # noqa: E402
from pricefm_full_run import (  # noqa: E402
    load_full_config,
    resolve_folds,
    resolve_horizons,
    resolve_quantiles,
    resolve_regions,
)


CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_full.yaml"
MEDIAN_WARM_CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_full_median_warmstart.yaml"
AUTHORITATIVE_MEDIAN_DE_LU_CONFIG = (
    ROOT
    / "application"
    / "config"
    / "pricefm_desn_model_median_de_lu_fold1_authoritative_20260601.yaml"
)


def test_full_config_resolves_production_scope():
    full = load_full_config(CONFIG)
    data = load_config(full["data_config"])
    assert len(resolve_regions(full, data)) == 38
    assert resolve_folds(full, data) == [1, 2, 3]
    assert resolve_horizons(full, data) == list(range(1, 97))
    assert resolve_quantiles(full) == [0.05, 0.25, 0.50]


def test_full_config_uses_exact_chunked_rhs_ns_defaults():
    with open(CONFIG, "r") as f:
        full = yaml.safe_load(f)["pricefm_desn_full"]
    assert full["adapter"]["feature_dim"] == 30
    assert full["adapter"]["feature_map"] == "window_desn_v1"
    assert full["rhs_ns"]["tau0"] == 0.01
    assert full["rhs_ns"]["shrink_intercept"] is False
    assert full["qdesn_vb"]["likelihoods"] == ["al", "exal"]
    assert full["qdesn_vb"]["chunking"]["enabled"] is True
    assert full["qdesn_vb"]["chunking"]["mode"] == "exact"
    assert full["qdesn_vb"]["chunking"]["chunk_size"] == 2048


def test_full_config_outputs_are_ignored_local_paths():
    full = load_full_config(CONFIG)
    assert full["run"]["output_dir"].startswith("application/data_local/pricefm/")
    assert full["adapter"]["output_root"].startswith("application/data_local/pricefm/")


def test_median_warmstart_config_is_explicit_and_conservative():
    full = load_full_config(MEDIAN_WARM_CONFIG)
    data = load_config(full["data_config"])
    assert len(resolve_regions(full, data)) == 38
    assert resolve_folds(full, data) == [1, 2, 3]
    assert resolve_horizons(full, data) == list(range(1, 97))
    assert resolve_quantiles(full) == [0.50]
    assert full["warm_start"]["enabled"] is True
    assert full["warm_start"]["fallback_to_cold"] is False
    assert full["rhs_ns"]["tau0"] == 1.0e-4
    assert full["normal"]["vb_control"]["min_iter"] == 50
    assert full["normal"]["vb_control"]["max_iter"] == 100
    assert full["qdesn_vb"]["min_iter_elbo"] == 50
    assert full["qdesn_vb"]["max_iter"] == 100
    assert full["warm_start"]["qdesn"]["al"]["first_tau_source"] == "normal_rhs_ns"
    assert full["warm_start"]["qdesn"]["exal"]["source"] == "al_same_tau"
    assert "local" not in full["warm_start"]["qdesn"]["al"]["components"]
    assert "local" not in full["warm_start"]["qdesn"]["exal"]["components"]


def test_authoritative_median_de_lu_config_matches_selected_winner():
    full = load_full_config(AUTHORITATIVE_MEDIAN_DE_LU_CONFIG)
    data = load_config(full["data_config"])
    assert resolve_regions(full, data) == ["DE_LU"]
    assert resolve_folds(full, data) == [1]
    assert resolve_horizons(full, data) == list(range(1, 97))
    assert resolve_quantiles(full) == [0.50]
    assert full["adapter"]["feature_map"] == "window_desn_v1"
    assert full["adapter"]["feature_dim"] == 480
    assert full["adapter"]["projection_scale"] == 0.5
    assert full["adapter"]["seed"] == 20260601
    assert full["adapter"]["include_intercept"] is True
    assert full["rhs_ns"]["tau0"] == 1.0e-3
    assert full["rhs_ns"]["shrink_intercept"] is False
    assert full["training"]["train_origin_limit"] == 3000
    assert full["training"]["train_origin_selection"] == "tail"
    assert full["warm_start"]["enabled"] is True
    assert full["warm_start"]["fallback_to_cold"] is False
    assert full["qdesn_vb"]["likelihoods"] == ["al", "exal"]
    assert full["qdesn_vb"]["chunking"]["mode"] == "exact"
    assert full["qdesn_vb"]["chunking"]["chunk_size"] == 2048
    assert full["normal"]["vb_control"]["min_iter"] == 50
    assert full["normal"]["vb_control"]["max_iter"] == 100
    assert full["qdesn_vb"]["min_iter_elbo"] == 50
    assert full["qdesn_vb"]["max_iter"] == 100
