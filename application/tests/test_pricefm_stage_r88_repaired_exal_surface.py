import importlib.util
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/282_closeout_pricefm_stage_r88_repaired_exal_surface.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r88", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_case_gate_requires_all_seven_atoms():
    module = load()
    atoms = pd.DataFrame({
        "case_id": ["a"] * 7 + ["b"] * 7,
        "region": ["AA"] * 7 + ["BB"] * 7,
        "fold": [1] * 14,
        "tau": [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9] * 2,
        "source_stage": ["R87"] * 14,
        "atom_numerically_eligible": [True] * 13 + [False],
    })
    cases = module.summarize_cases(atoms)
    assert cases.set_index("case_id").loc["a", "all_atoms_numerically_eligible"]
    assert cases.set_index("case_id").loc["b", "fallback_to_al_required"]


def test_r88_has_no_rescue_test_or_mutation_path():
    text = SCRIPT.read_text()
    assert 'source_stage.value_counts().to_dict() != {"R87": 280, "R83": 14}' in text
    assert '"additional_rescue_authorized": False' in text
    assert '"test_opened": False' in text
    assert '"joint_or_mcmc_authorized": False' in text
    assert "subprocess" not in text
