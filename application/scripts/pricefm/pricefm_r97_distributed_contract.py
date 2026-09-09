#!/usr/bin/env python3
"""Shared contracts for the distributed R97 continuation."""

from __future__ import annotations

import csv
import fcntl
import json
import os
from pathlib import Path
import socket
from statistics import median
from typing import Any, Iterable, Mapping

from pricefm_region_frozen_contract import (
    atomic_write_json,
    canonical_sha256,
    sha256_file,
)


HOSTS = ("muscat", "jerez")
BLOCKED_ACTIONS = (
    "test_access_authorized",
    "registry_mutation_authorized",
    "article_mutation_authorized",
    "joint_model_authorized",
    "mcmc_authorized",
)


def sealed_payload(payload: Mapping[str, Any], hash_field: str) -> dict[str, Any]:
    result = dict(payload)
    result[hash_field] = canonical_sha256(result)
    return result


def verify_seal(payload: Mapping[str, Any], hash_field: str, *, label: str) -> None:
    expected = str(payload.get(hash_field, ""))
    unhashed = {key: value for key, value in payload.items() if key != hash_field}
    if not expected or canonical_sha256(unhashed) != expected:
        raise RuntimeError(f"{label} canonical hash changed")


def firewall() -> dict[str, bool]:
    return {"test_opened": False, **{name: False for name in BLOCKED_ACTIONS}}


def validate_firewall(payload: Mapping[str, Any], *, label: str) -> None:
    expected = firewall()
    changed = [key for key, value in expected.items() if payload.get(key) is not value]
    if changed:
        raise RuntimeError(f"{label} violates the R97 distributed firewall: {changed}")


def controller_lock_available(campaign_root: str | Path) -> bool:
    """Return true only when no process owns the original R97 controller lock."""
    path = Path(campaign_root) / "controller.lock"
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+")
    try:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        return True
    finally:
        handle.close()


