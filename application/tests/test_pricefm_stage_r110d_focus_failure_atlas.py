from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/372_audit_pricefm_stage_r110d_focus_failure_atlas.py"
spec = importlib.util.spec_from_file_location("pricefm_r110d", SCRIPT)
audit = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(audit)


def test_effective_oracle_lambda_interpolates_monotone_ladder():
    ladder = [4.0, 6.0, 8.0, 12.0, 20.0]
    assert audit.effective_oracle_lambda(4.0, ladder) == 0.0
    assert audit.effective_oracle_lambda(20.0, ladder) == 1.0
    assert abs(audit.effective_oracle_lambda(10.0, ladder) - 0.625) < 1e-12


def test_region_classification_separates_control_target_and_neighbors():
    assert audit.classify_region("BE", 4, 0.05, 0.20)[0] == "control_hold"
    assert audit.classify_region("BG", 1, 0.20, 0.00)[0] == "target_driver_readout_exposure"
    assert audit.classify_region("EE", 3, 0.20, 0.25)[0] == "neighbor_panel_and_target_driver"


def test_source_contract_is_read_only_and_blocks_broad_launch():
    text = SCRIPT.read_text()
    assert '"model_fit_started": False' in text
    assert '"test_opened": False' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert '"broad_all_region_launch_authorized": False' in text
    assert '"bg_exposure_readout_launch_authorized": False' in text
    assert "write launch YAML" not in text
