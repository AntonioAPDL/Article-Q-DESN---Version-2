import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r72_gate", SCRIPTS / "245_gate_pricefm_stage_r72_repair.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r72_exal_gate_fails_for_campaign_scale_instability():
    module = load()
    atoms = pd.DataFrame([
        {"likelihood_family": "exal", "artifacts_complete": True,
         "beta_l2": 10.0, "sigma": 1.0, "converged": True},
        {"likelihood_family": "exal", "artifacts_complete": True,
         "beta_l2": 1e9, "sigma": 1e8, "converged": False},
        {"likelihood_family": "al", "artifacts_complete": True,
         "beta_l2": 2.0, "sigma": 0.2, "converged": True},
    ])
    result = module.evaluate_exal_gate(atoms)
    assert result["passed"] is False
    assert result["extreme_beta_atoms"] == 1
    assert result["decision"] == "exal_launch_blocked"


def test_r72_probe_gate_requires_bounded_spd_and_rhs_contract(tmp_path):
    module = load()
    (tmp_path / "terminal.json").write_text(
        '{"status":"completed","converged":false}'
    )
    pd.DataFrame([{"beta_l2": 3.0, "sigma": 0.2}]).to_csv(
        tmp_path / "parameter_summary.csv", index=False
    )
    pd.DataFrame([{"relative_jitter": 1e-12}]).to_csv(
        tmp_path / "spd_factorization_trace.csv", index=False
    )
    (tmp_path / "rhs_diagnostics.json").write_text(
        '{"preflight":{"tau0":0.001,"init_tau":1,"init_tau_source":"init_tau"}}'
    )
    result = module.evaluate_probe(tmp_path)
    assert result["terminal_completed"] is True
    assert result["spd_within_bound"] is True
    assert result["rhs_contract_pass"] is True
    assert result["converged_at_bounded_iteration_budget"] is False
