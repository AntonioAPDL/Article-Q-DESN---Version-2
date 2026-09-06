#!/usr/bin/env python3
"""Build the hash-pinned PriceFM-local exdqlm 1.1.1 SPD repair runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
from typing import Any


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TARBALL = DATA / "runtime_sources/exdqlm_cran_1p1p1/exdqlm_1.1.1.tar.gz"
SOURCE_ROOT = DATA / "runtime_sources/exdqlm_pricefm_r72_spd_repair"
LIBRARY = DATA / "runtime_libraries/exdqlm_pricefm_r72_spd_repair"
PATCH = Path(__file__).with_name("pricefm_stage_r72_exdqlm_1p1p1_spd_repair.patch")
MANIFEST_NAME = "pricefm_stage_r72_spd_repair_manifest.json"
CRAN_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
VERSION = "1.1.1.9001"


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    lowered = value.strip().lower()
    if lowered in {"1", "true", "yes", "y"}:
        return True
    if lowered in {"0", "false", "no", "n"}:
        return False
    raise argparse.ArgumentTypeError(f"Not a Boolean: {value}")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tarball", type=Path, default=TARBALL)
    p.add_argument("--patch", type=Path, default=PATCH)
    p.add_argument("--source-root", type=Path, default=SOURCE_ROOT)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--install", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def safe_extract(archive: tarfile.TarFile, destination: Path) -> None:
    base = destination.resolve()
    for member in archive.getmembers():
        target = (destination / member.name).resolve()
        if base != target and base not in target.parents:
            raise RuntimeError(f"Unsafe archive member: {member.name}")
    archive.extractall(destination, filter="data")


def package_probe(library: Path) -> dict[str, Any]:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
desc <- utils::packageDescription("exdqlm", lib.loc = lib)
ns <- loadNamespace("exdqlm", lib.loc = lib)
helper <- get(".pricefm_safe_spd_chol", envir = ns, inherits = FALSE)
A <- matrix(c(2, 0.25, 0.25, 1), 2)
probe <- helper(A, context = "install_probe", iter = 1L)
cat(jsonlite::toJSON(list(
  version = as.character(desc$Version),
  repository = as.character(desc$Repository),
  repair = as.character(desc[["Config/PriceFM/repair"]]),
  base_sha256 = as.character(desc[["Config/PriceFM/base-tarball-sha256"]]),
  library = lib,
  direct_probe_path = as.character(probe$diagnostics$factorization_path[[1L]]),
  r_version = R.version.string
), auto_unbox = TRUE))
'''
    output = subprocess.check_output(["Rscript", "-e", code, str(library)], text=True)
    probe = json.loads(output)
    if probe.get("version") != VERSION or probe.get("repository") != "PriceFM-local":
        raise RuntimeError(f"Installed runtime is not the labeled PriceFM repair: {probe}")
    if probe.get("base_sha256") != CRAN_SHA256 or probe.get("direct_probe_path") != "direct":
        raise RuntimeError(f"Installed runtime provenance/probe failed: {probe}")
    return probe


def run(args: argparse.Namespace) -> dict[str, Any]:
    tarball = args.tarball.resolve()
    patch = args.patch.resolve()
    if sha256(tarball) != CRAN_SHA256:
        raise RuntimeError("Base tarball is not exact CRAN exdqlm 1.1.1")
    if not patch.is_file():
        raise FileNotFoundError(patch)
    source_root = args.source_root.resolve()
    source = source_root / "exdqlm"
    library = args.library.resolve()
    manifest_path = library / MANIFEST_NAME
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        current = json.loads(manifest_path.read_text())
        if current["base_tarball_sha256"] != CRAN_SHA256 or current["patch_sha256"] != sha256(patch):
            raise RuntimeError("Existing R72 runtime provenance conflicts with requested inputs")
        current["installed_package"] = package_probe(library)
        return current
    if (source_root.exists() or library.exists()) and not args.force:
        raise RuntimeError("R72 source/library exists without a reusable manifest; use --force true")
    if source_root.exists():
        shutil.rmtree(source_root)
    if library.exists():
        shutil.rmtree(library)
    source_root.mkdir(parents=True)
    with tarfile.open(tarball, "r:gz") as archive:
        safe_extract(archive, source_root)
    subprocess.run(
        ["patch", "--batch", "--forward", "-p1", "-i", str(patch)],
        cwd=source,
        check=True,
        text=True,
        capture_output=True,
    )
    description = (source / "DESCRIPTION").read_text()
    required_markers = (
        "Version: 1.1.1.9001", "Repository: PriceFM-local",
        "scale-aware-SPD-Cholesky-with-telemetry",
    )
    if any(marker not in description for marker in required_markers):
        raise RuntimeError("R72 patch did not produce the required honest package metadata")
    source_hashes = {
        str(path.relative_to(source)): sha256(path)
        for path in (
            source / "DESCRIPTION", source / "R/pricefm_spd_repair.R",
            source / "R/utils.R", source / "R/exalStaticLDVB.R",
        )
    }
    manifest: dict[str, Any] = {
        "status": "materialized_source_not_installed",
        "scientific_role": "pricefm_local_scale_aware_spd_repair_only",
        "source_label": "derived_from_exact_CRAN_exdqlm_1.1.1_not_CRAN",
        "base_tarball": str(tarball),
        "base_tarball_sha256": CRAN_SHA256,
        "patch": str(patch),
        "patch_sha256": sha256(patch),
        "patched_source": str(source),
        "patched_source_hashes": source_hashes,
        "library": str(library),
        "launch_authorized": False,
        "test_access_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    if args.install:
        library.mkdir(parents=True)
        install_log = library / "pricefm_stage_r72_spd_repair_install.log"
        with install_log.open("w") as log:
            subprocess.run(
                ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(source)],
                check=True,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )
        manifest["status"] = "installed_pricefm_local_spd_repair"
        manifest["install_log"] = str(install_log)
        manifest["install_log_sha256"] = sha256(install_log)
        manifest["installed_package"] = package_probe(library)
        write_json(manifest_path, manifest)
    else:
        source_manifest = source_root / MANIFEST_NAME
        write_json(source_manifest, manifest)
    return manifest


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
