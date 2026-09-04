from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/288_finalize_pricefm_stage_r87_to_r91.py"


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
