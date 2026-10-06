#!/usr/bin/env python3
"""Prepare a score-blind R122 Stage-0A AL convergence calibration."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
SOURCE_TAG = "pricefm_stage_r121b_bg_targeted_dense_refinement_repair_20260928"
TAG = "pricefm_stage_r122_stage0a_convergence_calibration_20260929"
CAPS = (750, 1000)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--artifact-repo", type=Path, default=DEFAULT_ARTIFACT_REPO)
    value.add_argument("--code-root", type=Path, default=SCRIPT_DIR.parents[2])
    value.add_argument("--source-campaign", type=Path)
    value.add_argument("--output-dir", type=Path)
    value.add_argument("--campaign-root", type=Path)
    return value


def _json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def calibration_sources(source: Path) -> pd.DataFrame:
    shortlist = pd.read_csv(source / "imported_screening/unique_normal_shortlist.csv")
    shortlist = shortlist.sort_values(["mean_AQL", "candidate_id"], kind="mergesort")
    selected: dict[str, dict[str, Any]] = {}
    for candidate_id in shortlist.candidate_id.astype(str):
        contract = source / "al_internal" / candidate_id / "split=3/quantiles/contracts/tau=0.50.json"
        selected[str(contract.resolve())] = {
            "source_contract": str(contract.resolve()), "reason": "split3_median_geometry_control",
        }
    for diagnostics in sorted(source.glob("al_internal/**/quantiles/al/tau=*/diagnostics.json")):
        if not bool(_json(diagnostics).get("external_gate_passed")):
            atom_root = diagnostics.parent
            split_root = next(parent for parent in atom_root.parents if parent.name.startswith("split="))
            contract = split_root / "quantiles/contracts" / f"{atom_root.name}.json"
            selected[str(contract.resolve())] = {
                "source_contract": str(contract.resolve()), "reason": "observed_external_gate_failure",
            }
    rows = []
    for item in selected.values():
        path = Path(item["source_contract"])
        if not path.is_file():
            raise FileNotFoundError(path)
        contract = _json(path)
        output = Path(contract["output_dir"])
        terminal = output / "terminal.json"
        diagnostics = output / "diagnostics.json"
        if not terminal.is_file() or not diagnostics.is_file():
            raise RuntimeError(f"calibration source is not terminal: {path}")
        rows.append({
            **item, "source_contract_sha256": sha256_file(path),
            "candidate_id": contract["candidate_id"], "split": int(contract["split"]),
            "tau": float(contract["tau"]), "source_atom_id": contract["atom_id"],
            "posterior_target_sha256": contract["posterior_target_sha256"],
            "source_external_gate_passed": bool(_json(diagnostics)["external_gate_passed"]),
        })
    result = pd.DataFrame(rows).sort_values(["candidate_id", "split", "tau"], kind="mergesort")
    if len(result) != 4 or result.candidate_id.nunique() != 3:
        raise RuntimeError("R122 Stage-0A requires three medians plus every observed failed atom")
    return result.reset_index(drop=True)


def _contract(source_path: Path, source_hash: str, cap: int, campaign: Path) -> dict[str, Any]:
    source = _json(source_path)
    candidate = str(source["candidate_id"]); split = int(source["split"]); tau = float(source["tau"])
    output = campaign / f"cap={cap}" / candidate / f"split={split}" / f"tau={tau:.2f}"
    result = dict(source)
    result.update({
        "tag": TAG, "atom_id": f"r122_stage0a_{candidate}_s{split}_q{tau:.2f}_i{cap}",
        "max_iter": int(cap), "output_dir": str(output.resolve()),
        "calibration_stage": "R122_stage0A_convergence_only",
        "calibration_only": True, "score_access_authorized": False,
        "selection_authorized": False, "calibration_source_contract": str(source_path.resolve()),
        "calibration_source_contract_sha256": source_hash,
        "calibration_source_atom_id": source["atom_id"],
        "calibration_iteration_cap": int(cap),
    })
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    artifact = args.artifact_repo.resolve(); code = args.code_root.resolve()
    data = artifact / "application/data_local/pricefm"
    source = (args.source_campaign or data / "campaigns" / SOURCE_TAG).resolve()
    output = (args.output_dir or data / "launch_prep" / TAG).resolve()
    campaign = (args.campaign_root or data / "campaigns" / TAG).resolve()
    if output.exists() and any(output.iterdir()):
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=False if not output.exists() else True)
    sources = calibration_sources(source)
    sources.to_csv(output / "calibration_atoms.csv", index=False)

    contracts = []
    for cap in CAPS:
        for row in sources.itertuples(index=False):
            source_path = Path(row.source_contract)
            contract = _contract(source_path, row.source_contract_sha256, cap, campaign)
            path = output / "contracts" / f"cap={cap}" / f"{contract['atom_id']}.json"
            path.parent.mkdir(parents=True, exist_ok=True); write_json(path, contract)
            contracts.append({"cap": cap, "candidate_id": contract["candidate_id"],
                              "split": contract["split"], "tau": contract["tau"],
                              "contract": str(path.resolve()), "contract_sha256": sha256_file(path),
                              "output_dir": contract["output_dir"],
                              "posterior_target_sha256": contract["posterior_target_sha256"]})
    contract_frame = pd.DataFrame(contracts)
    contract_frame.to_csv(output / "contract_manifest.csv", index=False)

    atom_script = code / "application/scripts/pricefm/420_fit_pricefm_stage_r121_quantile_atom.R"
    source_paths = [Path(__file__).resolve(), SCRIPT_DIR / "pricefm_r122_engine.py",
                    SCRIPT_DIR / "422_run_pricefm_stage_r122_stage0_calibration.py", atom_script]
    if any(not path.is_file() for path in source_paths):
        raise FileNotFoundError("R122 Stage-0A source bundle is incomplete")
    pd.DataFrame([{"path": str(path.resolve()), "sha256": sha256_file(path)} for path in source_paths]).to_csv(
        output / "source_manifest.csv", index=False)
    source_terminal = source / "campaign_terminal.json"
    control = {
        "stage": "R122_stage0A", "tag": TAG, "status": "prepared_not_launched",
        "source_campaign": str(source), "source_campaign_terminal_at_preparation": source_terminal.is_file(),
        "atom_script": str(atom_script.resolve()), "atom_script_sha256": sha256_file(atom_script),
        "caps": list(CAPS), "atom_count_per_cap": len(sources),
        "policy": "run_all_atoms_at_750_then_all_atoms_at_1000_only_if_any_750_atom_is_ineligible",
        "score_access_authorized": False, "test_access_authorized": False,
        "selection_authorized": False, "registry_mutation_authorized": False,
        "article_mutation_authorized": False, "joint_model_authorized": False,
        "mcmc_authorized": False, "exal_authorized": False,
        "campaign_root": str(campaign), "rscript": "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
        "minimum_memory_gib": 200, "minimum_free_gib": 200,
    }
    write_json(output / "launch_control.json", control)
    gates = {
        "four_atoms": len(sources) == 4,
        "three_geometries": sources.candidate_id.nunique() == 3,
        "all_split3_medians": len(sources[(sources.split == 3) & (sources.tau == .5)]) == 3,
        "all_observed_failures_included": int((~sources.source_external_gate_passed).sum()) == 2,
        "posterior_targets_preserved": contract_frame.groupby(["candidate_id", "split", "tau"]).posterior_target_sha256.nunique().eq(1).all(),
        "no_scores": not any("score" in Path(path).name.lower() for path in contract_frame.contract),
        "test_blocked": True, "article_registry_blocked": True,
    }
    gates = {key: bool(value) for key, value in gates.items()}
    write_json(output / "preparation_gates.json", {"checks": gates, "status": "passed" if all(gates.values()) else "failed"})
    if not all(gates.values()):
        raise RuntimeError(f"R122 Stage-0A preparation gate failed: {gates}")
    files = ("calibration_atoms.csv", "contract_manifest.csv", "source_manifest.csv",
             "launch_control.json", "preparation_gates.json")
    summary = {**control, "status": "prepared_r122_stage0a_calibration",
               "launch_authorized": True,
               "output_sha256": {name: sha256_file(output / name) for name in files}}
    write_json(output / "summary.json", summary)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
