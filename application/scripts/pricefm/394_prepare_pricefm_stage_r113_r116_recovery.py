#!/usr/bin/env python3
"""Prepare a provenance-preserving recovery of the stopped R113--R116 campaign."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any

import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PARENT = DATA / "campaigns/pricefm_stage_r113_r116_rolled_state_driver_20260922"
TAG = "pricefm_stage_r113_r116_rolled_state_driver_recovery_20260923"
OUTPUT = DATA / "campaigns" / TAG
QUANTILES = (0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
APPROVED_CHANGED_SOURCES = {
    "application/scripts/pricefm/391_run_pricefm_stage_r113_r116_campaign.py",
    "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py",
}


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(payload.encode()).hexdigest()


def git_value(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def file_record(role: str, path: Path, final_path: Path | None = None) -> dict[str, Any]:
    return {
        "role": role,
        "path": str((final_path or path).resolve()),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def link_tree(source: Path, destination: Path) -> None:
    if not source.is_dir():
        raise FileNotFoundError(source)
    shutil.copytree(source, destination, copy_function=os.link)


def verify_parent(parent: Path, code_root: Path) -> tuple[dict[str, Any], pd.DataFrame]:
    contract_path = parent / "campaign_contract.json"
    source_path = parent / "source_manifest.csv"
    contract = json.loads(contract_path.read_text())
    expected = str(contract.get("campaign_contract_sha256", ""))
    unhashed = {key: value for key, value in contract.items() if key != "campaign_contract_sha256"}
    if (
        contract.get("stage") != "R113_R116"
        or contract.get("status") != "prepared_training_only_not_launched"
        or not expected
        or canonical_hash(unhashed) != expected
    ):
        raise RuntimeError("parent R113--R116 campaign contract is invalid")
    if sha256_file(source_path) != str(contract.get("source_manifest_sha256")):
        raise RuntimeError("parent source manifest changed")
    sources = pd.read_csv(source_path)
    root_text = str(code_root.resolve()) + os.sep
    for row in sources.itertuples(index=False):
        path = Path(row.path)
        relative = None
        if str(path).startswith(root_text):
            relative = str(path)[len(root_text):]
        if relative in APPROVED_CHANGED_SOURCES:
            if not path.is_file():
                raise RuntimeError(f"approved recovery source is missing: {path}")
            continue
        if (
            not path.is_file()
            or path.stat().st_size != int(row.bytes)
            or sha256_file(path) != str(row.sha256)
        ):
            raise RuntimeError(f"parent frozen evidence changed: {path}")
    return contract, sources


def r114_reuse_inventory(temporary: Path, output_root: Path) -> pd.DataFrame:
    rows = []
    for relative_root in (Path("runs/r114_fit"), Path("runs/r114_normal_driver")):
        for path in sorted((temporary / relative_root).rglob("*")):
            if path.is_file():
                relative = path.relative_to(temporary)
                rows.append(file_record(
                    "reused_completed_r114_artifact", path, output_root / relative
                ))
    result = pd.DataFrame(rows)
    if result.empty or result.path.duplicated().any():
        raise RuntimeError("R114 recovery inventory is empty or duplicated")
    return result


def r114_family_eligibility(temporary: Path) -> pd.DataFrame:
    rows = []
    for family in ("al", "exal"):
        for inner in (1, 2, 3):
            root = temporary / f"runs/r114_fit/family={family}/inner={inner}"
            terminal = json.loads((root / "terminal.json").read_text())
            axis_valid = (
                terminal.get("status") == "completed_r114_quantile_family_fit"
                and terminal.get("family") == family
                and terminal.get("fit_axis") == "inner_fold"
                and int(terminal.get("fit_axis_value", -1)) == inner
                and terminal.get("test_opened") is False
            )
            complete = 0
            eligible = 0
            for tau in QUANTILES:
                atom = root / f"tau={str(tau).replace('.', 'p')}/terminal.json"
                value = json.loads(atom.read_text())
                if (
                    value.get("status") == "completed_r114_quantile_atom"
                    and value.get("family") == family
                    and value.get("test_opened") is False
                ):
                    complete += 1
                    eligible += int(value.get("numerically_eligible") is True)
            family_eligible = axis_valid and complete == 7 and eligible == 7
            rows.append({
                "family": family, "inner_fold": inner, "axis_contract_valid": axis_valid,
                "atoms_expected": 7, "atoms_complete": complete, "atoms_eligible": eligible,
                "eligible": family_eligible,
                "decision": "score_training_only" if family_eligible else "exclude_before_validation_scoring",
                "test_opened": False,
            })
    result = pd.DataFrame(rows)
    if len(result) != 6:
        raise RuntimeError("R114 recovery eligibility ledger is incomplete")
    eligible = result.groupby("family").eligible.all().to_dict()
    if eligible != {"al": True, "exal": False}:
        raise RuntimeError(f"unexpected R114 family eligibility: {eligible}")
    return result


def prepare_recovery(
    code_root: Path,
    parent: Path = PARENT,
    output_root: Path = OUTPUT,
    *,
    force: bool = False,
    require_clean: bool = True,
) -> dict[str, Any]:
    code_root = code_root.resolve()
    parent = parent.resolve()
    output_root = output_root.resolve()
    if output_root.exists() and any(output_root.iterdir()):
        if not force:
            summary = output_root / "summary.json"
            if summary.is_file():
                value = json.loads(summary.read_text())
                if value.get("status") == "prepared_recovery_not_launched":
                    return value
            raise FileExistsError(output_root)
        shutil.rmtree(output_root)

    head = git_value(code_root, "rev-parse", "HEAD")
    upstream = git_value(code_root, "rev-parse", "@{upstream}")
    status = git_value(code_root, "status", "--porcelain")
    if require_clean and (status or head != upstream):
        raise RuntimeError("recovery preparation requires a clean synchronized task branch")
    parent_contract, parent_sources = verify_parent(parent, code_root)

    output_root.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_root.name + ".tmp.", dir=output_root.parent))
    try:
        for name in ("splits", "runs/r114_fit", "runs/r114_normal_driver"):
            link_tree(parent / name, temporary / name)
        for name in ("r115_candidate_bank.csv", "nested_split_summary.csv"):
            source = parent / name
            destination = temporary / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.link(source, destination)

        metadata = temporary / "parent_metadata"
        metadata.mkdir()
        for name in (
            "campaign_contract.json", "source_manifest.csv", "r114_fit_manifest.csv",
            "r114_normal_driver_manifest.csv", "r114_batch1_status.csv",
            "r114_batch2_status.csv", "r114_score_status.csv", "controller.log",
        ):
            source = parent / name
            if source.is_file():
                shutil.copy2(source, metadata / name)

        reuse = r114_reuse_inventory(temporary, output_root)
        reuse_path = temporary / "r114_reuse_manifest.csv"
        reuse.to_csv(reuse_path, index=False)
        eligibility = r114_family_eligibility(temporary)
        eligibility_path = temporary / "r114_family_eligibility_prep.csv"
        eligibility.to_csv(eligibility_path, index=False)

        family_terminals = list((temporary / "runs/r114_fit").glob("family=*/inner=*/terminal.json"))
        atom_terminals = list((temporary / "runs/r114_fit").glob("family=*/inner=*/tau=*/terminal.json"))
        normal_terminals = list((temporary / "runs/r114_normal_driver").glob("region=*/inner=*/terminal.json"))
        if (len(family_terminals), len(atom_terminals), len(normal_terminals)) != (6, 42, 9):
            raise RuntimeError("R114 recovery does not contain the exact 6/42/9 terminal set")

        report = "\n".join([
            "# PriceFM R113--R116 recovery contract", "",
            "- Parent campaign is immutable and remains the source of the completed R114 fits.",
            "- Reused fit cells: 42 quantile atoms and 9 Normal-RHS drivers.",
            "- AL eligibility: 21/21 atoms across three inner folds.",
            "- exAL eligibility: 3/21 atoms; excluded before validation scoring.",
            "- R114 refitting is unauthorized. Recovery starts with AL scoring.",
            "- R115 and R116 remain training-only until frozen outer transfer evaluation.",
            "- Test, registry, article, MCMC, joint-model, and all-region actions remain blocked.",
        ]) + "\n"
        report_path = temporary / "recovery_plan.md"
        report_path.write_text(report)

        source_rows = []
        for row in parent_sources.itertuples(index=False):
            path = Path(row.path)
            source_rows.append(file_record("recovery_source_or_frozen_evidence", path))
        new_source = code_root / "application/scripts/pricefm/394_prepare_pricefm_stage_r113_r116_recovery.py"
        source_rows.extend([
            file_record("recovery_source", new_source),
            file_record("parent_campaign_contract", parent / "campaign_contract.json"),
            file_record("parent_source_manifest", parent / "source_manifest.csv"),
            file_record("R114_reuse_manifest", reuse_path, output_root / reuse_path.name),
            file_record("R114_eligibility_ledger", eligibility_path, output_root / eligibility_path.name),
            file_record("recovery_plan", report_path, output_root / report_path.name),
        ])
        source_manifest = pd.DataFrame(source_rows).drop_duplicates(subset=["path"], keep="last")
        source_manifest_path = temporary / "source_manifest.csv"
        source_manifest.to_csv(source_manifest_path, index=False)

        contract = {
            "stage": "R113_R116", "tag": TAG,
            "status": "prepared_recovery_not_launched",
            "resume_mode": "reuse_completed_r114_fits",
            "code_root": str(code_root),
            "branch": git_value(code_root, "branch", "--show-current"),
            "head": head, "upstream": upstream,
            "parent_campaign": str(parent),
            "parent_campaign_contract_sha256": sha256_file(parent / "campaign_contract.json"),
            "parent_source_manifest_sha256": sha256_file(parent / "source_manifest.csv"),
            "region": parent_contract["region"],
            "outer_selection_fold": parent_contract["outer_selection_fold"],
            "inner_folds": parent_contract["inner_folds"],
            "families": parent_contract["families"],
            "quantiles": parent_contract["quantiles"],
            "posterior_paths": parent_contract["posterior_paths"],
            "rank_policies": parent_contract["rank_policies"],
            "readout_modes": parent_contract["readout_modes"],
            "r114_score_families": ["al"],
            "r116_families": ["al"],
            "excluded_family": {
                "family": "exal", "reason": "18_of_21_atoms_nonconverged_at_iteration_500",
                "exclusion_stage": "before_validation_scoring",
            },
            "reused_r114_fit_cells": 51,
            "r114_refit_authorized": False,
            "r115_ridge_candidates": parent_contract["r115_ridge_candidates"],
            "r115_ridge_fit_cells": parent_contract["r115_ridge_fit_cells"],
            "r115_rhs_maximum_fit_cells": parent_contract["r115_rhs_maximum_fit_cells"],
            "r116_family_maximum_fit_cells": 21,
            "r116_factorial_maximum_fit_cells": 42,
            "max_workers": parent_contract["max_workers"],
            "selection_split": parent_contract["selection_split"],
            "outer_validation_role": parent_contract["outer_validation_role"],
            "package_contract": parent_contract["package_contract"],
            "normal_package_contract": parent_contract["normal_package_contract"],
            "source_manifest_sha256": sha256_file(source_manifest_path),
            "candidate_bank_sha256": sha256_file(temporary / "r115_candidate_bank.csv"),
            "r114_reuse_manifest": reuse_path.name,
            "r114_reuse_manifest_sha256": sha256_file(reuse_path),
            "r114_family_eligibility_sha256": sha256_file(eligibility_path),
            "test_access_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
            "mcmc_authorized": False,
            "joint_model_authorized": False,
            "broad_all_region_authorized": False,
        }
        contract["campaign_contract_sha256"] = canonical_hash(contract)
        write_json(temporary / "campaign_contract.json", contract)
        summary = {
            **contract, "output_root": str(output_root),
            "reused_family_fit_tasks": 6, "reused_quantile_atoms": 42,
            "reused_normal_driver_tasks": 9,
            "next_action": "jerez_preflight_then_resume_from_R114_AL_scoring",
        }
        write_json(temporary / "summary.json", summary)
        if output_root.exists():
            shutil.rmtree(output_root)
        temporary.rename(output_root)
        return summary
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--code-root", type=Path, default=Path.cwd())
    parser.add_argument("--parent-campaign", type=Path, default=PARENT)
    parser.add_argument("--output-root", type=Path, default=OUTPUT)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    result = prepare_recovery(
        args.code_root, args.parent_campaign, args.output_root, force=args.force
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
