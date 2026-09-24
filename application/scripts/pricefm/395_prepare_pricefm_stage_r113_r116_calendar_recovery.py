#!/usr/bin/env python3
"""Prepare the calendar-safe descendant of the stopped R113--R116 recovery."""

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

import numpy as np
import pandas as pd

from pricefm_common import sha256_file, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
PARENT = DATA / "campaigns/pricefm_stage_r113_r116_rolled_state_driver_recovery_20260923"
TAG = "pricefm_stage_r113_r116_calendar_recovery_20260923"
OUTPUT = DATA / "campaigns" / TAG
CHANGED_SOURCES = {
    "application/scripts/pricefm/390_run_pricefm_stage_r114_normal_driver.R",
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
        or contract.get("resume_mode") != "reuse_completed_r114_fits"
        or not expected
        or canonical_hash(unhashed) != expected
        or sha256_file(source_path) != str(contract.get("source_manifest_sha256"))
    ):
        raise RuntimeError("parent R113--R116 recovery contract is invalid")
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
            raise RuntimeError(f"parent frozen source/evidence changed: {path}")
    return contract, sources


def utc_strings(values: Any) -> pd.Series:
    parsed = pd.to_datetime(values, utc=True, errors="coerce")
    if pd.isna(parsed).any():
        raise RuntimeError("calendar timestamps do not parse as UTC")
    return pd.Series(parsed).dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_complete_surface(rows: pd.DataFrame, origin_times: list[str], label: str) -> None:
    selected = rows[rows._origin_time.isin(origin_times)].copy()
    observed = sorted(selected._origin_time.unique().tolist())
    if observed != sorted(origin_times):
        raise RuntimeError(f"{label} does not cover the requested origin calendar")
    if selected.duplicated(["_origin_time", "horizon"]).any():
        raise RuntimeError(f"{label} has duplicate origin/horizon rows")
    counts = selected.groupby("_origin_time").horizon.agg(
        lambda values: np.array_equal(np.sort(values.astype(int)), np.arange(1, 97))
    )
    if not counts.all():
        raise RuntimeError(f"{label} does not contain horizons 1--96 exactly once")


def build_shared_calendar(parent: Path, inner_fold: int) -> tuple[pd.DataFrame, Path]:
    bg_root = parent / f"runs/r114_normal_driver/region=BG/inner={inner_fold}"
    terminal = json.loads((bg_root / "terminal.json").read_text())
    if terminal.get("status") != "completed_r114_normal_driver":
        raise RuntimeError(f"BG Normal driver is incomplete for inner fold {inner_fold}")
    evaluation = pd.read_csv(bg_root / "evaluation_rows.csv")
    evaluation["_origin_time"] = utc_strings(evaluation.origin_market_time).to_numpy()
    validation_times = evaluation[["_origin_time"]].drop_duplicates()._origin_time.tolist()
    validate_complete_surface(evaluation, validation_times, "BG validation surface")

    old_manifest = pd.read_csv(parent / "parent_metadata/r114_normal_driver_manifest.csv")
    match = old_manifest[
        old_manifest.region.astype(str).eq("BG")
        & old_manifest.inner_fold.astype(int).eq(int(inner_fold))
    ]
    if len(match) != 1:
        raise RuntimeError("BG Normal-driver contract is not unique")
    old_contract = json.loads(Path(match.iloc[0].contract_path).read_text())
    rows_path = Path(old_contract["adapter_dir"]) / "rows_train.csv"
    rows = pd.read_csv(rows_path)
    rows["_origin_time"] = utc_strings(rows.origin_market_time).to_numpy()
    response = pd.to_datetime(rows.response_market_time, utc=True, errors="coerce")
    validation_start = pd.Timestamp(validation_times[0])
    train_mask = response.lt(validation_start) & pd.to_datetime(
        rows._origin_time, utc=True
    ).lt(validation_start)
    train_times = rows.loc[train_mask, ["_origin_time"]].drop_duplicates()._origin_time.tolist()
    validate_complete_surface(rows.loc[train_mask], train_times, "BG training surface")
    summary = pd.read_csv(bg_root / "embargo_summary.csv").iloc[0]
    if (
        len(train_times) != int(summary.n_train_origins)
        or len(validation_times) != int(summary.n_validation_origins)
        or len(evaluation) != len(validation_times) * 96
    ):
        raise RuntimeError("BG shared calendar disagrees with its completed fit")
    calendar = pd.DataFrame({
        "split": ["train"] * len(train_times) + ["validation"] * len(validation_times),
        "origin_market_time": train_times + validation_times,
        "calendar_order": list(range(len(train_times))) + list(range(len(validation_times))),
    })
    return calendar, rows_path


