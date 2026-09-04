import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/284_prepare_pricefm_stage_r90_scoring_only_test_audit.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r90_prep", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_thresholds_and_reference_surface_are_preregistered():
    module = load()
    assert module.TAUS == (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
    text = SCRIPT.read_text()
    assert 'default=1e-10' in text
    assert "R90 registered thresholds cannot be changed" in text
    assert '"comparator_granularity": "case_level_seven_quantile_AQL_only"' in text
    assert "no_unsupported_granular_reference_inference" in text


def test_r90_prep_authorizes_test_scoring_but_never_refitting_or_mutation():
    text = SCRIPT.read_text()
    assert '"test_access_authorized": True' in text
    assert '"model_refit_authorized": False' in text
    assert '"selection_change_authorized": False' in text
    assert '"registry_mutation_authorized": False' in text
    assert '"article_mutation_authorized": False' in text
    assert '"joint_model_authorized": False' in text
    assert '"mcmc_authorized": False' in text
    assert "subprocess" not in text
