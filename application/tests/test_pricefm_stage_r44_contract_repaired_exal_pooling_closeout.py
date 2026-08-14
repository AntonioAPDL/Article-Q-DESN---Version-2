import importlib.util
import sys
from pathlib import Path

import pandas as pd


SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/170_closeout_pricefm_stage_r44_contract_repaired_exal_pooling.py"
if str(SCRIPT.parent) not in sys.path:
    sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r44", SCRIPT)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def test_selector_is_exal_ready_one_se_and_harm_guarded():
    mod = module()
    rows = []
    for fold, shared, partial, separate in [(1, .10, .09, .08), (2, .12, .11, .10), (3, .11, .10, .09), (4, .13, .12, .11), (5, .40, .39, .38)]:
        for weight, value in [(0, shared), (.25, partial), (1, separate)]:
            rows.append({"inner_fold": fold, "horizon_group": "1-24", "separate_weight": weight, "AQL_scaled": value, "shared_converged": True})
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [True] * 5})
    result = mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)
    assert result["selected_weight"] <= result["raw_best_weight"]
    assert result["selected_convergence_pass"] is True


def test_nonconverged_separate_surface_forces_shared():
    mod = module()
    rows = []
    for fold in range(1, 6):
        rows.extend([
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 0, "AQL_scaled": .2, "shared_converged": True},
            {"inner_fold": fold, "horizon_group": "1-24", "separate_weight": 1, "AQL_scaled": .1, "shared_converged": True},
        ])
    convergence = pd.DataFrame({"horizon_group": ["1-24"] * 5, "converged": [False, True, True, True, True]})
    assert mod.select_block(pd.DataFrame(rows), convergence, "1-24", .005)["selected_weight"] == 0


def test_closeout_is_validation_only_and_blocks_promotion_actions():
    source = SCRIPT.read_text()
    assert 'SHARED = "qdesn_exal_rhs_ns_exact_chunked"' in source
    assert "rows_val.csv" in source
    assert "rows_test.csv" not in source
    assert '"test_inspected": False' in source
    assert '"registry_mutation_authorized": False' in source
    assert '"mcmc_authorized": False' in source
    assert "NO_3:2,NO_3:3" in source