def completed_target_only_candidates(parent: Path) -> list[str]:
    bank = pd.read_csv(parent / "r115_candidate_bank.csv")
    completed = []
    for terminal_path in sorted((parent / "runs/r115_ridge").glob("candidate=*/terminal.json")):
        terminal = json.loads(terminal_path.read_text())
        if terminal.get("status") == "completed_r115_ridge_candidate" and terminal.get("test_opened") is False:
            completed.append(terminal_path.parent.name.split("=", 1)[1])
    selected = bank[bank.candidate_id.astype(str).isin(completed)]
    if (
        len(completed) != 12
        or len(selected) != 12
        or not selected.feature_policy.astype(str).eq("target_only").all()
        or not selected.graph_degree.astype(int).eq(0).all()
    ):
        raise RuntimeError("the reusable R115 set is not the exact 12 target-only candidates")
    return sorted(completed)


def inventory_reused_files(temporary: Path, output_root: Path) -> pd.DataFrame:
    rows = []
    roots = (
        Path("runs/r114_fit"),
        Path("runs/r114_normal_driver/region=BG"),
        Path("runs/r114_score"),
        Path("runs/r115_ridge"),
        Path("splits"),
    )
    for relative_root in roots:
        root = temporary / relative_root
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file():
                relative = path.relative_to(temporary)
                rows.append(file_record("reused_verified_artifact", path, output_root / relative))
    result = pd.DataFrame(rows)
    if result.empty or result.path.duplicated().any():
        raise RuntimeError("calendar recovery reuse inventory is empty or duplicated")
    return result