def valid_compaction_marker(path: str | Path) -> bool:
    path = Path(path)
    if not path.is_file():
        return False
    try:
        payload = json.loads(path.read_text())
        if payload.get("status") != "completed_compacted":
            return False
        retained = payload.get("retained") or []
        return bool(retained) and all(
            Path(record["path"]).is_file()
            and sha256_file(record["path"]) == str(record["sha256"])
            for record in retained
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def valid_surface_terminal(path: str | Path) -> bool:
    path = Path(path)
    if not path.is_file():
        return False
    try:
        payload = json.loads(path.read_text())
        if payload.get("status") not in {"completed", "completed_numerically_ineligible"}:
            return False
        if payload.get("test_opened") is not False or payload.get("test_access_authorized") is not False:
            return False
        return all(
            Path(record["path"]).is_file()
            and sha256_file(record["path"]) == str(record["sha256"])
            for record in payload.get("artifacts") or []
        )
    except (OSError, KeyError, json.JSONDecodeError):
        return False


def manifest_progress(path: str | Path) -> tuple[int, int]:
    path = Path(path)
    if not path.is_file():
        return 0, 0
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    complete = sum(
        valid_compaction_marker(Path(row["run_dir"]) / "r97_compaction_terminal.json")
        for row in rows
    )
    return complete, len(rows)


def _surface_progress(region_root: Path) -> tuple[int, int]:
    manifest = region_root / "surface_grid/task_manifest.csv"
    if not manifest.is_file():
        return 0, 45
    with manifest.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    complete = sum(valid_surface_terminal(Path(row["output_dir"]) / "terminal.json") for row in rows)
    return complete, len(rows)


def _elapsed_samples(region_root: Path) -> list[float]:
    samples: list[float] = []
    for path in region_root.glob("**/cell_status.json"):
        try:
            payload = json.loads(path.read_text())
            value = payload.get("elapsed_seconds")
            if value is not None and float(value) > 0:
                samples.append(float(value))
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            continue
    return samples


def scan_region(campaign_root: str | Path, region: str) -> dict[str, Any]:
    root = Path(campaign_root) / "regions" / region
    ridge_complete, ridge_total = manifest_progress(root / "ridge_generated/manifest.csv")
    rhs_complete, rhs_total = manifest_progress(root / "rhs_generated/manifest.csv")
    refine_complete, refine_total = manifest_progress(root / "refine_generated/manifest.csv")
    surface_complete, surface_total = _surface_progress(root)
    closeout = Path(campaign_root) / "region_closeouts" / region / "summary.json"
    elapsed = _elapsed_samples(root)
    return {
        "region": region,
        "region_root": str(root.resolve()),
        "ridge_complete": ridge_complete,
        "ridge_total": ridge_total or 240,
        "rhs_complete": rhs_complete,
        "rhs_total": rhs_total or 90,
        "refinement_complete": refine_complete,
        "refinement_total": refine_total,
        "surface_complete": surface_complete,
        "surface_total": surface_total,
        "region_closeout_complete": closeout.is_file(),
        "elapsed_sample_count": len(elapsed),
        "median_cell_seconds": median(elapsed) if elapsed else None,
    }


def estimate_remaining(rows: Iterable[Mapping[str, Any]], fallback_cell_seconds: float) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for source in rows:
        row = dict(source)
        seconds = float(row.get("median_cell_seconds") or fallback_cell_seconds)
        if row.get("region_closeout_complete"):
            cells = 0
        else:
            cells = (
                max(0, int(row["ridge_total"]) - int(row["ridge_complete"])) * 3
                + max(0, int(row["rhs_total"]) - int(row["rhs_complete"])) * 3
                + max(0, int(row["refinement_total"]) - int(row["refinement_complete"])) * 3
                + max(0, int(row["surface_total"]) - int(row["surface_complete"]))
            )
        row["estimated_remaining_cells"] = cells
        row["estimated_remaining_cpu_seconds"] = round(cells * seconds, 3)
        result.append(row)
    return result


def assign_regions(
    rows: Iterable[Mapping[str, Any]],
    *,
    jerez_region_count: int = 25,
    workers: Mapping[str, int] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, float]]:
    """Assign whole regions, balancing estimated CPU time per host worker."""
    capacities = dict(workers or {"muscat": 20, "jerez": 50})
    values = [dict(row) for row in rows]
    if not 0 <= jerez_region_count <= len(values):
        raise ValueError("invalid Jerez region quota")
    quotas = {"jerez": jerez_region_count, "muscat": len(values) - jerez_region_count}
    loads = {host: 0.0 for host in HOSTS}
    counts = {host: 0 for host in HOSTS}
    assigned: list[dict[str, Any]] = []
    for row in sorted(values, key=lambda item: (-float(item["estimated_remaining_cpu_seconds"]), str(item["region"]))):
        candidates = [host for host in HOSTS if counts[host] < quotas[host]]
        host = min(
            candidates,
            key=lambda name: (
                (loads[name] + float(row["estimated_remaining_cpu_seconds"])) / capacities[name],
                name,
            ),
        )
        row["assigned_host"] = host
        row["host_workers"] = capacities[host]
        row["max_concurrent_models_per_region"] = 2
        assigned.append(row)
        counts[host] += 1
        loads[host] += float(row["estimated_remaining_cpu_seconds"])
    if counts != quotas:
        raise RuntimeError(f"region assignment quota failed: {counts} != {quotas}")
    return sorted(assigned, key=lambda item: str(item["region"])), loads


def relative_to_root(path: str | Path, root: str | Path) -> str:
    resolved, resolved_root = Path(path).resolve(), Path(root).resolve()
    try:
        return str(resolved.relative_to(resolved_root))
    except ValueError as error:
        raise RuntimeError(f"artifact escapes the declared root: {resolved}") from error


def host_identity() -> dict[str, Any]:
    return {
        "hostname": socket.gethostname(),
        "logical_cpus": os.cpu_count(),
    }


def write_sealed(path: str | Path, payload: Mapping[str, Any], hash_field: str) -> dict[str, Any]:
    result = sealed_payload(payload, hash_field)
    atomic_write_json(path, result)
    return result
