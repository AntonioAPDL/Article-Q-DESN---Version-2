import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_gate_is_strict_about_control_outputs():
    gate = load("r80_gate", "269_gate_pricefm_stage_r80_zero_freeze_repair.py")
    text = (SCRIPTS / "269_gate_pricefm_stage_r80_zero_freeze_repair.py").read_text()
    assert "len(frame) == 3" in text
    assert "frame.trace_finite.all()" in text
    assert "frame.structured_updates.ge(35).all()" in text
    assert "frame.tail_max_delta_state.lt(2).all()" in text
    assert gate.OUTPUT.name.startswith("pricefm_stage_r80_zero_freeze_repair_gate")


def test_retry_prep_is_exactly_failed_atoms_and_preserves_firewalls():
    text = (SCRIPTS / "270_prepare_pricefm_stage_r81_zero_freeze_retry.py").read_text()
    assert 'len(selected) != 14' in text
    assert 'selected.case_id.nunique() != 11' in text
    assert 'sigmagam_freeze_warmup_iters"] = 0' in text
    assert 'successful_r76_atoms_refit": 0' in text
    assert '"test_opened": False' in text


def test_retry_launcher_is_gate_bound_and_exactly_bounded():
    text = (SCRIPTS / "271_launch_pricefm_stage_r81_zero_freeze_retry.py").read_text()
    assert 'expected_tasks=14, workers=14' in text
    assert 'manifest.case_id.nunique() != 11' in text
    assert 'gate.get("r81_retry_authorized") is not True' in text
    assert 'task.get("sigmagam_freeze_warmup_iters") != 0' in text