def prepare_calendar_recovery(
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
                if value.get("status") == "prepared_calendar_recovery_not_launched":
                    return value
            raise FileExistsError(output_root)
        shutil.rmtree(output_root)

    head = git_value(code_root, "rev-parse", "HEAD")
    upstream = git_value(code_root, "rev-parse", "@{upstream}")
    status = git_value(code_root, "status", "--porcelain")
    if require_clean and (status or head != upstream):
        raise RuntimeError("calendar recovery requires a clean synchronized task branch")
    parent_contract, parent_sources = verify_parent(parent, code_root)
    reusable_candidates = completed_target_only_candidates(parent)

    output_root.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=output_root.name + ".tmp.", dir=output_root.parent))
    try:
        link_tree(parent / "splits", temporary / "splits")
        link_tree(parent / "runs/r114_fit", temporary / "runs/r114_fit")
        link_tree(
            parent / "runs/r114_normal_driver/region=BG",
            temporary / "runs/r114_normal_driver/region=BG",
        )
        link_tree(parent / "runs/r114_score", temporary / "runs/r114_score")
        for candidate_id in reusable_candidates:
            link_tree(
                parent / f"runs/r115_ridge/candidate={candidate_id}",
                temporary / f"runs/r115_ridge/candidate={candidate_id}",
            )
        for name in REUSED_FLAT_FILES:
            shutil.copy2(parent / name, temporary / name)

        metadata = temporary / "parent_metadata"
        metadata.mkdir()
        for name in ("campaign_contract.json", "source_manifest.csv", "summary.json", "controller.log"):
            if (parent / name).is_file():
                shutil.copy2(parent / name, metadata / name)

        calendars = temporary / "shared_calendars"
        calendars.mkdir()
        calendar_records = []
        calendar_paths: dict[int, Path] = {}
        for inner in (1, 2, 3):
            calendar, rows_path = build_shared_calendar(parent, inner)
            path = calendars / f"inner_fold_{inner}.csv"
            calendar.to_csv(path, index=False)
            calendar_paths[inner] = path
            calendar_records.append({
                "inner_fold": inner,
                "calendar_path": str((output_root / "shared_calendars" / path.name).resolve()),
                "calendar_sha256": sha256_file(path),
                "train_origins": int(calendar.split.eq("train").sum()),
                "validation_origins": int(calendar.split.eq("validation").sum()),
                "reference_rows_path": str(rows_path.resolve()),
                "reference_rows_sha256": sha256_file(rows_path),
            })
        calendar_manifest = pd.DataFrame(calendar_records)
        calendar_manifest_path = temporary / "shared_calendar_manifest.csv"
        calendar_manifest.to_csv(calendar_manifest_path, index=False)

        old_manifest = pd.read_csv(parent / "parent_metadata/r114_normal_driver_manifest.csv")
        contracts = temporary / "contracts/r114_normal_driver"
        contracts.mkdir(parents=True)
        task_rows = []
        for region in ("GR", "RO"):
            for inner in (1, 2, 3):
                match = old_manifest[
                    old_manifest.region.astype(str).eq(region)
                    & old_manifest.inner_fold.astype(int).eq(inner)
                ]
                if len(match) != 1:
                    raise RuntimeError(f"old Normal-driver contract is not unique: {region} inner {inner}")
                value = json.loads(Path(match.iloc[0].contract_path).read_text())
                task_id = f"r114_normal_calendar__{region}__inner{inner}"
                final_calendar = output_root / "shared_calendars" / calendar_paths[inner].name
                value.update({
                    "task_id": task_id,
                    "output_dir": str((
                        output_root / f"runs/r114_normal_driver/region={region}/inner={inner}"
                    ).resolve()),
                    "helper_path": str((
                        code_root / "application/R/pricefm_recursive_normal_fit.R"
                    ).resolve()),
                    "horizon_helper_path": str((
                        code_root / "application/scripts/pricefm/pricefm_horizon_readout.R"
                    ).resolve()),
                    "calendar_alignment_mode": "reference_region_shared_origin_times",
                    "reference_region": "BG",
                    "calendar_key": "origin_market_time_utc",
                    "shared_calendar_path": str(final_calendar.resolve()),
                    "shared_calendar_sha256": sha256_file(calendar_paths[inner]),
                })
                value.pop("task_contract_sha256", None)
                value["task_contract_sha256"] = canonical_hash(value)
                path = contracts / f"{task_id}.json"
                write_json(path, value)
                task_rows.append({
                    "task_id": task_id,
                    "region": region,
                    "inner_fold": inner,
                    "contract_path": str((output_root / "contracts/r114_normal_driver" / path.name).resolve()),
                    "contract_sha256": sha256_file(path),
                    "output_dir": value["output_dir"],
                })
        task_manifest = pd.DataFrame(task_rows)
        task_manifest_path = temporary / "r114_normal_driver_manifest.csv"
        task_manifest.to_csv(task_manifest_path, index=False)

        reuse = inventory_reused_files(temporary, output_root)
        reuse_path = temporary / "calendar_recovery_reuse_manifest.csv"
        reuse.to_csv(reuse_path, index=False)
        report_path = temporary / "calendar_recovery_plan.md"
        report_path.write_text("\n".join([
            "# PriceFM R113--R116 calendar-safe recovery", "",
            "- Parent recovery is immutable failure evidence.",
            "- Reuse: 42 quantile atoms, three BG Normal drivers, three AL scores, and 12 target-only R115 candidates.",
            "- Refit: six GR/RO Normal drivers on exact BG UTC calendars.",
            "- Continue: 228 graph ridge candidates, bounded RHS confirmation, AL-only R116, and outer transfer closeout.",
            "- Test, registry, article, MCMC, joint-model, and all-region actions remain blocked.",
        ]) + "\n")

        source_rows = []
        root_text = str(code_root) + os.sep
        for row in parent_sources.itertuples(index=False):
            path = Path(row.path)
            relative = str(path)[len(root_text):] if str(path).startswith(root_text) else None
            if relative not in CHANGED_SOURCES:
                source_rows.append(file_record("parent_frozen_source_or_evidence", path))
        for relative in sorted(CHANGED_SOURCES | {
            "application/scripts/pricefm/395_prepare_pricefm_stage_r113_r116_calendar_recovery.py",
        }):
            source_rows.append(file_record("calendar_recovery_source", code_root / relative))
        source_rows.extend([
            file_record("parent_campaign_contract", parent / "campaign_contract.json"),
            file_record("parent_source_manifest", parent / "source_manifest.csv"),
            file_record("reuse_manifest", reuse_path, output_root / reuse_path.name),
            file_record("shared_calendar_manifest", calendar_manifest_path, output_root / calendar_manifest_path.name),
            file_record("calendar_recovery_plan", report_path, output_root / report_path.name),
        ])
        for path in sorted(calendars.glob("*.csv")):
            source_rows.append(file_record("shared_BG_calendar", path, output_root / "shared_calendars" / path.name))
        for path in sorted(contracts.glob("*.json")):
            source_rows.append(file_record("aligned_neighbor_contract", path, output_root / "contracts/r114_normal_driver" / path.name))
        source_manifest = pd.DataFrame(source_rows).drop_duplicates(subset=["path"], keep="last")
        source_manifest_path = temporary / "source_manifest.csv"
        source_manifest.to_csv(source_manifest_path, index=False)

        contract = {
            "stage": "R113_R116", "tag": TAG,
            "status": "prepared_calendar_recovery_not_launched",
            "resume_mode": "reuse_R114_then_refit_aligned_neighbors",
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
            "r114_score_families": ["al"], "r116_families": ["al"],
            "calendar_alignment_mode": "reference_region_shared_origin_times",
            "calendar_reference_region": "BG", "calendar_key": "origin_market_time_utc",
            "reused_r114_fit_cells": 45, "corrected_neighbor_driver_fit_cells": 6,
            "reused_r115_ridge_candidates": 12, "reused_r115_ridge_fit_cells": 72,
            "r115_ridge_candidates": parent_contract["r115_ridge_candidates"],
            "r115_ridge_fit_cells": parent_contract["r115_ridge_fit_cells"],
            "r115_rhs_maximum_fit_cells": parent_contract["r115_rhs_maximum_fit_cells"],
            "r116_family_maximum_fit_cells": parent_contract["r116_family_maximum_fit_cells"],
            "r116_factorial_maximum_fit_cells": parent_contract["r116_factorial_maximum_fit_cells"],
            "max_workers": parent_contract["max_workers"],
            "selection_split": parent_contract["selection_split"],
            "outer_validation_role": parent_contract["outer_validation_role"],
            "package_contract": parent_contract["package_contract"],
            "normal_package_contract": parent_contract["normal_package_contract"],
            "source_manifest_sha256": sha256_file(source_manifest_path),
            "candidate_bank_sha256": sha256_file(temporary / "r115_candidate_bank.csv"),
            "r114_reuse_manifest": reuse_path.name,
            "r114_reuse_manifest_sha256": sha256_file(reuse_path),
            "shared_calendar_manifest_sha256": sha256_file(calendar_manifest_path),
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
            **contract,
            "output_root": str(output_root),
            "reused_quantile_atoms": 42,
            "reused_BG_normal_driver_tasks": 3,
            "aligned_neighbor_refit_tasks": 6,
            "reused_target_only_candidates": 12,
            "remaining_graph_candidates": 228,
            "next_action": "jerez_preflight_then_refit_six_aligned_neighbor_drivers",
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
    result = prepare_calendar_recovery(
        args.code_root, args.parent_campaign, args.output_root, force=args.force,
    )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
