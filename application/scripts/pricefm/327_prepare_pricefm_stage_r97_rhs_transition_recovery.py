#!/usr/bin/env python3
"""Prepare sealed R97 RHS-transition recovery artifacts without fitting models."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
from typing import Any

import pandas as pd

from pricefm_r97_distributed_contract import (
    firewall,
    validate_firewall,
    verify_seal,
    write_sealed,
)
from pricefm_region_frozen_contract import (
    atomic_write_json,
    file_record,
    git_identity,
    sha256_file,
    verify_file_record,
)


LEGACY_GRID_NAME = "pricefm_stage_r93_ridge_grid.yaml"
R97_GRID_NAME = "ridge_grid.yaml"


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    sub = value.add_subparsers(dest="command", required=True)

    rebind = sub.add_parser("rebind-contract")
    rebind.add_argument("--source-contract", type=Path, required=True)
    rebind.add_argument("--code-root", type=Path, required=True)
    rebind.add_argument("--output", type=Path, required=True)
    rebind.add_argument("--host", choices=("muscat", "jerez"), required=True)
    rebind.add_argument(
        "--reason",
        default="explicit R97 ridge_grid.yaml to R93 Ridge-to-RHS path repair",
    )
    rebind.add_argument("--force", action="store_true")

    aliases = sub.add_parser("install-grid-aliases")
    aliases.add_argument("--shard-contract", type=Path, required=True)
    aliases.add_argument("--campaign-root", type=Path, required=True)
    aliases.add_argument("--host", choices=("muscat", "jerez"), required=True)
    aliases.add_argument("--output", type=Path)
    aliases.add_argument("--write", action="store_true")
    return value


def load_contract(path: Path, host: str) -> dict[str, Any]:
    payload = json.loads(path.read_text())
    verify_seal(payload, "shard_contract_sha256", label="R97 recovery source contract")
    validate_firewall(payload, label="R97 recovery source contract")
    if payload.get("mode") != "freeze" or payload.get("host") != host:
        raise RuntimeError("R97 recovery requires the matching frozen host contract")
    for name in ("parent_campaign_contract", "checkpoint", "assignment"):
        verify_file_record(payload[name], label=f"R97 recovery {name}")
    assignment = pd.read_csv(payload["assignment"]["path"])
    owned = assignment.loc[
        assignment.assigned_host.astype(str).eq(host), "region"
    ].astype(str).tolist()
    if owned != list(payload["regions"]):
        raise RuntimeError("R97 recovery ownership differs from the sealed assignment")
    return payload


def rebind_contract(args: argparse.Namespace) -> dict[str, Any]:
    source_path = args.source_contract.resolve()
    source = load_contract(source_path, args.host)
    output = args.output.resolve()
    if output.exists() and not args.force:
        raise FileExistsError(output)

    identity = git_identity(args.code_root.resolve())
    if not identity.clean or identity.head != identity.upstream_head:
        raise RuntimeError("R97 recovery code must be clean and synchronized with upstream")
    old_head = str(source["code_git_identity"]["head"])
    ancestor = subprocess.run(
        ["git", "merge-base", "--is-ancestor", old_head, identity.head],
        cwd=args.code_root.resolve(), check=False,
    )
    if ancestor.returncode != 0:
        raise RuntimeError("R97 recovery commit is not a descendant of the frozen shard code")

    payload = {key: value for key, value in source.items() if key != "shard_contract_sha256"}
    payload["code_git_identity"] = identity.to_dict()
    payload["transition_recovery"] = {
        "reason": str(args.reason),
        "source_contract": file_record(source_path, "original_frozen_shard_contract"),
        "source_code_git_identity": source["code_git_identity"],
        "scientific_contract_changed": False,
        "checkpoint_changed": False,
        "assignment_changed": False,
        "region_ownership_changed": False,
        "completed_ridge_refit_authorized": False,
        "completed_rhs_refit_authorized": False,
        "completed_screening_refit_authorized": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    return write_sealed(output, payload, "shard_contract_sha256")


def install_aliases(args: argparse.Namespace) -> dict[str, Any]:
    contract_path = args.shard_contract.resolve()
    contract = load_contract(contract_path, args.host)
    campaign_root = args.campaign_root.resolve()
    if Path(contract["campaign_root"]).resolve() != campaign_root:
        raise RuntimeError("R97 recovery campaign root differs from the shard contract")
    if not socket.gethostname().lower().startswith(args.host.lower()):
        raise RuntimeError(f"R97 {args.host} aliases cannot be installed on {socket.gethostname()}")

    records = []
    for region in contract["regions"]:
        prep = campaign_root / "regions" / region / "ridge_prep"
        target = prep / R97_GRID_NAME
        alias = prep / LEGACY_GRID_NAME
        if not target.is_file() or target.stat().st_size == 0:
            raise RuntimeError(f"R97 Ridge grid is missing or empty for {region}: {target}")
        target_hash = sha256_file(target)
        existed = os.path.lexists(alias)
        if existed:
            if not alias.is_symlink() or os.readlink(alias) != R97_GRID_NAME:
                raise RuntimeError(f"R97 legacy grid path is not the expected relative alias: {alias}")
        elif args.write:
            alias.symlink_to(R97_GRID_NAME)
        if args.write and (
            not alias.is_file()
            or alias.resolve() != target.resolve()
            or sha256_file(alias) != target_hash
        ):
            raise RuntimeError(f"R97 grid alias verification failed for {region}")
        records.append({
            "region": region,
            "target": str(target),
            "alias": str(alias),
            "target_sha256": target_hash,
            "bytes": target.stat().st_size,
            "previously_present": existed,
            "installed": bool(args.write),
            "verified": bool(args.write),
        })

    result = {
        "schema_version": 1,
        "stage": "R97-rhs-transition-recovery",
        "status": "aliases_installed_and_verified" if args.write else "preview_only",
        "host": args.host,
        "region_count": len(records),
        "source_contract": file_record(contract_path, "frozen_shard_contract"),
        "aliases": records,
        "model_fitting_invoked": False,
        "completed_ridge_refit_authorized": False,
        **firewall(),
    }
    if args.write:
        output = args.output or (
            campaign_root / "distributed" / args.host / "rhs_transition_compatibility.json"
        )
        atomic_write_json(output, result)
    return result


def main() -> int:
    args = parser().parse_args()
    result = rebind_contract(args) if args.command == "rebind-contract" else install_aliases(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
