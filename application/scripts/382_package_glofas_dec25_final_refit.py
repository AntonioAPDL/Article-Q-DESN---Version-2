#!/usr/bin/env python3
"""Package Dec25 final-refit GloFAS artifacts for Muscat import."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import tarfile
from datetime import datetime, timezone
from pathlib import Path


COMPACT_DIRS = {"configs", "contracts", "tables", "scores", "traces", "coefficients", "forecasts", "logs", "status", "figures", "docs", "manifests"}
HEAVY_DIRS = COMPACT_DIRS | {"objects"}
DESIGN_CACHE_SUFFIX = "_final_dec25_design_cache.rds"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(path: str) -> Path:
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or list(rows[0])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})


def role_for(path: Path, runtime: Path) -> str:
    parts = path.relative_to(runtime).parts
    if not parts:
        return "."
    if parts[0] == "objects":
        return "fit_object"
    return parts[0]


def include_file(path: Path, runtime: Path, part: str, kind: str, include_design_cache: bool) -> bool:
    rel_parts = path.relative_to(runtime).parts
    if not rel_parts:
        return False
    if path.name.endswith("_handoff_file_manifest.csv"):
        return False
    top = rel_parts[0]
    if top == "objects" and kind == "compact":
        return path.name.endswith("_compact.rds")
    if kind == "compact" and top not in COMPACT_DIRS:
        return False
    if kind == "heavy" and top not in HEAVY_DIRS:
        return False
    if path.name.endswith(DESIGN_CACHE_SUFFIX) and not include_design_cache:
        return False
    name = path.name
    path_text = "/".join(rel_parts)
    if part in {"part2", "part3"}:
        if name.startswith(part) or f"/{part}" in path_text or top in {"configs", "docs", "manifests", "status", "logs", "tables"}:
            return True
        return False
    return True


def make_manifest(runtime: Path, part: str, kind: str, include_design_cache: bool) -> list[dict]:
    rows = []
    for path in sorted(p for p in runtime.rglob("*") if p.is_file()):
        if not include_file(path, runtime, part, kind, include_design_cache):
            continue
        rel_path = rel(path, runtime)
        rows.append({
            "relative_path": rel_path,
            "repo_relative_path": rel(path, repo_root()),
            "role": role_for(path, runtime),
            "package_kind": kind,
            "part": part,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return rows


VERIFY_PY = """#!/usr/bin/env python3
import csv
import hashlib
import sys
from pathlib import Path


def sha256_file(path):
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
manifest = root / "handoff_file_manifest.csv"
if not manifest.exists():
    raise SystemExit(f"missing manifest: {manifest}")
with manifest.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
missing = []
mismatch = []
for row in rows:
    path = root / row["relative_path"]
    if not path.exists():
        missing.append(row["relative_path"])
        continue
    observed = sha256_file(path)
    if observed.lower() != row["sha256"].lower():
        mismatch.append((row["relative_path"], row["sha256"], observed))
if missing or mismatch:
    print({"missing": missing, "mismatch": mismatch})
    raise SystemExit(1)
print(f"verified_files={len(rows)}")
"""

VERIFY_R = """#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
manifest <- file.path(root, "handoff_file_manifest.csv")
if (!file.exists(manifest)) stop(sprintf("missing manifest: %s", manifest), call. = FALSE)
x <- read.csv(manifest, stringsAsFactors = FALSE, check.names = FALSE)
if (!nrow(x)) stop("empty handoff manifest", call. = FALSE)
paths <- file.path(root, x$relative_path)
if (any(!file.exists(paths))) stop("handoff package has missing files", call. = FALSE)
cat(sprintf("verified_rows=%d\\n", nrow(x)))
"""


def write_verify_scripts(root: Path) -> None:
    (root / "verify_handoff_package.py").write_text(VERIFY_PY, encoding="utf-8")
    (root / "verify_handoff_package.py").chmod(0o755)
    (root / "verify_handoff_package.R").write_text(VERIFY_R, encoding="utf-8")
    (root / "verify_handoff_package.R").chmod(0o755)


def materialize_package(runtime: Path, output_dir: Path, part: str, kind: str, rows: list[dict]) -> tuple[Path, str]:
    package_id = f"glofas_{part}_final_dec25_2022_{kind}_handoff_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    staging = output_dir / package_id
    staging.mkdir(parents=True, exist_ok=False)
    write_verify_scripts(staging)
    write_csv(staging / "handoff_file_manifest.csv", rows)
    metadata = {
        "schema_version": "glofas_final_dec25_2022_handoff_package_v1",
        "part": part,
        "package_kind": kind,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "runtime_root": rel(runtime, repo_root()),
        "member_count": len(rows),
        "design_cache_policy": "excluded_unless_explicitly_requested",
    }
    (staging / "handoff_package_metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for row in rows:
        src = runtime / row["relative_path"]
        dst = staging / row["relative_path"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            shutil.copy2(src, dst)
    archive = output_dir / f"{package_id}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(staging, arcname=package_id)
    digest = sha256_file(archive)
    (output_dir / f"{archive.name}.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    return archive, digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--part", choices=("part2", "part3", "all"), required=True)
    parser.add_argument("--package-kind", choices=("compact", "heavy"), required=True)
    parser.add_argument("--output-dir", default="local_trackers/muscat_handoffs")
    parser.add_argument("--include-design-cache", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    runtime = resolve(args.runtime_root)
    output_dir = resolve(args.output_dir)
    if not runtime.exists():
        raise SystemExit(f"missing runtime root: {runtime}")
    rows = make_manifest(runtime, args.part, args.package_kind, args.include_design_cache)
    dry_path = runtime / "manifests" / f"{args.part}_{args.package_kind}_handoff_file_manifest.csv"
    if not rows:
        raise SystemExit("No files matched the requested package.")
    write_csv(dry_path, rows)
    if args.dry_run:
        print(f"dry_run_manifest={rel(dry_path, repo_root())}")
        print(f"member_count={len(rows)}")
        return 0
    output_dir.mkdir(parents=True, exist_ok=True)
    archive, digest = materialize_package(runtime, output_dir, args.part, args.package_kind, rows)
    print(f"archive={rel(archive, repo_root())}")
    print(f"archive_sha256={digest}")
    print(f"member_count={len(rows)}")
    print("verify=extract archive and run python3 verify_handoff_package.py <extracted_package_dir>")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
