#!/usr/bin/env python3
"""Install the immutable R65 exdqlm source into a dedicated runtime library."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from pricefm_common import parse_bool, write_json


PACKAGE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r65_cc85a75")
LIBRARY = Path(
    "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_cc85a75"
)
COMMIT = "cc85a75ceca51c6e6a699147c45742591c7e3679"
HASHES = {
    "R/exal_ldvb_engine.R": "c55e3cb960f8d1d695e4340c496334b4acbf73500399872b0d5a09896493add5",
    "R/exal_inference_config.R": "18f6a140e0dc4e33702528b21db8bf3b264b743fc745f2daf0b276143fb11044",
    "R/exal_sigmagam_structured.R": "4bc6e0d11736ec5e7ef73a267c84aedf7b1de36ad218f81859e0060ec552052f",
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
    head = subprocess.check_output(["git", "-C", str(package), "rev-parse", "HEAD"], text=True).strip()
    observed = {name: sha256(package / name) for name in HASHES}
    if head != COMMIT or observed != HASHES:
        raise RuntimeError("R65 package source does not match the immutable inference contract")
    manifest_path = library / "pricefm_r65_install_manifest.json"
    expected = {
        "status": "installed_immutable_pricefm_r65_package",
        "source_path": str(package),
        "source_commit": COMMIT,
        "source_sha256": HASHES,
        "library": str(library),
        "package": "exdqlm",
        "package_version": "1.1.1",
    }
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        current = json.loads(manifest_path.read_text())
        if current == expected:
            return current
        raise RuntimeError("Existing R65 package library has a conflicting install manifest")
    library.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(package)],
        check=True,
    )
    if not (library / "exdqlm").is_dir():
        raise RuntimeError("R65 package installation did not materialize exdqlm")
    write_json(manifest_path, expected)
    return expected


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
