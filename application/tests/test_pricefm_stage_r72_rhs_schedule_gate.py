import importlib.util
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"


def load():
    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(
        "r72_rhs", SCRIPTS / "248_gate_pricefm_stage_r72_rhs_schedule.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_r72_pinball_matches_quantile_loss_definition():
    module = load()
    y = np.array([0.0, 2.0])
    prediction = np.array([1.0, 1.0])
    assert module.pinball(y, prediction, 0.25) == 0.5


def test_r72_rhs_gate_requires_six_unique_cpus():
    module = load()
    assert module.parse_cpus("1,2,3,4,5,6") == [1, 2, 3, 4, 5, 6]
    try:
        module.parse_cpus("1,1,2,3,4,5")
    except RuntimeError:
        pass
    else:
        raise AssertionError("duplicate CPUs accepted")
