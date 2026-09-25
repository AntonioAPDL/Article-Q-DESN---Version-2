#!/usr/bin/env python3
"""Freeze the stopped, numerically blocked PriceFM R117 campaign."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


TAG = "pricefm_stage_r117_bg_pure_all_layer_recursive_20260925"
EXPECTED_QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=Path("/data/jaguir26/local/src/Article-Q-DESN"))
    value.add_argument("--campaign-root", type=Path)
    value.add_argument("--output-dir", type=Path)
    return value


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _finite(value: Any) -> bool:
    try:
        return math.isfinite(float(value))
    except (TypeError, ValueError):
        return False


def classify_trace_tail(family: str, tail: pd.DataFrame) -> dict[str, Any]:
    if tail.empty:
        return {
            "diagnostic_class": "missing_trace",
            "tail_rows": 0,
            "scale_stable": False,
            "elbo_stable": False,
            "divergent": True,
        }
    last = tail.iloc[-1]
    sigma = float(last["sigma"])
    delta_state = abs(float(last["delta_state"]))
    delta_sigma = abs(float(last["delta_sigma"]))
    delta_elbo = abs(float(last["delta_elbo"]))
    elbo = abs(float(last["elbo"]))
    scale_stable = sigma < 100.0 and delta_sigma <= 1e-6
    elbo_stable = delta_elbo / max(1.0, elbo) <= 1e-8
    divergent = sigma >= 100.0 or delta_state >= 1e3 or delta_sigma >= 1.0
    if divergent:
        diagnostic_class = "genuine_numerical_divergence"
    elif family == "al" and scale_stable and elbo_stable:
        diagnostic_class = "finite_scale_elbo_stable_state_unresolved"
    elif family == "exal" and scale_stable and elbo_stable:
        diagnostic_class = "finite_exal_state_unresolved"
    else:
        diagnostic_class = "nonconverged_unresolved"
    return {
        "diagnostic_class": diagnostic_class,
        "tail_rows": int(len(tail)),
        "scale_stable": bool(scale_stable),
        "elbo_stable": bool(elbo_stable),
        "divergent": bool(divergent),
        "final_elbo": float(last["elbo"]),
        "final_sigma": sigma,
        "final_gamma": None if str(last.get("gamma", "NA")) == "NA" else float(last["gamma"]),
        "final_delta_state": delta_state,
        "final_delta_sigma": delta_sigma,
        "final_delta_elbo": float(last["delta_elbo"]),
    }


def _verify_terminal_artifacts(root: Path, terminal: dict[str, Any]) -> bool:
    records = terminal.get("artifacts", [])
    if not isinstance(records, list) or not records:
        return False
    for record in records:
        path = root / str(record["path"])
        if not path.is_file() or sha256_file(path) != str(record["sha256"]):
            return False
    return True


def atom_record(campaign: Path, terminal_path: Path) -> dict[str, Any]:
    terminal = _read_json(terminal_path)
    atom_root = terminal_path.parent
    family = str(terminal["family"])
    tau = float(terminal["tau"])
    fold = int(next(part.split("=", 1)[1] for part in atom_root.parts if part.startswith("fold=")))
    contract_path = campaign / f"full_folds/fold={fold}/quantile_contracts/{family}_tau={tau:.2f}.json"
    contract = _read_json(contract_path)
    trace_path = atom_root / "vb_trace.csv"
    trace = pd.read_csv(trace_path)
    tail = trace.tail(min(50, len(trace)))
    diagnosis = classify_trace_tail(family, tail)
    contract_tau0 = float(contract["tau0"])
    recorded_tau0 = float(terminal["tau0"])
    return {
        "variant": str(contract["variant"]),
        "fold": fold,
        "family": family,
        "tau": tau,
        "atom_id": str(terminal["atom_id"]),
        "contract_path": str(contract_path.resolve()),
        "contract_sha256": sha256_file(contract_path),
        "artifact_root": str(atom_root.resolve()),
        "terminal_sha256": sha256_file(terminal_path),
        "artifact_hashes_valid": _verify_terminal_artifacts(atom_root, terminal),
        "finite_core": bool(terminal.get("finite_core")),
        "formal_converged": bool(terminal.get("formal_converged")),
        "numerically_eligible": bool(terminal.get("numerically_eligible")),
        "contract_tau0": contract_tau0,
        "recorded_terminal_tau0": recorded_tau0,
        "tau0_serialization_loss": contract_tau0 > 0 and recorded_tau0 == 0,
        "posterior_target_sha256": str(terminal["posterior_target_sha256"]),
        "train_seconds": float(terminal["train_seconds"]),
        "package_version": str(terminal["package"]["version"]),
        "package_repository": str(terminal["package"]["repository"]),
        "test_opened": bool(terminal.get("test_opened")),
        **diagnosis,
    }


def _stage_counts(campaign: Path, atoms: pd.DataFrame) -> dict[str, Any]:
    ridge = _read_json(campaign / "ridge_closeout/summary.json")
    rhs = _read_json(campaign / "rhs_closeout/summary.json")
    extended = _read_json(campaign / "extended/tau0_closeout/summary.json")
    normal_terminals = list(campaign.glob("full_folds/fold=*/normal_rhs/terminal.json"))
    return {
        "ridge_complete": int(ridge["cells"]),
        "ridge_planned": 240,
        "rhs_attempted": int(rhs["planned_cells"]),
        "rhs_scored": int(rhs["scored_cells"]),
        "rhs_excluded": int(rhs["incomplete_or_failed_cells"]),
        "rhs_eligible_complete_groups": int(rhs["eligible_complete_groups"]),
        "extended_tau0_complete": int(extended["fit_completed_cells"]),
        "extended_tau0_planned": int(extended["planned_cells"]),
        "pure_normal_complete": len(normal_terminals),
        "pure_normal_planned": 3,
        "pure_quantile_complete": int(len(atoms)),
        "pure_quantile_planned": 42,
        "pure_quantile_remaining": 42 - int(len(atoms)),
        "extended_normal_complete": len(list(campaign.glob("extended/full_folds/fold=*/normal_rhs/terminal.json"))),
        "extended_normal_planned": 3,
        "extended_quantile_complete": len(list(campaign.glob("extended/full_folds/fold=*/quantiles/*/tau=*/terminal.json"))),
        "extended_quantile_planned": 42,
    }


def _markdown(summary: dict[str, Any], atoms: pd.DataFrame) -> str:
    counts = summary["counts"]
    lines = [
        "# PriceFM R117 blocked partial closeout",
        "",
        f"Status: `{summary['status']}`",
        "",
        "R117 was stopped after its quantile-family gate became mathematically unreachable.",
        "No outer test data, registry, article, joint model, or MCMC surface was opened.",
        "",
        "| Stage | Complete | Planned |",
        "|---|---:|---:|",
        f"| Ridge | {counts['ridge_complete']} | {counts['ridge_planned']} |",
        f"| Normal RHS attempted | {counts['rhs_attempted']} | {counts['rhs_attempted']} |",
        f"| Extended tau0 | {counts['extended_tau0_complete']} | {counts['extended_tau0_planned']} |",
        f"| Pure full Normal | {counts['pure_normal_complete']} | {counts['pure_normal_planned']} |",
        f"| Pure quantile | {counts['pure_quantile_complete']} | {counts['pure_quantile_planned']} |",
        f"| Extended full Normal | {counts['extended_normal_complete']} | {counts['extended_normal_planned']} |",
        f"| Extended quantile | {counts['extended_quantile_complete']} | {counts['extended_quantile_planned']} |",
        "",
        "## Quantile diagnosis",
        "",
    ]
    grouped = atoms.groupby(["family", "diagnostic_class"]).size().reset_index(name="atoms")
    lines.extend(["| Family | Diagnostic class | Atoms |", "|---|---|---:|"])
    lines.extend(
        f"| {row.family} | {row.diagnostic_class} | {int(row.atoms)} |"
        for row in grouped.itertuples(index=False)
    )
    lines.extend([
        "",
        "The nonzero tau0 values in the contracts were used by the fit. The zero values in",
        "R117 terminal JSON are a jsonlite precision-loss defect and are not fit inputs.",
        "",
        "## Decision",
        "",
        "Preserve all screening, design, winner, and Normal artifacts. Do not promote any",
        "R117 quantile result. Continue through a separately versioned R118 numerical repair.",
        "",
    ])
    return "\n".join(lines)


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve()
    campaign = (args.campaign_root or artifact / "application/data_local/pricefm/campaigns" / TAG).resolve()
    output = (args.output_dir or campaign / "partial_closeout").resolve()
    if (campaign / "campaign_terminal.json").exists():
        raise RuntimeError("R117 already has a normal campaign terminal; refusing blocked closeout")
    paths = sorted(campaign.glob("full_folds/fold=*/quantiles/*/tau=*/terminal.json"))
    atoms = pd.DataFrame(atom_record(campaign, path) for path in paths)
    if atoms.empty or atoms.atom_id.duplicated().any():
        raise RuntimeError("R117 quantile terminal inventory is empty or duplicated")
    if atoms.test_opened.any() or not atoms.artifact_hashes_valid.all():
        raise RuntimeError("R117 artifact or test firewall failed")
    families = {
        family: {
            "complete": int(len(group)),
            "eligible": int(group.numerically_eligible.sum()),
            "divergent": int(group.divergent.sum()),
        }
        for family, group in atoms.groupby("family")
    }
    summary = {
        "stage": "R117",
        "status": "stopped_blocked_quantile_numerics_not_promoted",
        "campaign": str(campaign),
        "counts": _stage_counts(campaign, atoms),
        "families": families,
        "existing_family_gate_reachable": False,
        "reuse_authorized": ["ridge", "rhs", "winners", "designs", "normal_rhs"],
        "reuse_quantile_atoms": False,
        "next_stage": "R118_exact_cran_quantile_mechanism_repair",
        "test_opened": False,
        "registry_mutated": False,
        "article_mutated": False,
        "joint_model_fitted": False,
        "mcmc_fitted": False,
    }
    output.mkdir(parents=True, exist_ok=True)
    atoms_path = output / "quantile_atom_audit.csv"
    atoms.to_csv(atoms_path, index=False, quoting=csv.QUOTE_MINIMAL)
    write_json(output / "summary.json", summary)
    (output / "README.md").write_text(_markdown(summary, atoms))
    sources = [
        campaign / "winner/winner.json",
        campaign / "winner/extended_winner.json",
        campaign / "ridge_closeout/summary.json",
        campaign / "rhs_closeout/summary.json",
        campaign / "extended/tau0_closeout/summary.json",
        atoms_path,
        output / "summary.json",
        output / "README.md",
    ]
    write_json(output / "manifest.json", {
        "status": "hash_sealed_r117_blocked_closeout",
        "files": [{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in sources],
        "test_opened": False,
    })
    return summary


def main() -> int:
    result = run(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
