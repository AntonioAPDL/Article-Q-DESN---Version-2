#!/usr/bin/env python3
"""Prepare R115--R116 recovery with calendar-to-local-index mapping throughout."""

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
PARENT = DATA / "campaigns/pricefm_stage_r113_r116_calendar_convergence_recovery_20260923"
TAG = "pricefm_stage_r113_r116_calendar_index_recovery_20260923"
OUTPUT = DATA / "campaigns" / TAG
CHANGED_SOURCES = {
    "application/scripts/pricefm/391_run_pricefm_stage_r113_r116_campaign.py",
    "application/scripts/pricefm/392_orchestrate_pricefm_stage_r113_r116_campaign.py",
}
REUSED_FLAT_FILES = (
    "nested_split_summary.csv",
    "r115_candidate_bank.csv",
    "r114_driver_horizon_metrics.csv",
    "r114_driver_metrics.csv",
    "r114_driver_ranking.csv",
    "r114_selected_driver.json",
    "r114_score_status.csv",
    "shared_calendar_manifest.csv",
)


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
        or contract.get("resume_mode") != "reuse_R114_then_refit_aligned_neighbors"
        or not expected
        or canonical_hash(unhashed) != expected
        or sha256_file(source_path) != str(contract.get("source_manifest_sha256"))
    ):
        raise RuntimeError("parent convergence recovery contract is invalid")
    sources = pd.read_csv(source_path)
    root_text = str(code_root.resolve()) + os.sep
    for row in sources.itertuples(index=False):
        path = Path(row.path)
        relative = str(path)[len(root_text):] if str(path).startswith(root_text) else None
        if relative in CHANGED_SOURCES:
            if not path.is_file():
                raise RuntimeError(f"changed recovery source is missing: {path}")
            continue
        if (
            not path.is_file()
            or path.stat().st_size != int(row.bytes)
            or sha256_file(path) != str(row.sha256)
        ):
            raise RuntimeError(f"parent convergence source/evidence changed: {path}")
    return contract, sources


def verify_six_aligned_neighbors(parent: Path) -> None:
    for region in ("GR", "RO"):
        for inner in (1, 2, 3):
            root = parent / f"runs/r114_normal_driver/region={region}/inner={inner}"
            terminal = json.loads((root / "terminal.json").read_text())
            shared = parent / f"shared_calendars/inner_fold_{inner}.csv"
            if (
                terminal.get("status") != "completed_r114_normal_driver"
                or terminal.get("calendar_alignment_mode") != "reference_region_shared_origin_times"
                or terminal.get("calendar_key") != "origin_market_time_utc"
                or terminal.get("shared_calendar_sha256") != sha256_file(shared)
                or terminal.get("test_opened") is not False
            ):
                raise RuntimeError(f"aligned R114 neighbor is not reusable: {root}")


def inventory_reused_files(temporary: Path, output_root: Path) -> pd.DataFrame:
    rows = []
    for relative_root in (
        Path("splits"), Path("shared_calendars"), Path("runs/r114_fit"),
        Path("runs/r114_score"), Path("runs/r114_normal_driver"),
    ):
        for path in sorted((temporary / relative_root).rglob("*")):
            if path.is_file():
                relative = path.relative_to(temporary)
                rows.append(file_record("reused_verified_R114_artifact", path, output_root / relative))
    result = pd.DataFrame(rows)
    if result.empty or result.path.duplicated().any():
        raise RuntimeError("calendar-index recovery reuse inventory is empty or duplicated")
    return result


