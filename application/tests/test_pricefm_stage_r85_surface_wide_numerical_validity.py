import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/279_audit_pricefm_stage_r85_surface_wide_numerical_validity.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r85", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_registered_numerical_bounds_are_uniform():
    module = load()
    trace = pd.DataFrame({
        "sigma": [1.0] * 35,
        "gamma": [0.1] * 35,
        "delta_state": [1.0] + [0.1] * 34,
        "delta_sigma": [0.1] * 35,
        "delta_gamma": [0.1] * 35,
        "delta_s": [0.1] * 35,
    })
    parameter = pd.Series({"beta_l2": 2.0, "al_init_beta_l2": 1.0})
    good = module.trace_diagnostics(trace, parameter, 35)
    assert good["visible_numerical_bounds_pass"] is True
    trace.loc[0, "sigma"] = 100.0
    bad = module.trace_diagnostics(trace, parameter, 35)
    assert bad["sigma_bound_pass"] is False
    assert bad["visible_numerical_bounds_pass"] is False


def test_r85_quarantines_r84_and_refits_all_old_runtime_atoms():
    text = SCRIPT.read_text()
    assert 'len(completed76) != 280 or len(failed76) != 14' in text
    assert '"r85_refit_required"] = True' in text
    assert '"r84_scientific_authority": False' in text
    assert '"r86_launch_prep_authorized": True' in text
    assert '"test_opened": False' in text
    assert '"joint_or_mcmc_authorized": False' in text
    assert "subprocess" not in text
