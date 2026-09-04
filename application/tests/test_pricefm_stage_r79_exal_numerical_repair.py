import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/263_gate_pricefm_stage_r79_exal_numerical_repair.py"


def load():
    spec = importlib.util.spec_from_file_location("r79", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_r79_requires_evidence_and_blocks_speculative_retry(tmp_path):
    module = load()
    output = tmp_path / "r79"
    result = module.run(module.parser().parse_args(["--output-dir", str(output)]))
    assert result["retry_atoms_authorized"] == 0
    assert result["unresolved_failure_components"] == 13
    gates = pd.read_csv(output / "pricefm_stage_r79_numerical_repair_gates.csv")
    assert not bool(gates.loc[gates.gate == "r80_retry_authorized", "passed"].iloc[0])
    assert bool(gates.loc[gates.gate == "exact_r75_structured_source", "passed"].iloc[0])


def test_r79_outputs_are_read_only_and_reproducible(tmp_path):
    module = load()
    output = tmp_path / "r79"
    module.run(module.parser().parse_args(["--output-dir", str(output)]))
    summary = json.loads((output / "summary.json").read_text())
    assert summary["test_opened"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False
    assert not list(output.rglob("*.yaml"))
    assert not list(output.rglob("*.rds"))
