import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "application/scripts/pricefm/262_audit_pricefm_stage_r77_exal_failures.py"


def load():
    spec = importlib.util.spec_from_file_location("r77", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_failure_classifier_is_specific_and_conservative():
    module = load()
    assert module.classify("Structured exAL scale-skewness update has no finite gamma grid.") == "structured_gamma_grid_nonfinite"
    assert module.classify("R76 fit failed finite-output or structured-update contract.") == "aggregate_terminal_contract_unresolved"
    assert module.classify("different exception") == "fit_exception_other"


def test_real_r76_atlas_freezes_failures_and_blocks_retry(tmp_path):
    module = load()
    args = module.parser().parse_args(["--output-dir", str(tmp_path / "atlas")])
    result = module.run(args)
    assert result["failed_atoms"] == 14
    assert result["failed_cases"] == 11
    assert result["failures_tau_0p25"] == 9
    assert result["failures_tau_0p75"] == 5
    assert result["retry_atoms_authorized"] == 0
    eligibility = pd.read_csv(tmp_path / "atlas/pricefm_stage_r77_retry_eligibility.csv")
    assert len(eligibility) == 14
    assert not eligibility.retry_eligible.astype(bool).any()
    summary = json.loads((tmp_path / "atlas/summary.json").read_text())
    assert summary["test_opened"] is False
    assert summary["registry_mutated"] is False
    assert summary["article_mutated"] is False


def test_atlas_writes_no_launch_or_binary_artifacts(tmp_path):
    module = load()
    module.run(module.parser().parse_args(["--output-dir", str(tmp_path / "atlas")]))
    forbidden = {".yaml", ".yml", ".rds", ".rda", ".rdata"}
    assert not [p for p in (tmp_path / "atlas").rglob("*") if p.suffix.lower() in forbidden]
