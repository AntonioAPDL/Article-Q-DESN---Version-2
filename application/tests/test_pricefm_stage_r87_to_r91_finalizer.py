import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/288_finalize_pricefm_stage_r87_to_r91.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r87_r91_finalizer", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_finalizer_orders_the_frozen_stages_and_requires_authorization():
    text = SCRIPT.read_text()
    positions = [text.index(f'"{number}_') for number in (282, 283, 284)]
    positions += [text.index('"--preflight-only"'), text.index('"--authorize"'), text.index("287_closeout")]
    assert positions == sorted(positions)
    assert "R88-R91 finalization requires explicit --authorize-test-audit" in text


def test_finalizer_does_not_reference_forbidden_workflows():
    text = SCRIPT.read_text().lower()
    assert "main.tex" not in text
    assert "registry.csv" not in text
    assert "mcmc" not in text
    assert "joint" not in text


def test_finalizer_freezes_its_code_commit():
    text = SCRIPT.read_text()
    assert "frozen_code_head = code_head(code_root)" in text
    assert "require_unchanged_head(code_root, frozen_code_head)" in text
    assert "Finalizer code HEAD changed" in text


def test_finalizer_preserves_virtual_environment_symlink(tmp_path):
    module = load()
    link = tmp_path / "venv/bin/python"
    link.parent.mkdir(parents=True)
    link.symlink_to(sys.executable)
    observed = module.python_executable(link)
    assert observed == link.absolute()
    assert observed.is_symlink()
    assert "args.python_bin.resolve()" not in SCRIPT.read_text()


def test_finalizer_pins_environment_and_records_failure_state():
    text = SCRIPT.read_text()
    assert '"scikit_learn": "1.8.0"' in text
    assert '"pandas": "3.0.3"' in text
    assert '"failed_stage": current_stage' in text
    assert '"error_type": type(error).__name__' in text


def test_finalizer_requires_audited_pretest_boundaries():
    text = SCRIPT.read_text()
    assert '"eligible_exal_cases": 32' in text
    assert '"fallback_al_cases": 10' in text
    assert '"exal_selected_cases": 32' in text
    assert '"al_selected_cases": 24' in text
    assert '"model_refits_authorized": 0' in text
