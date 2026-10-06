"""Shared validation helpers for the PriceFM R118 quantile continuation."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from pricefm_common import sha256_file


TAIL_ROWS = 25


def finite_float(value: Any) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def verify_artifacts(root: Path, terminal: dict[str, Any]) -> bool:
    records = terminal.get("artifacts", [])
    if not isinstance(records, list) or not records:
        return False
    return all(
        (root / str(record["path"])).is_file()
        and sha256_file(root / str(record["path"])) == str(record["sha256"])
        for record in records
    )


def relative_tail_gate(
    beta: np.ndarray,
    trace: pd.DataFrame,
    sigma: float,
    gamma: float,
    release_iter: int = 0,
    formal_converged: bool = False,
) -> dict[str, Any]:
    post_release = trace.loc[trace["iter"] > int(release_iter)].copy()
    tail = post_release.tail(min(TAIL_ROWS, len(post_release)))
    if tail.empty or not np.isfinite(beta).all() or not finite_float(sigma) or not finite_float(gamma):
        return {
            "external_gate_passed": False,
            "post_release_updates": int(len(post_release)),
            "relative_state_tail_max": math.inf,
            "relative_sigma_tail_max": math.inf,
            "relative_elbo_tail_max": math.inf,
            "bounded": False,
        }
    beta_scale = max(1.0, float(np.max(np.abs(beta))))
    relative_state = float(np.max(np.abs(tail.delta_state))) / beta_scale
    relative_sigma = float(np.max(np.abs(tail.delta_sigma))) / max(1e-12, abs(float(sigma)))
    relative_elbo = float(np.max(np.abs(tail.delta_elbo))) / max(1.0, float(np.max(np.abs(tail.elbo))))
    bounded = float(sigma) > 0 and float(sigma) < 100 and abs(float(gamma)) < 20
    passed = (
        bounded
        and (bool(formal_converged) or len(post_release) >= 35)
        and relative_state <= 1e-3
        and relative_sigma <= 1e-3
        and relative_elbo <= 1e-5
    )
    return {
        "external_gate_passed": bool(passed),
        "post_release_updates": int(len(post_release)),
        "relative_state_tail_max": relative_state,
        "relative_sigma_tail_max": relative_sigma,
        "relative_elbo_tail_max": relative_elbo,
        "bounded": bool(bounded),
    }


def audit_atom(atom_dir: Path, contract_path: Path) -> dict[str, Any]:
    atom_dir = Path(atom_dir).resolve()
    contract_path = Path(contract_path).resolve()
    terminal_path = atom_dir / "terminal.json"
    if not terminal_path.is_file() or not contract_path.is_file():
        return {"admissible": False, "reason": "missing_terminal_or_contract"}
    terminal = json.loads(terminal_path.read_text())
    contract = json.loads(contract_path.read_text())
    if terminal.get("test_opened", True) or contract.get("test_access_authorized", True):
        return {"admissible": False, "reason": "test_firewall_failed"}
    if terminal.get("package", {}).get("version") != "1.1.1" or terminal.get("package", {}).get("repository") != "CRAN":
        return {"admissible": False, "reason": "package_contract_failed"}
    if not verify_artifacts(atom_dir, terminal):
        return {"admissible": False, "reason": "artifact_hash_failed"}
    p = int(terminal["p"])
    beta = np.fromfile(atom_dir / "beta_mean.bin", dtype="<f8")
    covariance = np.fromfile(atom_dir / "beta_cov.bin", dtype="<f8")
    trace = pd.read_csv(atom_dir / "vb_trace.csv")
    parameters = json.loads((atom_dir / "parameter_summary.json").read_text())
    finite = (
        beta.size == p
        and covariance.size == p * p
        and np.isfinite(beta).all()
        and np.isfinite(covariance).all()
        and np.all(np.diag(covariance.reshape(p, p)) > 0)
    )
    release = max(
        int(terminal.get("sigmagam_freeze_warmup_iters", 0)),
        int(terminal.get("rhs_freeze_tau_warmup_iters", 0)),
    )
    gate = relative_tail_gate(
        beta, trace, float(parameters["sigma"]), float(parameters.get("gamma", 0)), release,
        bool(terminal.get("formal_converged", False)),
    )
    contract_tau0 = float(contract["tau0"])
    identity = (
        str(terminal["family"]) == str(contract["family"])
        and float(terminal["tau"]) == float(contract["tau"])
        and str(terminal["posterior_target_sha256"]) == str(contract["posterior_target_sha256"])
        and contract_tau0 > 0
    )
    admissible = finite and identity and gate["external_gate_passed"]
    return {
        "admissible": bool(admissible),
        "reason": "passed_external_gate" if admissible else "external_or_identity_gate_failed",
        "atom_dir": str(atom_dir),
        "terminal_path": str(terminal_path),
        "terminal_sha256": sha256_file(terminal_path),
        "contract_path": str(contract_path),
        "contract_sha256": sha256_file(contract_path),
        "family": str(terminal["family"]),
        "tau": float(terminal["tau"]),
        "p": p,
        "contract_tau0": contract_tau0,
        "terminal_tau0": float(terminal.get("tau0", 0)),
        "tau0_serialization_loss": contract_tau0 > 0 and float(terminal.get("tau0", 0)) == 0,
        "formal_converged": bool(terminal.get("formal_converged", False)),
        "finite_core": bool(terminal.get("finite_core", False) and finite),
        "artifact_hashes_valid": True,
        "posterior_target_sha256": str(contract["posterior_target_sha256"]),
        "sigma": float(parameters["sigma"]),
        "gamma": float(parameters.get("gamma", 0)),
        **gate,
    }