def prepare_calendar_index_recovery(
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
                if value.get("status") == "prepared_calendar_index_recovery_not_launched":
                    return value
            raise FileExistsError(output_root)
        shutil.rmtree(output_root)

    head = git_value(code_root, "rev-parse", "HEAD")
    upstream = git_value(code_root, "rev-parse", "@{upstream}")
    status = git_value(code_root, "status", "--porcelain")
    if require_clean and (status or head != upstream):
        raise RuntimeError("calendar-index recovery requires a clean synchronized task branch")
    parent_contract, parent_sources = verify_parent(parent, code_root)
    verify_six_aligned_neighbors(parent)

    output_root.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_root.name + ".tmp.", dir=output_root.parent))
    try:
        for name in (
            "splits", "shared_calendars", "runs/r114_fit", "runs/r114_score",
            "runs/r114_normal_driver",
        ):
            link_tree(parent / name, temporary / name)
        for name in REUSED_FLAT_FILES:
            shutil.copy2(parent / name, temporary / name)

        metadata = temporary / "parent_metadata"
        metadata.mkdir()
        for name in (
            "campaign_contract.json", "source_manifest.csv", "summary.json",
            "controller.log", "r114_batch1_status.csv", "r115_ridge_status.csv",
        ):
            if (parent / name).is_file():
                shutil.copy2(parent / name, metadata / name)

        reuse = inventory_reused_files(temporary, output_root)
        reuse_path = temporary / "calendar_index_recovery_reuse_manifest.csv"
        reuse.to_csv(reuse_path, index=False)
        report_path = temporary / "calendar_index_recovery_plan.md"
        report_path.write_text("\n".join([
            "# PriceFM R113--R116 calendar-index recovery", "",
            "- All corrected R114 fits are reused and verified by hash.",
            "- All prior R115 outputs are excluded because candidate lag windows have different local origin positions.",
            "- R115 maps shared BG UTC train/validation calendars into each candidate's local indices.",
            "- R116 family splits use the selected candidate's calendar-mapped design indices.",
            "- R116 outer cells use a common UTC calendar and calendar-keyed Normal-driver lookup.",
            "- Registry, article, MCMC, joint-model, and all-region actions remain blocked.",
        ]) + "\n")

        source_rows = []
        root_text = str(code_root) + os.sep
        for row in parent_sources.itertuples(index=False):
            path = Path(row.path)
            relative = str(path)[len(root_text):] if str(path).startswith(root_text) else None
            if relative not in CHANGED_SOURCES:
                source_rows.append(file_record("parent_frozen_source_or_evidence", path))
        for relative in sorted(CHANGED_SOURCES | {
            "application/scripts/pricefm/397_prepare_pricefm_stage_r113_r116_calendar_index_recovery.py",
        }):
            source_rows.append(file_record("calendar_index_recovery_source", code_root / relative))
        source_rows.extend([
            file_record("parent_campaign_contract", parent / "campaign_contract.json"),
            file_record("parent_source_manifest", parent / "source_manifest.csv"),
            file_record("reuse_manifest", reuse_path, output_root / reuse_path.name),
            file_record("calendar_index_recovery_plan", report_path, output_root / report_path.name),
        ])
        source_manifest = pd.DataFrame(source_rows).drop_duplicates(subset=["path"], keep="last")
        source_manifest_path = temporary / "source_manifest.csv"
        source_manifest.to_csv(source_manifest_path, index=False)

        contract = {
            key: value for key, value in parent_contract.items()
            if key != "campaign_contract_sha256"
        }
        contract.update({
            "tag": TAG,
            "status": "prepared_calendar_index_recovery_not_launched",
            "resume_mode": "reuse_completed_calendar_aligned_R114",
            "code_root": str(code_root),
            "branch": git_value(code_root, "branch", "--show-current"),
            "head": head, "upstream": upstream,
            "parent_campaign": str(parent),
            "parent_campaign_contract_sha256": sha256_file(parent / "campaign_contract.json"),
            "parent_source_manifest_sha256": sha256_file(parent / "source_manifest.csv"),
            "source_manifest_sha256": sha256_file(source_manifest_path),
            "candidate_bank_sha256": sha256_file(temporary / "r115_candidate_bank.csv"),
            "r114_reuse_manifest": reuse_path.name,
            "r114_reuse_manifest_sha256": sha256_file(reuse_path),
            "reused_r115_ridge_candidates": 0,
            "reused_r115_ridge_fit_cells": 0,
            "invalidated_positional_r115_candidates": 12,
            "r115_calendar_policy": "shared_BG_UTC_calendar_to_candidate_local_indices",
            "r116_family_calendar_policy": "shared_BG_UTC_calendar_to_selected_local_indices",
            "r116_outer_calendar_policy": "common_UTC_origin_intersection",
        })
        contract["campaign_contract_sha256"] = canonical_hash(contract)
        write_json(temporary / "campaign_contract.json", contract)
        summary = {
            **contract,
            "output_root": str(output_root),
            "reused_R114_neighbor_drivers": 6,
            "r115_candidates_to_run": 240,
            "next_action": "jerez_preflight_then_run_all_240_calendar_mapped_R115_candidates",
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
    result = prepare_calendar_index_recovery(
        args.code_root, args.parent_campaign, args.output_root, force=args.force,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
