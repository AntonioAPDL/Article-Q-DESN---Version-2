import importlib.util
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/283_select_pricefm_stage_r89_validation_family.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r89", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_pinball_loss():
    module = load()
    y = np.array([1.0, 1.0])
    q = np.array([0.0, 2.0])
    assert np.allclose(module.pinball(y, q, 0.25), [0.25, 0.75])


def test_selection_contract_is_case_specific_validation_only():
    text = SCRIPT.read_text()
    assert "case_specific_raw_original_seven_quantile_validation_AQL" in text
    assert "lower_raw_seven_quantile_validation_AQL_and_integrity_pass" in text
    assert "complete_exal_case_integrity_block_fallback_to_al" in text
    assert '"selection_frozen_before_test": True' in text
    assert '"test_access_authorized": False' in text
    assert '"r90_scoring_only_test_prep_authorized": True' in text
    assert "required-sklearn-version" in text and 'default="1.8.0"' in text
    assert "subprocess" not in text
