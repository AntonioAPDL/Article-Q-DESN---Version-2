#!/usr/bin/env python3
"""Install the immutable corrected exdqlm source for PriceFM Stage-R66."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from pricefm_common import parse_bool, write_json


PACKAGE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r66_ab5741c")
LIBRARY = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/"
    "runtime_libraries/exdqlm_ab5741c"
)
COMMIT = "ab5741ceb854db9a53889a17c91d2d30f4d8c41d"
HASHES = {
    "R/exal_ldvb_engine.R": "d82d1be56a156c32eb681f5464ac00ea8765992034c84824c0c98066d09912e3",
    "R/exal_inference_config.R": "18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044",
    "R/exal_sigmagam_structured.R": "c039125ab261c950ea464cc886f48257558b273df1e400aa407f72ff36e5d762",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--package-path", type=Path, default=PACKAGE)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def run(args: argparse.Namespace) -> dict:
    package = args.package_path.resolve()
    library = args.library.resolve()
    head = subprocess.check_output(
        ["git", "-C", str(package), "rev-parse", "HEAD"], text=True
    ).strip()
    observed = {name: sha256(package / name) for name in HASHES}
    if head != COMMIT or observed != HASHES:
        raise RuntimeError("R66 package source does not match the immutable correction contract")
    if subprocess.check_output(
        ["git", "-C", str(package), "status", "--porcelain"], text=True
    ).strip():
        raise RuntimeError("R66 package checkout is dirty")
    manifest_path = library / "pricefm_r66_install_manifest.json"
    expected = {
        "status": "installed_immutable_pricefm_r66_package",
        "source_path": str(package),
        "source_commit": COMMIT,
        "source_sha256": HASHES,
        "library": str(library),
        "package": "exdqlm",
        "package_version": "1.1.1",
        "scientific_change": "structured_exal_continuation_and_exact_conditional_gig_moments",
    }
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        current = json.loads(manifest_path.read_text())
        if current == expected:
            return current
        raise RuntimeError("Existing R66 package library conflicts with the pinned manifest")
    library.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(package)],
        check=True,
    )
    if not (library / "exdqlm").is_dir():
        raise RuntimeError("R66 package installation did not materialize exdqlm")
    write_json(manifest_path, expected)
    return expected


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
