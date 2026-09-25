from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "application/scripts/pricefm"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from pricefm_common import sha256_file  # noqa: E402


def load(relative: str, name: str):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CLOSEOUT = load(
    "application/scripts/pricefm/402_closeout_pricefm_stage_r117_blocked.py",
    "pricefm_r117_blocked_closeout",
)


def trace(**last) -> pd.DataFrame:
    baseline = {
        "elbo": -1.0e6,
        "sigma": 0.008,
        "gamma": 0.0,
        "delta_state": 0.08,
        "delta_sigma": 1.0e-10,
        "delta_elbo": 1.0e-4,
    }
    baseline.update(last)
    return pd.DataFrame([baseline])


def test_trace_classification_separates_al_scale_sensitivity_from_divergence() -> None:
    al = CLOSEOUT.classify_trace_tail("al", trace())
    assert al["diagnostic_class"] == "finite_scale_elbo_stable_state_unresolved"
    assert al["scale_stable"] is True
    assert al["elbo_stable"] is True
    assert al["divergent"] is False

    exal = CLOSEOUT.classify_trace_tail(
        "exal",
        trace(sigma=9.0e6, delta_state=3.0e7, delta_sigma=2.0e6),
    )
    assert exal["diagnostic_class"] == "genuine_numerical_divergence"
    assert exal["divergent"] is True


def test_atom_audit_recovers_tau0_from_contract_without_rewriting_fit(tmp_path: Path) -> None:
    campaign = tmp_path / "campaign"
    contract_dir = campaign / "full_folds/fold=1/quantile_contracts"
    atom_dir = campaign / "full_folds/fold=1/quantiles/al/tau=0.45"
    contract_dir.mkdir(parents=True)
    atom_dir.mkdir(parents=True)

    contract = {
        "variant": "pure",
        "tau0": 1.9564639521780738e-5,
    }
    (contract_dir / "al_tau=0.45.json").write_text(json.dumps(contract))
    pd.DataFrame(trace()).to_csv(atom_dir / "vb_trace.csv", index=False)
    artifact = atom_dir / "parameter_summary.json"
    artifact.write_text('{"finite":true}')
    terminal = {
        "family": "al",
        "tau": 0.45,
        "tau0": 0,
        "atom_id": "fold1-al-0.45",
        "finite_core": True,
        "formal_converged": False,
        "numerically_eligible": False,
        "posterior_target_sha256": "target",
        "train_seconds": 1.0,
        "package": {"version": "1.1.1", "repository": "CRAN"},
        "test_opened": False,
        "artifacts": [
            {"path": artifact.name, "sha256": sha256_file(artifact)},
        ],
    }
    terminal_path = atom_dir / "terminal.json"
    terminal_path.write_text(json.dumps(terminal))

    record = CLOSEOUT.atom_record(campaign, terminal_path)
    assert record["contract_tau0"] == contract["tau0"]
    assert record["recorded_terminal_tau0"] == 0
    assert record["tau0_serialization_loss"] is True
    assert record["artifact_hashes_valid"] is True
    assert record["formal_converged"] is False
