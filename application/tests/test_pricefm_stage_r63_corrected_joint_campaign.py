import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location("r63prep", SCRIPTS / "220_prepare_pricefm_stage_r63_corrected_joint_campaign.py")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def test_target_selection_preserves_wins_and_bounds_mechanisms():
    module = load()
    queues = pd.DataFrame([
        {"case_id": "win", "region": "A", "fold": 1, "mechanism_queue": "existing_joint_validation_win", "joint_likelihood_family": "al", "independent_selected_family": "exal"},
        {"case_id": "correction", "region": "B", "fold": 1, "mechanism_queue": "near_loss_le_1pct", "joint_likelihood_family": "al", "independent_selected_family": "exal"},
        {"case_id": "severe", "region": "C", "fold": 1, "mechanism_queue": "severe_loss_gt_5pct", "joint_likelihood_family": "exal", "independent_selected_family": "exal"},
    ])
    corrections = pd.DataFrame([
        {"case_id": "win", "region": "A", "fold": 1, "corrected_seven_quantile_family": "exal"},
        {"case_id": "correction", "region": "B", "fold": 1, "corrected_seven_quantile_family": "exal"},
    ])
    selected = module.selected_arms(queues, corrections)
    assert "win" not in set(selected.case_id)
    assert selected[selected.case_id.eq("correction")].arm_id.tolist() == ["corrected_family_replay"]
    assert set(selected[selected.case_id.eq("severe")].arm_id) == set(module.SEVERE_ARMS)


def test_r63_contract_keeps_mutation_and_test_blocked():
    source = (SCRIPTS / "220_prepare_pricefm_stage_r63_corrected_joint_campaign.py").read_text()
    assert '"test_access_authorized": False' in source
    assert '"registry_mutation_authorized": False' in source
    assert '"article_mutation_authorized": False' in source
    assert "current_joint_wins_excluded" in source


def test_r63_closeout_requires_both_validation_baselines():
    source = (SCRIPTS / "221_closeout_pricefm_stage_r63_corrected_joint_campaign.py").read_text()
    assert "beats_independent and beats_old_joint" in source
    assert '"mcmc_launch_authorized": False' in source
    assert '"test_opened": False' in source


def test_shared_postfit_accepts_r61_r63_runtime_schema():
    source = (SCRIPTS / "205_repair_pricefm_stage_r57_joint_vb_postfit.py").read_text()
    assert 'payload.get("pricefm_stage_r61_joint_mechanism")' in source
    prep = (SCRIPTS / "220_prepare_pricefm_stage_r63_corrected_joint_campaign.py").read_text()
    assert '"vb_method_id": "AL_joint_cavi"' in prep


def test_r63_runner_and_closeout_propagate_stage_and_blocked_status():
    runner = (SCRIPTS / "213_run_pricefm_stage_r61_joint_mechanism_case.R").read_text()
    assert 'stage = cfg$stage %||% "R61"' in runner
    spec = importlib.util.spec_from_file_location(
        "r63closeout", SCRIPTS / "221_closeout_pricefm_stage_r63_corrected_joint_campaign.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.command_exit_code({"status": "completed_r63_validation_closeout"}) == 0
    assert module.command_exit_code({"status": "incomplete_or_integrity_blocked"}) == 1
