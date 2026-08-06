import importlib.util
import sys
from pathlib import Path

import pandas as pd


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/166_closeout_pricefm_stage_r40_partial_pooling.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r40", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def test_one_se_prefers_stronger_pooling_and_applies_harm_guard():
    mod = module()
    rows = []
    for fold, shared, partial, separate in [(1, .10, .09, .08), (2, .12, .11, .10), (3, .11, .10, .09), (4, .13, .12, .11), (5, .40, .39, .38)]:
        for weight, value in [(0, shared), (.25, partial), (1, separate)]:
            rows.append({"inner_fold": fold, "horizon_group": "1-24", "separate_weight": weight, "AQL_scaled": value, "shared_converged": True})
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [True] * 5})
    result = mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)
    assert result["selected_weight"] <= result["raw_best_weight"]
    assert result["selected_convergence_pass"] is True


def test_nonconverged_separate_forces_shared_eligibility():
    mod = module()
    rows = []
    for fold in range(1, 6):
        rows += [
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 0, "AQL_scaled": .2, "shared_converged": True},
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 1, "AQL_scaled": .1, "shared_converged": True},
        ]
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [False, True, True, True, True]})
    result = mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)
    assert result["selected_weight"] == 0
    assert result["selected_convergence_pass"] is True


def test_closeout_source_never_reads_test_predictions():
    source = SCRIPT.read_text()
    assert 'rows_val.csv' in source
    assert 'rows_test.csv' not in source
    assert '"test_inspected": False' in source
