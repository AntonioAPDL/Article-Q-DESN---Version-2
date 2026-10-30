"""Build an opaque, byte-identical minimal R4.6 startup carrier without running R.

The carrier is not an ABI, startup, numerical or scientific-application proof.
Host glibc is never replaced. Only fixed installed runtime paths are read.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import stat
import subprocess
import tarfile
import time
from pricefm_hb.batch_preflight import read as read_metadata, pin as metadata_pin

ORIGIN = Path("/data/jaguir26/local/opt/R/4.6.0/lib64/R")
ELF_SHA = "9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27"
PACKAGES = ("base", "compiler", "datasets", "graphics", "grDevices", "grid", "methods",
            "parallel", "splines", "stats", "stats4", "tools", "utils")
ROOTS = ("bin", "etc", "lib", "modules", "share", "include")
MAX_FILES = 2048
MAX_BYTES = 128 * 1024**2
GLIBC = re.compile(
    r"^(?:libc|libm|libmvec|libpthread|libdl|librt|libresolv|libutil|libanl|libBrokenLocale|"
    r"libthread_db|libmemusage|libpcprofile|libSegFault|libc_malloc_debug)"
    r"(?:\.so(?:\.[A-Za-z0-9_.-]+)?|-[0-9][A-Za-z0-9_.-]*\.so|(?:_nonshared)?\.a)$")

def require(ok, message):
    if not ok:
        raise ValueError(message)

def write(path, value):
    with path.open("x") as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write("\n"); handle.flush(); os.fsync(handle.fileno())
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try: os.fsync(fd)
    finally: os.close(fd)

def pin(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

def physical_sources():
    paths = []
    for name in ROOTS:
        paths.extend(x for x in (ORIGIN / name).rglob("*") if x.is_file())
    for name in PACKAGES:
        paths.extend(x for x in (ORIGIN / "library" / name).rglob("*") if x.is_file())
    for name in ("COPYING", "README", "SVN-REVISION"):
        if (ORIGIN / name).is_file():
            paths.append(ORIGIN / name)
    return sorted(set(paths))

def public_fork_child_setup():
    """Public Popen preexec hook; this metadata builder must be single-threaded."""
    return None

def dynamic(path):
    with path.open("rb") as handle:
        magic = handle.read(4)
    if magic != b"\x7fELF":
        return [], []
    # readelf reads headers; it never starts the inspected R/shared-object code.
    require(len(list(Path("/proc/self/task").iterdir())) == 1,
            "public preexec fork setup requires a single-threaded metadata process")
    result = subprocess.run(["readelf", "-d", "--version-info", str(path)],
                            capture_output=True, check=True,
                            preexec_fn=public_fork_child_setup)
    require(len(result.stdout) <= 1024**2 and len(result.stderr) <= 1024**2, "readelf output bound")
    text = result.stdout.decode()
    require("GLIBC_PRIVATE" not in text, "private glibc ABI is not portable")
    needed = re.findall(r"Shared library: \[([^\]]+)\]", text)
    versions = sorted(set(re.findall(r"Name: (GLIBC_[0-9.]+)", text)))
    return needed, versions

def host_glibc(name):
    return bool(GLIBC.fullmatch(name)) or name.startswith(("ld-linux-", "ld-", "libnss_"))

def validate_source_names(source):
    require(not host_glibc(source.name) and not host_glibc(source.resolve(strict=True).name),
            "glibc-family payload forbidden in logical or resolved source")

def resolve_library(name):
    require(re.fullmatch(r"[A-Za-z0-9_+.-]+", name), "unsafe library name")
    for root in (ORIGIN / "lib", Path("/usr/lib64"), Path("/lib64"),
                 Path("/usr/lib/x86_64-linux-gnu"), Path("/lib/x86_64-linux-gnu")):
        path = root / name
        if path.is_file():
            return path
    raise ValueError("unresolved required native library: " + name)

def materialize(output, scope_pin):
    output = Path(output).absolute()
    require(os.sched_getaffinity(0) == {31}, "administrative CPU31 required")
    scope = read_metadata(scope_pin)
    require(scope["status"] in ("PROSPECTIVE_TWO_ROLE_HB_RUNTIME_QUALIFICATION_SCOPE",
                               "PROSPECTIVE_CARRIER_PUBLIC_FORK_SOURCE_REMEDY_SCOPE"),
            "separate prospective carrier scope required")
    require(scope["issued_epoch"] <= time.time() and time.time()+300 < scope["expires_epoch"],
            "complete preparation must fit fixed scope")
    allowed = Path(scope["allowed_metadata_output_root"]).absolute()
    require(output != allowed and output.is_relative_to(allowed), "carrier output outside own scope")
    require(not any(p.is_symlink() for p in (output, *output.parents)), "physical output path")
    require(pin(ORIGIN / "bin/exec/R")["sha256"] == ELF_SHA, "pinned native R ELF differs")
    output.mkdir(mode=0o700, exist_ok=False)
    write(output / "INTENT.json", dict(status="OPAQUE_RUNTIME_CARRIER_INTENT_NOT_COMPATIBILITY",
          origin=str(ORIGIN), native_ELF_sha256=ELF_SHA, created_epoch=time.time(),
          source=pin(Path(__file__)), scope=scope_pin, max_files=MAX_FILES, max_bytes=MAX_BYTES,
          R_executions=0, scientific_data_access=False))
    sources = {"R_HOME/" + str(p.relative_to(ORIGIN)): p for p in physical_sources()}
    for source in sources.values():
        validate_source_names(source)
    pending = list(sources.values())
    inspected = set()
    glibc_names = set()
    glibc_versions = set()
    while pending:
        source = pending.pop()
        identity = str(source.resolve(strict=True))
        if identity in inspected:
            continue
        inspected.add(identity)
        needed, versions = dynamic(source)
        glibc_versions.update(versions)
        for name in needed:
            if host_glibc(name):
                glibc_names.add(name)
                continue
            origin = resolve_library(name)
            validate_source_names(origin)
            if "R_HOME/lib/" + name in sources:
                # R_HOME/lib is first in the proposed loader path. Its exact
                # bytes already exist; do not duplicate them in external lib/.
                continue
            key = "lib/" + name
            if key not in sources:
                sources[key] = origin
                pending.append(origin)
    require(0 < len(sources) <= MAX_FILES, "bounded runtime file count")
    total = sum(p.stat().st_size for p in sources.values())
    require(total <= MAX_BYTES, "bounded total runtime bytes")
    bank = output / "bank"
    bank.mkdir(mode=0o700)
    rows = []
    for name, source in sorted(sources.items()):
        resolved = source.resolve(strict=True)
        before = resolved.stat()
        require(stat.S_ISREG(before.st_mode), "regular source required")
        target = bank / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        h = hashlib.sha256()
        with resolved.open("rb") as src, target.open("xb") as dest:
            for chunk in iter(lambda: src.read(1024**2), b""):
                h.update(chunk); dest.write(chunk)
        after = resolved.stat()
        key = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns)
        require(key(before) == key(after), "runtime changed during byte copy")
        mode = stat.S_IMODE(before.st_mode) & 0o777
        os.chmod(target, mode)
        rows.append(dict(name=name, original_logical_path=str(source),
                         original_resolved_path=str(resolved), sha256=h.hexdigest(),
                         bytes=before.st_size, mode=mode, original_symlink=source.is_symlink(),
                         device=before.st_dev, inode=before.st_ino, mtime_ns=before.st_mtime_ns))
    # All writes finish first. No global sync and no interleaved file/dir flush.
    for row in rows:
        path = bank / row["name"]
        require(pin(path)["sha256"] == row["sha256"], "copied runtime bytes differ")
        require(pin(Path(row["original_resolved_path"]))["sha256"] == row["sha256"],
                "origin runtime drift after copy")
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
    manifest = dict(status="BYTE_IDENTICAL_STARTUP_CARRIER_NOT_RUNTIME_PROOF",
        source=pin(Path(__file__)), scope=scope_pin,
        metadata_reader_source=metadata_pin(Path(read_metadata.__code__.co_filename)),
        native_ELF_sha256=ELF_SHA, files=rows,
        file_count=len(rows), total_bytes=sum(x["bytes"] for x in rows),
        host_glibc_not_bundled=sorted(glibc_names), required_GLIBC_versions=sorted(glibc_versions),
        all_writes_before_file_fsync=True, no_R_execution=True,
        library_aliases_are_regular_copies=True, no_installed_runtime_modified=True,
        exdqlm_or_real_target_packages_included=False, scientific_or_ABI_parity=False)
    write(bank / "CARRIER_MANIFEST.json", manifest)
    archive = output / "runtime_carrier.tar.gz"
    with archive.open("xb") as raw:
        with gzip.GzipFile(filename="", mode="wb", compresslevel=1, fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w|") as tar:
                for path in sorted(bank.rglob("*")):
                    if not path.is_file():
                        continue
                    info = tar.gettarinfo(str(path), arcname=str(path.relative_to(bank)))
                    require(info.isfile(), "archive contains regular files only")
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    with path.open("rb") as handle:
                        tar.addfile(info, handle)
        raw.flush(); os.fsync(raw.fileno())
    for path in sorted([p for p in bank.rglob("*") if p.is_dir()] + [bank, output],
                       key=lambda p: len(p.parts), reverse=True):
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
    anchor = Path(scope.get("durability_anchor", str(allowed.parent.parent))).absolute()
    require(output.is_relative_to(anchor) and anchor != Path("/"), "bounded durability ancestor")
    for path in output.parents:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
        if path == anchor:
            break
    result = dict(status=manifest["status"], archive=pin(archive),
          archive_bytes=archive.stat().st_size, manifest=pin(bank / "CARRIER_MANIFEST.json"),
          runtime_file_count=len(rows), runtime_total_bytes=manifest["total_bytes"],
          no_R_or_model_execution=True, ABI_and_startup_unproved=True)
    write(output / "RESULT.json", result)
    return result

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--scope", required=True)
    args = p.parse_args()
    print(json.dumps(materialize(args.output, metadata_pin(args.scope))))

if __name__ == "__main__":
    main()
