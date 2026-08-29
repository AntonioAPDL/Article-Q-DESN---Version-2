import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r64prep", SCRIPTS / "222_prepare_pricefm_stage_r64_joint_mcmc_confirmation.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def candidates():
    return pd.DataFrame([
        {
            "source_case_id": "case_a", "region": "AA", "fold": 1,
            "n_train": 100, "n_slopes": 20, "K": 7, "joint_dimension": 140,
            "vb_elapsed_seconds": 1500, "vb_iterations": 150,
        },
        {
            "source_case_id": "case_b", "region": "BB", "fold": 2,
            "n_train": 200, "n_slopes": 30, "K": 7, "joint_dimension": 210,
            "vb_elapsed_seconds": 3000, "vb_iterations": 150,
        },
    ])


def test_r64_resource_envelope_is_full_joint_and_explicitly_heuristic():
    module = load()
    result = module.resource_envelope(candidates(), chains=4, n_iter=2000)
    first = result.iloc[0]
    assert first.latent_cells_per_chain == 700
    assert first.stacked_design_nnz_per_iteration == 14_000
    assert first.planned_chains == 4
    assert first.vb_linear_hours_per_chain == 1500 / 3600 * 2000 / 150
    assert not result.production_runtime_validated.any()


def test_r64_chain_seed_plan_is_case_specific_unique_and_blocked():
    module = load()
    result = module.chain_seed_plan(candidates(), chains=4)
    assert len(result) == 8
    assert result.seed.nunique() == 8
    assert result.groupby("source_case_id").chain.nunique().eq(4).all()
    assert not result.mcmc_launch_authorized.any()


def test_r64_capability_audit_rejects_old_pricefm_runner():
    module = load()
    result = module.kernel_capabilities(ROOT).set_index("capability")
    assert bool(result.loc["genuine_joint_al_mcmc_kernel", "supported"])
    assert bool(result.loc["split_anchor_innovation_rhs", "supported"])
    assert bool(result.loc["collapsed_exal_gamma_kernel", "supported"])
    assert not bool(result.loc["old_pricefm_r50_is_joint_equivalent", "supported"])
    assert not bool(result.loc["dedicated_pricefm_joint_mcmc_runner", "supported"])


def test_r64_writes_no_launch_yaml_and_keeps_mutation_blocked():
    source = (SCRIPTS / "222_prepare_pricefm_stage_r64_joint_mcmc_confirmation.py").read_text()
    assert "yaml.safe_dump" not in source
    assert '"launch_yaml_written": False' in source
    assert '"mcmc_launch_authorized": False' in source
    assert '"registry_mutation_authorized": False' in source
    assert '"article_mutation_authorized": False' in source
