import importlib.util
import sys
from pathlib import Path

import pandas as pd

SCRIPT = Path(__file__).parents[1] / "scripts/pricefm/175_audit_pricefm_stage_r49_mcmc_mechanism_capability.py"
sys.path.insert(0, str(SCRIPT.parent))


def module():
    spec = importlib.util.spec_from_file_location("r49", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_capability_audit_is_read_only():
    text = SCRIPT.read_text()
    assert "launch_yaml_written\": False" in text
    assert "mcmc_launch_authorized\": False" in text
    assert "subprocess" not in text


def test_conditional_component_count_uses_only_nonzero_blocks(tmp_path):
    mod = module()
    r46 = tmp_path / "r46"
    exdqlm = tmp_path / "exdqlm"
    out = tmp_path / "out"
    r46.mkdir()
    (exdqlm / "R").mkdir(parents=True)
    pd.DataFrame([{
        "region": "NO_3", "fold": 2, "weight_1_24": .75,
        "weight_25_48": 0, "weight_49_72": 0, "weight_73_96": 0,
    }]).to_csv(r46 / "pricefm_stage_r46_frozen_test_audit_queue.csv", index=False)
    runner = tmp_path / "runner.R"
    runner.write_text("exal_ldvb_fit separate_horizon_block partial_pool")
    (exdqlm / "R/qdesn_mcmc.R").write_text('qdesn_fit_mcmc exal_mcmc_fit( "rhs_ns" beta_prior_type get_exact(mcmc_args, "init", list())')
    (exdqlm / "R/exal_mcmc_fit.R").write_text("if (init_from_vb) exal_ldvb_fit( exal_mcmc_posterior_predict exal_mcmc_posterior_draws")
    args = mod.parser().parse_args(["--stage-r46-dir", str(r46), "--runner", str(runner), "--exdqlm-repo", str(exdqlm), "--output-dir", str(out)])
    summary = mod.run(args)
    assert summary["conditional_tau_component_fit_targets"] == 14
    assert summary["pricefm_runner_capable"] is False
    assert not list(out.glob("*.yaml"))
