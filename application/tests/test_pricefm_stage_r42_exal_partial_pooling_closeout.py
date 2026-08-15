import importlib.util
import sys
from pathlib import Path

import pandas as pd


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/168_closeout_pricefm_stage_r42_exal_partial_pooling.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r42", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def test_one_se_selection_prefers_more_pooling_and_enforces_harm_guard():
    mod = module()
    rows = []
    for fold, shared, partial, separate in [(1, .10, .09, .08), (2, .12, .11, .10), (3, .11, .10, .09), (4, .13, .12, .11), (5, .40, .39, .38)]:
        for weight, value in [(0, shared), (.25, partial), (1, separate)]:
            rows.append({"inner_fold": fold, "horizon_group": "1-24", "separate_weight": weight, "AQL_scaled": value, "shared_converged": True})
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [True] * 5})
    result = mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)
    assert result["selected_weight"] <= result["raw_best_weight"]
    assert result["selected_convergence_pass"] is True


def test_nonconverged_separate_surface_forces_shared_weight():
    mod = module()
    rows = []
    for fold in range(1, 6):
        rows.extend([
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 0, "AQL_scaled": .2, "shared_converged": True},
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 1, "AQL_scaled": .1, "shared_converged": True},
        ])
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [False, True, True, True, True]})
    result = mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)
    assert result["selected_weight"] == 0


def test_closeout_is_exal_specific_and_does_not_read_test_artifacts():
    source = SCRIPT.read_text()
    assert 'SHARED = "qdesn_exal_rhs_ns_exact_chunked"' in source
    assert 'rows_val.csv' in source
    assert 'rows_test.csv' not in source
    assert '"test_inspected": False' in source
    assert "restore_selected_r33_spatial_where_needed_and_nested_normal_to_al_to_exal_initialization_keep_interaction_none" in source
