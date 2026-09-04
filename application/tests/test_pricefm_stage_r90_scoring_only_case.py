import importlib.util
from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/285_run_pricefm_stage_r90_scoring_only_case.py"


def load():
    spec = importlib.util.spec_from_file_location("pricefm_r90_case", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_beta_loader_orders_and_validates_features(tmp_path):
    module = load()
    path = tmp_path / "beta.csv"
    pd.DataFrame({"feature_index": [2, 1], "beta_mean": [3.0, 2.0]}).to_csv(path, index=False)
    assert np.array_equal(module.load_beta(path), np.array([2.0, 3.0]))


def test_validation_replay_is_key_aligned_and_strict():
    module = load()
    rows = pd.DataFrame({"origin_id": [0, 0], "horizon": [1, 2]})
    prediction = pd.DataFrame({
        "split": ["val", "val"], "origin_id": [0, 0], "horizon": [2, 1],
        "tau": [0.5, 0.5], "pred_scaled": [2.0, 1.0],
    })
    result = module.validation_replay(rows, prediction, np.array([1.0, 2.0]), 0.5, 1e-10)
    assert result["passed"]
    assert result["maximum_absolute_difference"] == 0.0


def test_worker_contains_no_fit_or_mutation_path():
    text = SCRIPT.read_text()
    assert '"model_fitted": False' in text
    assert '"selection_changed": False' in text
    assert '"task_config_sha256": sha256(task_path)' in text
    assert '"registry_mutated": False' in text
    assert '"article_mutated": False' in text
    assert "subprocess" not in text
    assert "exalStaticLDVB" not in text
