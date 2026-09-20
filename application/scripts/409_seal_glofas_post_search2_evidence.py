#!/usr/bin/env python3.11
"""Seal completed GloFAS r8 and Part 4 evidence without modifying either runtime."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_value(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def status_counts(root: Path) -> dict[str, int]:
    status = root / "status"
    return {
        suffix: len(list(status.glob(f"*.{suffix}")))
        for suffix in ("completed", "failed", "running", "pending")
    }


def files_for(root: Path) -> list[Path]:
    allowed = {
        "configs", "docs", "figures", "forecasts", "inputs", "logs", "manifests",
        "objects", "predictions", "scores", "scripts", "status", "tables", "traces",
        "coefficients",
    }
    return sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.relative_to(root).parts[0] in allowed
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--r8-root", required=True)
    parser.add_argument("--part4-root", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[2]
    r8 = (repo / args.r8_root).resolve() if not Path(args.r8_root).is_absolute() else Path(args.r8_root).resolve()
    part4 = (repo / args.part4_root).resolve() if not Path(args.part4_root).is_absolute() else Path(args.part4_root).resolve()
    output = (repo / args.output_root).resolve() if not Path(args.output_root).is_absolute() else Path(args.output_root).resolve()
    output.mkdir(parents=True, exist_ok=True)

    expected = {"r8": 133, "part4": 18}
    counts = {"r8": status_counts(r8), "part4": status_counts(part4)}
    for lane, total in expected.items():
        observed = counts[lane]
        if observed["completed"] != total or any(observed[key] for key in ("failed", "running", "pending")):
            raise SystemExit(f"Cannot seal {lane}: {observed}, expected {total} clean completions")

    rows: list[dict[str, object]] = []
    for lane, root in (("r8", r8), ("part4", part4)):
        for path in files_for(root):
            stat = path.stat()
            rows.append({
                "lane": lane,
                "relative_path": path.relative_to(root).as_posix(),
                "bytes": stat.st_size,
                "sha256": sha256(path),
            })

    manifest = output / "glofas_post_search2_evidence_manifest.csv"
    with manifest.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["lane", "relative_path", "bytes", "sha256"])
        writer.writeheader()
        writer.writerows(rows)

    metadata = {
        "schema_version": "glofas_post_search2_evidence_seal_v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": socket.getfqdn(),
        "repo": str(repo),
        "git_head": git_value(repo, "rev-parse", "HEAD"),
        "git_branch": git_value(repo, "branch", "--show-current"),
        "git_status_at_seal": git_value(repo, "status", "--short"),
        "r8_root": str(r8),
        "part4_root": str(part4),
        "health": counts,
        "manifest_rows": len(rows),
        "manifest_bytes": sum(int(row["bytes"]) for row in rows),
        "manifest_sha256": sha256(manifest),
        "classification": {
            "r8": "completed_pre_correction_evidence_preserved_read_only",
            "part4": "completed_pre_continuation_evidence_preserved_read_only",
        },
    }
    metadata_path = output / "glofas_post_search2_evidence_seal.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    print(json.dumps(metadata, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
