#!/usr/bin/env python3
"""Create or verify a hash manifest for an R97 host-shard transfer."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Any, Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pricefm_r97_distributed_contract import (
    firewall,
    relative_to_root,
    verify_seal,
    write_sealed,
)
from pricefm_region_frozen_contract import atomic_write_json, sha256_file, verify_file_record


BASE_ROOT = Path("/data/jaguir26/local")
ARTIFACT_ROOT = BASE_ROOT / "src/Article-Q-DESN"
DATA_ROOT = ARTIFACT_ROOT / "application/data_local/pricefm"
TAG = "pricefm_stage_r97_global_region_frozen_campaign_20260908"
CAMPAIGN_ROOT = DATA_ROOT / "campaigns" / TAG
PREP_ROOT = DATA_ROOT / "authoritative" / f"{TAG}_prep"
RUNTIME_SOURCE = DATA_ROOT / "runtime_sources/exdqlm_pricefm_r93_normal_exact_names"
RUNTIME_LIBRARY = DATA_ROOT / "runtime_libraries/exdqlm_pricefm_r94_coherent_exal_init"
APPROVED_EXTERNAL_SYMLINKS = {
    "/usr/bin/python3.11": "695bf83254bba94ab3b2a9d00c94b9316e483965b006936b076916f0a85a9ae5",
}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    sub = value.add_subparsers(dest="command", required=True)
    inventory = sub.add_parser("inventory")
    inventory.add_argument("--shard-contract", type=Path, required=True)
    inventory.add_argument("--base-root", type=Path, default=BASE_ROOT)
    inventory.add_argument("--campaign-root", type=Path, default=CAMPAIGN_ROOT)
    inventory.add_argument("--output-dir", type=Path, required=True)
    inventory.add_argument("--scope", choices=("common", "host", "all"), default="all")
    inventory.add_argument("--force", action="store_true")
    verify = sub.add_parser("verify")
    verify.add_argument("--inventory", type=Path, required=True)
    verify.add_argument("--target-base-root", type=Path, default=BASE_ROOT)
    verify.add_argument("--output", type=Path)
    return value


def transfer_roots(contract: dict[str, Any], campaign_root: Path, scope: str) -> list[tuple[Path, str]]:
    common = [
        (PREP_ROOT, "parent_campaign_prep"),
        (campaign_root / "inner_preprocessing", "shared_inner_preprocessing"),
        (campaign_root / "processed_inner", "shared_processed_inner"),
        (DATA_ROOT / "raw", "PriceFM_raw_input"),
        (DATA_ROOT / "interim", "PriceFM_interim_input"),
        (DATA_ROOT / "venv", "pinned_PriceFM_python_environment"),
        (RUNTIME_SOURCE, "normal_runtime_source"),
        (RUNTIME_LIBRARY, "coherent_exAL_runtime_library"),
        (Path(contract["parent_campaign_contract"]["path"]), "parent_campaign_contract"),
        (Path(contract["checkpoint"]["path"]).parent, "distributed_contracts"),
    ]
    parent = json.loads(Path(contract["parent_campaign_contract"]["path"]).read_text())
    common.extend(
        (Path(parent[name]["path"]), f"parent_{name}")
        for name in ("authority_registry", "resolved_controls", "se2_reuse", "source_data_config")
    )
    host = [
        (campaign_root / "regions" / region, f"owned_region_{region}")
        for region in contract["regions"]
    ]
    if scope == "common":
        return common
    if scope == "host":
        return host
    return common + host


def iter_entries(root: Path) -> Iterable[Path]:
    if root.is_symlink() or root.is_file():
        yield root
        return
    if not root.is_dir():
        raise FileNotFoundError(root)
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or path.is_file():
            yield path


def record(path: Path, base_root: Path, role: str) -> dict[str, Any]:
    if path.is_symlink():
        try:
            relative = str(path.absolute().relative_to(base_root.resolve()))
        except ValueError as error:
            raise RuntimeError(f"artifact link escapes the declared root: {path.absolute()}") from error
        target = os.readlink(path)
        resolved = path.resolve()
        external_sha256 = None
        try:
            relative_to_root(resolved, base_root)
        except RuntimeError:
            expected = APPROVED_EXTERNAL_SYMLINKS.get(str(resolved))
            if not expected or not resolved.is_file() or sha256_file(resolved) != expected:
                raise
            external_sha256 = expected
        result = {
            "relative_path": relative,
            "role": role,
            "type": "symlink",
            "symlink_target": target,
            "resolved_target": str(resolved),
        }
        if external_sha256:
            result["external_target_sha256"] = external_sha256
        return result
    relative = relative_to_root(path, base_root)
    return {
        "relative_path": relative,
        "role": role,
        "type": "file",
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def inventory(args: argparse.Namespace) -> dict[str, Any]:
    contract = json.loads(args.shard_contract.read_text())
    verify_seal(contract, "shard_contract_sha256", label="R97 host shard contract")
    for name in ("parent_campaign_contract", "checkpoint", "assignment"):
        verify_file_record(contract[name], label=f"R97 shard {name}")
    entries: dict[str, dict[str, Any]] = {}
    for root, role in transfer_roots(contract, args.campaign_root.resolve(), args.scope):
        for path in iter_entries(root):
            item = record(path, args.base_root.resolve(), role)
            entries.setdefault(item["relative_path"], item)
    rows = [entries[key] for key in sorted(entries)]
    output = args.output_dir.resolve()
    if output.exists() and any(output.iterdir()) and not args.force:
        raise FileExistsError(output)
    output.mkdir(parents=True, exist_ok=True)
    files_from = output / f"pricefm_stage_r97_{contract['host']}_{args.scope}_rsync_files.txt"
    files_from.write_text("".join(f"{row['relative_path']}\n" for row in rows))
    payload = {
        "schema_version": 1,
        "stage": "R97-distributed-continuation",
        "status": "transfer_inventory_complete_not_transferred",
        "host": contract["host"],
        "scope": args.scope,
        "base_root": str(args.base_root.resolve()),
        "shard_contract": {
            "path": str(args.shard_contract.resolve()),
            "sha256": sha256_file(args.shard_contract),
        },
        "entry_count": len(rows),
        "file_count": sum(row["type"] == "file" for row in rows),
        "symlink_count": sum(row["type"] == "symlink" for row in rows),
        "total_file_bytes": sum(int(row.get("bytes", 0)) for row in rows),
        "entries": rows,
        "rsync_files_from": str(files_from),
        "transfer_invoked": False,
        "launch_invoked": False,
        **firewall(),
    }
    manifest = output / f"pricefm_stage_r97_{contract['host']}_{args.scope}_transfer_inventory.json"
    result = write_sealed(manifest, payload, "transfer_inventory_sha256")
    return {
        "status": result["status"],
        "manifest": str(manifest),
        "files_from": str(files_from),
        "entry_count": result["entry_count"],
        "total_file_bytes": result["total_file_bytes"],
        "transfer_invoked": False,
    }


def verify(args: argparse.Namespace) -> dict[str, Any]:
    payload = json.loads(args.inventory.read_text())
    verify_seal(payload, "transfer_inventory_sha256", label="R97 transfer inventory")
    root = args.target_base_root.resolve()
    failures: list[dict[str, str]] = []
    for item in payload["entries"]:
        path = root / item["relative_path"]
        if item["type"] == "symlink":
            if not path.is_symlink() or os.readlink(path) != item["symlink_target"]:
                failures.append({"relative_path": item["relative_path"], "reason": "symlink_mismatch"})
            elif item.get("external_target_sha256") and (
                not path.resolve().is_file()
                or sha256_file(path.resolve()) != item["external_target_sha256"]
            ):
                failures.append({"relative_path": item["relative_path"], "reason": "external_symlink_target_hash_mismatch"})
        elif not path.is_file():
            failures.append({"relative_path": item["relative_path"], "reason": "missing"})
        elif path.stat().st_size != int(item["bytes"]):
            failures.append({"relative_path": item["relative_path"], "reason": "size_mismatch"})
        elif sha256_file(path) != item["sha256"]:
            failures.append({"relative_path": item["relative_path"], "reason": "sha256_mismatch"})
    result = {
        "schema_version": 1,
        "stage": "R97-distributed-continuation",
        "status": "verified" if not failures else "verification_failed",
        "host": payload["host"],
        "scope": payload["scope"],
        "target_base_root": str(root),
        "entry_count": len(payload["entries"]),
        "failure_count": len(failures),
        "failures": failures,
        "launch_invoked": False,
        **firewall(),
    }
    if args.output:
        atomic_write_json(args.output, result)
    return result


def main() -> int:
    args = parser().parse_args()
    result = inventory(args) if args.command == "inventory" else verify(args)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] != "verification_failed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
