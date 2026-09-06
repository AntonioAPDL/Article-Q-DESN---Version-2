#!/usr/bin/env python3
"""Materialize the exact CRAN exdqlm 1.1.1 source in an isolated library."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
SOURCE_DIR = DATA / "runtime_sources/exdqlm_cran_1p1p1"
TARBALL = SOURCE_DIR / "exdqlm_1.1.1.tar.gz"
LIBRARY = DATA / "runtime_libraries/exdqlm_cran_1p1p1"
MANIFEST = LIBRARY / "pricefm_r67_cran111_install_manifest.json"
CRAN_URL = "https://cran.r-project.org/src/contrib/exdqlm_1.1.1.tar.gz"
CRAN_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
REQUIRED_EXPORTS = (
    "exalStaticLDVB",
    "exal_make_vb_control",
    "exal_make_vb_sigmagam_control",
)
FORK_ONLY_EXPORTS = (
    "beta_prior",
    "exal_ldvb_fit",
    "normal_desn_fit",
    "qdesn_fit_vb",
)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tarball", type=Path, default=TARBALL)
    p.add_argument("--library", type=Path, default=LIBRARY)
    p.add_argument("--source-url", default=CRAN_URL)
    p.add_argument("--download-if-missing", type=parse_bool, default=True)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_name(destination.name + ".download.tmp")
    if tmp.exists():
        tmp.unlink()
    try:
        with urllib.request.urlopen(url) as response, tmp.open("wb") as handle:
            shutil.copyfileobj(response, handle)
        tmp.replace(destination)
    finally:
        if tmp.exists():
            tmp.unlink()


def parse_dcf(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    key: str | None = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[:1].isspace() and key is not None:
            fields[key] = fields[key] + " " + line.strip()
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        fields[key] = value.strip()
    return fields


def tarball_description(path: Path) -> dict[str, str]:
    with tarfile.open(path, "r:gz") as archive:
        members = [member for member in archive.getmembers() if member.name == "exdqlm/DESCRIPTION"]
        if len(members) != 1:
            raise RuntimeError("CRAN tarball must contain exactly exdqlm/DESCRIPTION")
        handle = archive.extractfile(members[0])
        if handle is None:
            raise RuntimeError("Could not read exdqlm/DESCRIPTION from CRAN tarball")
        return parse_dcf(handle.read().decode("utf-8"))


def verify_tarball(path: Path) -> dict[str, str]:
    path = path.resolve()
    observed = sha256(path)
    if observed != CRAN_SHA256:
        raise RuntimeError(f"CRAN exdqlm 1.1.1 SHA-256 mismatch: {observed}")
    description = tarball_description(path)
    required = {
        "Package": "exdqlm",
        "Version": "1.1.1",
        "Repository": "CRAN",
    }
    for key, expected in required.items():
        if description.get(key) != expected:
            raise RuntimeError(f"CRAN DESCRIPTION mismatch for {key}: {description.get(key)!r}")
    return {
        "path": str(path),
        "sha256": observed,
        "package": description["Package"],
        "version": description["Version"],
        "repository": description["Repository"],
        "packaged": description.get("Packaged", ""),
        "date_publication": description.get("Date/Publication", ""),
    }


def package_probe(library: Path) -> dict:
    code = r'''
args <- commandArgs(trailingOnly = TRUE)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
desc <- utils::packageDescription("exdqlm", lib.loc = lib)
exports <- sort(getNamespaceExports(loadNamespace("exdqlm", lib.loc = lib)))
cat(jsonlite::toJSON(list(
  version = as.character(desc$Version),
  repository = as.character(desc$Repository),
  packaged = as.character(desc$Packaged),
  library = lib,
  exports = exports,
  r_version = R.version.string
), auto_unbox = TRUE))
'''
    output = subprocess.check_output(
        ["Rscript", "-e", code, str(library.resolve())],
        text=True,
    )
    probe = json.loads(output)
    if probe.get("version") != "1.1.1" or probe.get("repository") != "CRAN":
        raise RuntimeError(f"Installed package is not CRAN exdqlm 1.1.1: {probe}")
    exports = set(probe.get("exports", []))
    missing = sorted(set(REQUIRED_EXPORTS) - exports)
    forbidden = sorted(set(FORK_ONLY_EXPORTS) & exports)
    if missing or forbidden:
        raise RuntimeError(f"Unexpected installed API; missing={missing}, fork_only={forbidden}")
    probe["required_exports_present"] = list(REQUIRED_EXPORTS)
    probe["fork_only_exports_absent"] = list(FORK_ONLY_EXPORTS)
    return probe


def expected_manifest(tarball: dict, library: Path, probe: dict) -> dict:
    manifest = {
        "status": "installed_exact_cran_exdqlm_1.1.1",
        "scientific_role": "future_pricefm_static_al_exal_readout_only",
        "source_url": CRAN_URL,
        "source_tarball": tarball,
        "library": str(library.resolve()),
        "installed_package": probe,
        "fork_source_used": False,
        "launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    install_log = library / "pricefm_r67_cran111_install.log"
    if install_log.is_file():
        manifest["install_log"] = str(install_log)
        manifest["install_log_sha256"] = sha256(install_log)
    return manifest


def run(args: argparse.Namespace) -> dict:
    tarball_path = args.tarball.expanduser()
    if not tarball_path.is_file():
        if not args.download_if_missing:
            raise FileNotFoundError(tarball_path)
        atomic_download(str(args.source_url), tarball_path)
    tarball = verify_tarball(tarball_path)

    library = args.library.expanduser().resolve()
    manifest_path = library / MANIFEST.name
    if manifest_path.is_file() and (library / "exdqlm").is_dir() and not args.force:
        probe = package_probe(library)
        expected = expected_manifest(tarball, library, probe)
        current = json.loads(manifest_path.read_text())
        if current != expected:
            raise RuntimeError("Existing CRAN 1.1.1 runtime manifest conflicts with the requested source")
        return current

    if library.exists() and any(library.iterdir()):
        if not args.force:
            raise RuntimeError(f"Refusing to replace nonempty runtime library: {library}")
        shutil.rmtree(library)
    library.mkdir(parents=True, exist_ok=True)
    install_log = library / "pricefm_r67_cran111_install.log"
    with install_log.open("w") as log:
        subprocess.run(
            ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(tarball_path.resolve())],
            check=True,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
    probe = package_probe(library)
    manifest = expected_manifest(tarball, library, probe)
    write_json(manifest_path, manifest)
    return manifest


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
