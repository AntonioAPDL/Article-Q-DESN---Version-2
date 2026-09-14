#!/usr/bin/env python3
"""Audit and freeze a two-host continuation contract for PriceFM Stage R97."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from statistics import median
import subprocess
import sys
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import (
    assign_regions,
    controller_lock_available,
    estimate_remaining,
    firewall,
    scan_region,
    verify_seal,
    write_sealed,
)
from pricefm_region_frozen_contract import (
    canonical_sha256,
    file_record,
    git_identity,
    verify_file_record,
)


ARTIFACT_ROOT = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA_ROOT = ARTIFACT_ROOT / "application/data_local/pricefm"
TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
CAMPAIGN_ROOT = DATA_ROOT / "campaigns" / TAG
PREP_ROOT = DATA_ROOT / "authoritative" / f"{TAG}_prep"
CONTRACT = PREP_ROOT / "pricefm_stage_r97_campaign_contract.json"
OUTPUT = DATA_ROOT / "authoritative" / f"{TAG}_distributed_continuation"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--campaign-contract", type=Path, default=CONTRACT)
    value.add_argument("--campaign-root", type=Path, default=CAMPAIGN_ROOT)
    value.add_argument("--code-root", type=Path, required=True)
    value.add_argument("--output-dir", type=Path, default=OUTPUT)
    value.add_argument("--mode", choices=("preview", "freeze"), default="preview")
    value.add_argument("--muscat-workers", type=int, default=20)
    value.add_argument("--jerez-workers", type=int, default=50)
    value.add_argument("--jerez-regions", type=int, default=25)
    value.add_argument("--fallback-cell-seconds", type=float, default=260.0)
    value.add_argument("--write", action="store_true")
    value.add_argument("--force", action="store_true")
    return value


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0]) if rows else []
    temporary = path.with_name(f"{path.name}.tmp")
    with temporary.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def _contract(path: Path, campaign_root: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    verify_seal(payload, "campaign_contract_sha256", label="R97 campaign contract")
    if Path(payload["campaign_root"]).resolve() != campaign_root.resolve():
        raise RuntimeError("R97 campaign root differs from the sealed parent contract")
    if len(payload["regions_to_fit"]) != 37 or len(set(payload["regions_to_fit"])) != 37:
        raise RuntimeError("R97 distributed continuation requires the exact 37-region surface")
    for name in ("authority_registry", "resolved_controls", "se2_reuse", "source_data_config"):
        verify_file_record(payload[name], label=f"R97 {name}")
    return payload


def _git_identity_for_planning(code_root: Path) -> dict[str, Any]:
    try:
        return git_identity(code_root).to_dict()
    except subprocess.CalledProcessError:
        def git(*values: str) -> str:
            return subprocess.check_output(["git", *values], cwd=code_root, text=True).strip()
        return {
            "worktree": str(code_root.resolve()),
            "branch": git("branch", "--show-current"),
            "head": git("rev-parse", "HEAD"),
            "upstream": None,
            "upstream_head": None,
            "clean": not bool(git("status", "--porcelain=v1", "--untracked-files=normal")),
        }


def build(args: argparse.Namespace) -> dict[str, Any]:
    if not 1 <= args.muscat_workers <= 20:
        raise RuntimeError("Muscat worker count must be 1--20")
    if not 1 <= args.jerez_workers <= 50:
        raise RuntimeError("Jerez worker count must be 1--50")
    parent = _contract(args.campaign_contract.resolve(), args.campaign_root.resolve())
    lock_free = controller_lock_available(args.campaign_root)
    if args.mode == "freeze" and not lock_free:
        raise RuntimeError("freeze requires the original R97 controller to be stopped and drained")

    scanned = [scan_region(args.campaign_root, region) for region in parent["regions_to_fit"]]
    observed_times = [float(row["median_cell_seconds"]) for row in scanned if row["median_cell_seconds"]]
    fallback = median(observed_times) if observed_times else float(args.fallback_cell_seconds)
    estimated = estimate_remaining(scanned, fallback)
    assigned, loads = assign_regions(
        estimated,
        jerez_region_count=args.jerez_regions,
        workers={"muscat": args.muscat_workers, "jerez": args.jerez_workers},
    )
    completed = sum(int(row["ridge_complete"]) for row in assigned)
    total = sum(int(row["ridge_total"]) for row in assigned)
    identity = _git_identity_for_planning(args.code_root.resolve())
    launch_grade_git = bool(identity["clean"] and identity["head"] == identity["upstream_head"])
    if args.mode == "freeze" and not launch_grade_git:
        raise RuntimeError("freeze requires a clean branch synchronized with its upstream")
    checkpoint = {
        "schema_version": 1,
        "stage": "R97-distributed-continuation",
        "mode": args.mode,
        "status": "frozen_not_launched" if args.mode == "freeze" else "preview_not_launchable",
        "parent_campaign_contract": file_record(args.campaign_contract, "R97_parent_campaign_contract"),
        "parent_campaign_contract_sha256": parent["campaign_contract_sha256"],
        "campaign_root": str(args.campaign_root.resolve()),
        "regions": list(parent["regions_to_fit"]),
        "region_count": len(assigned),
        "ridge_experiments_complete": completed,
        "ridge_experiments_total": total,
        "fallback_cell_seconds": fallback,
        "original_controller_lock_available": lock_free,
        "code_git_identity": identity,
        "launch_grade_git_identity": launch_grade_git,
        "assignment_load_cpu_seconds": {key: round(value, 3) for key, value in loads.items()},
        "absolute_path_strategy": "same_paths_on_both_hosts",
        "assignment_mutable_until_freeze": args.mode != "freeze",
        "launch_authorized": False,
        "global_test_scoring_authorized": False,
        **firewall(),
    }
    checkpoint["checkpoint_sha256"] = canonical_sha256(checkpoint)

    files: dict[str, str] = {}
    if args.write:
        output = args.output_dir.resolve()
        if output.exists() and any(output.iterdir()) and not args.force:
            raise FileExistsError(output)
        output.mkdir(parents=True, exist_ok=True)
        assignment_path = output / "pricefm_stage_r97_host_assignment.csv"
        _write_csv(assignment_path, assigned)
        checkpoint_path = output / "pricefm_stage_r97_distributed_checkpoint.json"
        write_sealed(checkpoint_path, {key: value for key, value in checkpoint.items() if key != "checkpoint_sha256"}, "checkpoint_sha256")
        files = {"checkpoint": str(checkpoint_path), "assignment": str(assignment_path)}
        for host in ("muscat", "jerez"):
            regions = [row["region"] for row in assigned if row["assigned_host"] == host]
            contract = {
                "schema_version": 1,
                "stage": "R97-distributed-continuation",
                "mode": args.mode,
                "host": host,
                "regions": regions,
                "region_count": len(regions),
                "workers": args.muscat_workers if host == "muscat" else args.jerez_workers,
                "max_concurrent_models_per_region": 2,
                "one_model_process_per_cpu": True,
                "threads_per_model": 1,
                "campaign_root": str(args.campaign_root.resolve()),
                "parent_campaign_contract": file_record(args.campaign_contract, "R97_parent_campaign_contract"),
                "checkpoint": file_record(checkpoint_path, "distributed_checkpoint"),
                "assignment": file_record(assignment_path, "exclusive_region_assignment"),
                "code_git_identity": identity,
                "launch_authorized": False,
                "global_test_scoring_authorized": False,
                **firewall(),
            }
            path = output / f"pricefm_stage_r97_{host}_shard_contract.json"
            write_sealed(path, contract, "shard_contract_sha256")
            files[f"{host}_contract"] = str(path)
    return {
        "status": checkpoint["status"],
        "mode": args.mode,
        "regions": len(assigned),
        "ridge_experiments_complete": completed,
        "ridge_experiments_total": total,
        "controller_lock_available": lock_free,
        "launch_grade_git_identity": launch_grade_git,
        "assignment_counts": {
            host: sum(row["assigned_host"] == host for row in assigned)
            for host in ("muscat", "jerez")
        },
        "files": files,
        "launch_invoked": False,
        "test_opened": False,
    }


def main() -> int:
    result = build(parser().parse_args())
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
