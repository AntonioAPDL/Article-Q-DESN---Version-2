"""Static contract tests for the PriceFM DESN model smoke config."""

from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "application" / "config" / "pricefm_desn_model_smoke.yaml"


def load_cfg():
    with open(CONFIG, "r") as f:
        return yaml.safe_load(f)["pricefm_desn_smoke"]


def test_smoke_config_uses_rhs_ns_and_exact_chunking():
    cfg = load_cfg()
    assert cfg["quantiles"] == [0.05, 0.25, 0.50]
    assert cfg["horizons"] == [1, 24, 48, 72, 96]
    assert cfg["qdesn_vb"]["chunking"]["enabled"] is True
    assert cfg["qdesn_vb"]["chunking"]["mode"] == "exact"
    assert cfg["rhs_ns"]["tau0"] == 0.01
    assert cfg["rhs_ns"]["shrink_intercept"] is False
    assert "ridge" not in cfg["qdesn_vb"].get("likelihoods", [])


def test_generated_outputs_are_under_ignored_local_pricefm_root():
    cfg = load_cfg()
    assert cfg["adapter"]["output_dir"].startswith("application/data_local/pricefm/")
    assert cfg["run"]["output_dir"].startswith("application/data_local/pricefm/")
    assert cfg["feature_policy"] == "target_only"
