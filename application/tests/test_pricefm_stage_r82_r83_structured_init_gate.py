from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def test_r82_gate_is_bounded_and_does_not_weaken_failed_r80_gate():
    text = (SCRIPTS / "275_gate_pricefm_stage_r82_structured_init_repair.py").read_text()
    assert 'r80.get("r81_retry_authorized") is not False' in text
    assert "controls.max_sigma.lt(100).all()" in text
    assert "controls.beta_l2_ratio.lt(10).all()" in text
    assert "controls.first_delta_state.lt(100).all()" in text
    assert "controls.tail_max_delta_state.lt(2).all()" in text
    assert '"r83_retry_atoms": 14 if authorized else 0' in text
    assert '"test_opened": False' in text


def test_r83_prep_changes_only_numerical_initialization_and_failed_atoms():
    text = (SCRIPTS / "276_prepare_pricefm_stage_r83_structured_init_retry.py").read_text()
    assert 'len(selected) != 14' in text
    assert 'selected.case_id.nunique() != 11' in text
    assert 'stage="R83"' in text
    assert 'sigmagam_freeze_warmup_iters=0' in text
    assert '"successful_r76_atoms_refit": 0' in text
    assert '"changed_scientific_fields": []' in text


def test_r83_launcher_is_gate_bound_one_process_per_cpu():
    text = (SCRIPTS / "277_launch_pricefm_stage_r83_structured_init_retry.py").read_text()
    assert "expected_tasks=14" in text and "workers=14" in text
    assert 'gate.get("r83_retry_authorized") is not True' in text
    assert 'task.get("stage") != "R83"' in text
    assert '"one_process_per_cpu": True' in text
    assert 'task.get("selection_split") != "val"' in text


def test_shared_atomic_launcher_labels_worker_stage_from_manifest():
    launcher = SCRIPTS / "260_launch_pricefm_stage_r76_repaired_exal_surface.py"
    text = launcher.read_text()
    assert "row.get('stage', 'R76')" in text
