"""Stream opaque runtime files to one durable regular-only archive.

No R, model, NumPy, ABI test or numerical payload is executed. The installed
runtime and every old failed carrier bank remain unchanged.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import io
import gzip
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import resource
import signal
import stat
import tarfile
import time

SCHEMA = "pricefm_streaming_runtime_archive_v1"
LEGACY_SHA = "78f8ecc975751908a5d3a8a70f65e908660cc7747fc6e5b6920d416243af8799"
ELF_SHA = "9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27"
MAX_FILES, MAX_TOTAL, MAX_FILE = 2048, 128 * 1024**2, 64 * 1024**2
ROLES = {"SYNTHETIC_SHAPE_AVAILABILITY", "REAL_R46_STARTUP_ARCHIVE"}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def physical(path):
    path = Path(path).absolute()
    require(".." not in path.parts and not any(x.is_symlink() for x in (path, *path.parents)),
            "physical path required")
    return path

def duplicate_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result

def read_json(path):
    path = physical(path)
    require(path.stat().st_size <= 16 * 1024**2 and path.is_file(), "bounded JSON metadata required")
    def finite_float(text):
        value = float(text)
        require(math.isfinite(value), "nonfinite JSON")
        return value
    return json.loads(path.read_bytes(), object_pairs_hook=duplicate_pairs,
                      parse_float=finite_float, parse_constant=lambda x: (_ for _ in ()).throw(ValueError("nonfinite JSON")))

def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024**2), b""):
            h.update(chunk)
    return h.hexdigest()

def pin(path):
    return {"path": str(Path(path).absolute()), "sha256": digest(path)}

def read(value):
    require(type(value) is dict and set(value) == {"path", "sha256"}, "strict two-field pin required")
    require(pin(physical(value["path"])) == value, "metadata/source pin drift")
    return read_json(value["path"])

def raw_json(value):
    return (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()

def write_json(path, value):
    with path.open("xb") as handle:
        handle.write(raw_json(value)); handle.flush(); os.fsync(handle.fileno())

def member_name(name):
    require(type(name) is str and re.fullmatch(r"[A-Za-z0-9_./+@-]+", name), "unsafe archive member")
    p = PurePosixPath(name)
    require(not p.is_absolute() and ".." not in p.parts and "." not in p.parts
            and str(p) == name and len(p.parts) >= 2 and p.parts[0] in {"R_HOME", "lib"},
            "runtime member outside complete allowlist")
    info = tarfile.TarInfo(name)
    info.tobuf(format=tarfile.USTAR_FORMAT, encoding="utf-8", errors="strict")
    return name

def shape_rows(rows):
    output, names = [], set()
    for row in rows:
        name = member_name(row["relative"])
        require(name not in names, "duplicate runtime member")
        names.add(name)
        require(type(row["bytes"]) is int and 0 <= row["bytes"] <= MAX_FILE
                and type(row["mode"]) is int and 0 <= row["mode"] <= 0o777, "runtime size/mode boundary")
        output.append({"relative": name, "bytes": row["bytes"], "mode": row["mode"],
                       "depth": len(PurePosixPath(name).parts)})
    output.sort(key=lambda x: x["relative"])
    require(0 < len(output) <= MAX_FILES and sum(x["bytes"] for x in output) <= MAX_TOTAL, "runtime shape cap")
    return output

def shape_identity(rows):
    return hashlib.sha256(json.dumps(shape_rows(rows), sort_keys=True, separators=(",", ":")).encode()).hexdigest()

def load_legacy(value):
    path = physical(value["path"])
    require(pin(path) == value and value["sha256"] == LEGACY_SHA, "frozen legacy metadata helper source differs")
    spec = importlib.util.spec_from_file_location("pricefm_hb._frozen_runtime_archive_helpers", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def lifetime(value):
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
            value.st_ctime_ns, stat.S_IMODE(value.st_mode))

def binding(logical):
    logical = Path(logical).absolute()
    resolved = logical.resolve(strict=True)
    before = logical.lstat()
    current = resolved.stat()
    require(stat.S_ISREG(current.st_mode) and current.st_size <= MAX_FILE, "bounded regular source required")
    return {"logical": str(logical), "resolved": str(resolved),
            "logical_lifetime": list(lifetime(before)), "resolved_lifetime": list(lifetime(current)),
            "bytes": current.st_size, "mode": stat.S_IMODE(current.st_mode) & 0o777}

def gather_real(legacy, expected_shape):
    require(legacy.ELF_SHA == ELF_SHA and digest(legacy.ORIGIN / "bin/exec/R") == ELF_SHA, "native R ELF pin differs")
    sources = {"R_HOME/" + str(path.relative_to(legacy.ORIGIN)): path for path in legacy.physical_sources()}
    require(0 < len(sources) <= MAX_FILES, "initial runtime source count cap")
    for path in sources.values():
        legacy.validate_source_names(path)
    pending, inspected, headers = list(sources.values()), set(), {}
    glibc, versions = set(), set()
    while pending:
        path = pending.pop()
        before = binding(path)
        resolved = before["resolved"]
        if resolved in inspected:
            continue
        inspected.add(resolved)
        needed, required = legacy.dynamic(path)
        require(binding(path) == before, "native headers/source lifetime changed during readelf")
        headers[resolved] = before["resolved_lifetime"]
        versions.update(required)
        for name in needed:
            if legacy.host_glibc(name):
                glibc.add(name)
                continue
            origin = legacy.resolve_library(name)
            legacy.validate_source_names(origin)
            if "R_HOME/lib/" + name in sources:
                continue
            key = "lib/" + name
            if key not in sources:
                sources[key] = origin
                require(len(sources) <= MAX_FILES, "complete runtime source count cap")
                pending.append(origin)
    snapshots = []
    for name, path in sorted(sources.items()):
        legacy.validate_source_names(path)
        before = binding(path)
        require(headers.get(before["resolved"]) == before["resolved_lifetime"], "source drift after native header validation")
        snapshots.append(dict(before, relative=name))
    require(shape_rows(snapshots) == shape_rows(expected_shape), "actual source shape changed before source hashing/archive")
    rows = []
    for before in snapshots:
        path = Path(before["logical"])
        file_hash = digest(before["resolved"])
        current = binding(path)
        require(current == {k: before[k] for k in current}, "source drift during initial hash")
        rows.append(dict(before, sha256=file_hash))
    shape_rows(rows)
    return rows, {"host_glibc_not_bundled": sorted(glibc), "required_GLIBC_versions": sorted(versions),
                  "native_ELF_sha256": ELF_SHA, "legacy_source_unchanged": True}

class HashingReader:
    def __init__(self, handle):
        self.handle, self.h, self.count = handle, hashlib.sha256(), 0
    def read(self, size=-1):
        data = self.handle.read(size)
        self.h.update(data); self.count += len(data)
        return data

def exact(handle, size):
    raw = handle.read(size)
    require(len(raw) == size, "truncated runtime archive")
    return raw

def validate_archive(archive, rows):
    """Consume every gzip/tar byte, rejecting hidden members and trailing data."""
    expected = {row["relative"]: row for row in rows}
    require(len(expected) == len(rows), "duplicate expected archive member")
    seen, expanded = set(), 0
    expected_tar_bytes = sum(512 + ((x["bytes"] + 511) // 512) * 512 for x in rows) + 1024
    expected_tar_bytes = ((expected_tar_bytes + tarfile.RECORDSIZE - 1) // tarfile.RECORDSIZE) * tarfile.RECORDSIZE
    with gzip.open(archive, "rb") as handle:
        while True:
            block = exact(handle, 512); expanded += 512
            if block == bytes(512):
                require(exact(handle, 512) == bytes(512), "tar end marker incomplete")
                expanded += 512
                for tail in iter(lambda: handle.read(1024**2), b""):
                    expanded += len(tail)
                    require(not any(tail), "nonzero trailing tar payload")
                break
            require(block[257:263] == b"ustar\0" and block[263:265] == b"00", "strict USTAR header required")
            info = tarfile.TarInfo.frombuf(block, "utf-8", "strict")
            name = member_name(info.name)
            require(info.type == tarfile.REGTYPE and not info.linkname and name in expected and name not in seen,
                    "unlisted/duplicate/link/special archive member")
            row = expected[name]
            require(info.size == row["bytes"] and info.mode == row["mode"]
                    and info.uid == info.gid == 0 and info.mtime == 0
                    and info.uname == info.gname == "", "archive member size/mode/identity differs")
            h, remaining = hashlib.sha256(), info.size
            while remaining:
                chunk = exact(handle, min(1024**2, remaining))
                h.update(chunk); remaining -= len(chunk); expanded += len(chunk)
            require(h.hexdigest() == row["sha256"], "archive member SHA256 differs")
            padding = (-info.size) % 512
            require(exact(handle, padding) == bytes(padding), "nonzero member padding")
            expanded += padding; seen.add(name)
    require(seen == set(expected) and expanded == expected_tar_bytes, "incomplete/extra archive bytes or members")
    return {"regular_members": len(seen), "expanded_tar_bytes": expanded,
            "all_member_SHA256s_verified": True, "gzip_CRC_and_complete_EOF_verified": True}

def sync_ancestry(output, anchor):
    require(output.is_relative_to(anchor), "durability anchor outside output ancestry")
    for directory in (output, *output.parents):
        fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
        if directory == anchor:
            break

def stream_archive(output, rows, role, provenance, anchor):
    require(role in ROLES, "typed runtime archive role required")
    rows = sorted(rows, key=lambda x: x["relative"])
    shape_rows(rows)
    output = physical(output)
    output.mkdir(mode=0o700, exist_ok=False)
    write_json(output / "INTENT.json", {"status": "STREAMING_RUNTIME_ARCHIVE_INTENT_NOT_COMPLETE",
        "role": role, "runtime_files": len(rows), "runtime_bytes": sum(x["bytes"] for x in rows),
        "no_persistent_runtime_bank": True, "provenance": provenance})
    archive = output / "runtime_carrier.tar.gz"
    manifests = []
    with archive.open("xb") as raw:
        with gzip.GzipFile(filename="", mode="wb", compresslevel=1, fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w|", format=tarfile.USTAR_FORMAT) as tar:
                for row in rows:
                    current = binding(row["logical"])
                    require(all(current[k] == row[k] for k in current), "source lifetime drift before streaming")
                    fd = os.open(row["resolved"], os.O_RDONLY | os.O_NOFOLLOW)
                    with os.fdopen(fd, "rb") as source:
                        require(list(lifetime(os.fstat(source.fileno()))) == row["resolved_lifetime"], "opened source identity differs")
                        info = tarfile.TarInfo(member_name(row["relative"]))
                        info.size, info.mode, info.mtime = row["bytes"], row["mode"], 0
                        info.uid = info.gid = 0; info.uname = info.gname = ""
                        info.type = tarfile.REGTYPE
                        reader = HashingReader(source)
                        tar.addfile(info, reader)
                        require(reader.count == row["bytes"] and reader.h.hexdigest() == row["sha256"], "source byte/hash drift while streaming")
                        require(list(lifetime(os.fstat(source.fileno()))) == row["resolved_lifetime"], "source changed while streaming")
                    require(binding(row["logical"]) == current and digest(row["resolved"]) == row["sha256"], "source hash/lifetime drift after streaming")
                    manifests.append({"relative": row["relative"], "bytes": row["bytes"], "sha256": row["sha256"], "mode": row["mode"],
                                      "original_logical_path": row["logical"], "original_resolved_path": row["resolved"],
                                      "original_logical_lifetime": row["logical_lifetime"], "original_resolved_lifetime": row["resolved_lifetime"]})
        raw.flush(); os.fsync(raw.fileno())
    archive_before = pin(archive)
    manifest = {"schema": SCHEMA, "status": "COMPLETE_OPAQUE_STREAMING_STARTUP_ARCHIVE_NOT_RUNTIME_PROOF",
                "role": role, "files": manifests, "file_count": len(manifests),
                "total_bytes": sum(x["bytes"] for x in manifests), "shape_sha256": shape_identity(manifests),
                "provenance": provenance, "manifest_sidecar_only_not_tar_member": True,
                "no_persistent_runtime_bank": True, "R_executions": 0, "ABI_and_startup_proved": False,
                "scientific_data_access": False}
    sidecar = output / "CARRIER_MANIFEST.json"
    write_json(sidecar, manifest)
    readback = validate_archive(archive, manifests)
    require(pin(archive) == archive_before and sidecar.read_bytes() == raw_json(manifest), "archive/sidecar drift during complete readback")
    for row in rows:
        current = binding(row["logical"])
        require(current == {k: row[k] for k in current} and digest(row["resolved"]) == row["sha256"],
                "original source drift at final readback")
    sync_ancestry(output, physical(anchor))
    result = {"status": "PASS_COMPLETE_DURABLE_STREAMING_RUNTIME_ARCHIVE", "role": role,
              "archive": archive_before, "archive_bytes": archive.stat().st_size, "manifest": pin(sidecar),
              "runtime_file_count": len(manifests), "runtime_total_bytes": manifest["total_bytes"],
              "shape_sha256": manifest["shape_sha256"], "readback": readback,
              "no_R_or_model_execution": True, "ABI_and_startup_unproved": True}
    write_json(output / "RESULT.json", result)
    sync_ancestry(output, physical(anchor))
    return result

def prepare_fixture(scope_pin, partial_bank, fixture_root, shape_output, fixture_output):
    scope = read(scope_pin)
    require(scope["status"] == "PROSPECTIVE_OPAQUE_STREAMING_RUNTIME_ARCHIVE_SCOPE"
            and time.time() + 60 < scope["expires_epoch"], "fresh fixture preparation scope required")
    bank, root = physical(partial_bank), physical(fixture_root)
    allowed = physical(scope["allowed_metadata_output_root"])
    for target in (physical(shape_output), physical(fixture_output)):
        require(target != allowed and target.is_relative_to(allowed) and not target.exists(),
                "fixture metadata output outside actual scope or already exists")
    require(root.parent == Path("/dev/shm") and root.name.startswith("pricefm_runtime_archive_fixture_")
            and not root.exists(), "private owned tmpfs fixture required")
    rows = []
    for path in sorted(bank.rglob("*")):
        require(not path.is_symlink(), "partial-bank shape links forbidden")
        if path.is_file():
            st = path.stat()
            require(stat.S_ISREG(st.st_mode), "regular partial-bank shape required")
            rows.append({"relative": str(path.relative_to(bank)), "bytes": st.st_size,
                         "mode": stat.S_IMODE(st.st_mode) & 0o777})
    rows = shape_rows(rows)
    require(len(rows) == 680 and sum(x["bytes"] for x in rows) == 111883856, "original failed-bank shape changed")
    require(sum(x["bytes"] for x in rows) <= 128 * 1024**2, "private fixture capacity bound")
    root.mkdir(mode=0o700)
    sources = []
    for row in rows:
        target = root / row["relative"]
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        h, remaining, counter = hashlib.sha256(), row["bytes"], 0
        with target.open("xb") as handle:
            while remaining:
                seed = ("pricefm-runtime-archive-shape04:" + row["relative"] + ":" + str(counter)).encode()
                chunk = hashlib.shake_256(seed).digest(min(1024**2, remaining))
                handle.write(chunk); h.update(chunk); remaining -= len(chunk); counter += 1
        os.chmod(target, row["mode"])
        sources.append(dict(binding(target), relative=row["relative"], sha256=h.hexdigest()))
    shape = {"status": "FROZEN_METADATA_ONLY_RUNTIME_SHAPE", "role": "SHAPE_NOT_RUNTIME_ABI_PROOF",
             "source_partial_bank": str(bank), "rows": rows, "shape_sha256": shape_identity(rows),
             "file_count": len(rows), "total_bytes": sum(x["bytes"] for x in rows),
             "max_file_bytes": max(x["bytes"] for x in rows), "max_depth": max(x["depth"] for x in rows),
             "real_runtime_payloads_read": False}
    write_json(physical(shape_output), shape)
    fixture = {"status": "PREPARED_OWNED_INCOMPRESSIBLE_SYNTHETIC_SHAPE_NOT_EXECUTED",
               "role": "SYNTHETIC_SHAPE_AVAILABILITY", "scope": scope_pin, "fixture_root": str(root),
               "producer_source": pin(Path(__file__).absolute()),
               "shape": pin(shape_output), "sources": sources, "generator": "deterministic_independent_SHAKE256_blocks",
               "real_runtime_payloads_used": False, "private_tmpfs_payload_bytes": shape["total_bytes"]}
    write_json(physical(fixture_output), fixture)
    return {"shape": pin(shape_output), "fixture": pin(fixture_output), "file_count": len(rows), "total_bytes": shape["total_bytes"]}

def build(config_pin, execution_pin):
    cfg, grant = read(config_pin), read(execution_pin)
    source = pin(Path(__file__).absolute())
    require(cfg["schema"] == SCHEMA and cfg["source"] == source, "archive source/config binding differs")
    scope = read(cfg["scope"])
    require(scope["status"] == "PROSPECTIVE_OPAQUE_STREAMING_RUNTIME_ARCHIVE_SCOPE"
            and scope["issued_epoch"] <= time.time() and time.time() + 300 < scope["expires_epoch"], "fixed streaming scope/calendar")
    require(scope.get("max_files") == MAX_FILES and scope.get("max_payload_bytes") == MAX_TOTAL
            and scope.get("max_per_file_bytes") == MAX_FILE and scope.get("same_CPU_guard") == 24
            and scope.get("same_wall_guard") == 300, "original archive limits differ")
    require(grant["status"] == "ROOT_AUTHORIZED_ONE_SHOT_STREAMING_RUNTIME_ARCHIVE"
            and grant["config"] == config_pin and grant["source"] == source
            and grant["scope"] == cfg["scope"] and grant["role"] == cfg["role"], "actual exact root archive execution authority required")
    require(time.time() + 300 < grant["expires_epoch"] <= scope["expires_epoch"], "root archive execution window")
    require(os.sched_getaffinity(0) == {31} and cfg["role"] in ROLES, "adminCPU31/typed role required")
    allowed, anchor, output = physical(scope["allowed_metadata_output_root"]), physical(scope["durability_anchor"]), physical(cfg["output"])
    require(output != allowed and output.is_relative_to(allowed), "archive outside own output scope")
    shape = read(cfg["expected_shape"])
    require(shape["shape_sha256"] == shape_identity(shape["rows"]), "frozen shape pin differs")
    legacy = load_legacy(cfg["legacy_source"])
    if cfg["role"] == "SYNTHETIC_SHAPE_AVAILABILITY":
        fixture = read(cfg["fixture"])
        require(fixture["role"] == cfg["role"] and fixture["shape"] == cfg["expected_shape"]
                and fixture["real_runtime_payloads_used"] is False, "honest synthetic source binding required")
        rows = fixture["sources"]
        fixture_root = physical(fixture["fixture_root"])
        require(fixture_root.parent == Path("/dev/shm") and fixture_root.name.startswith("pricefm_runtime_archive_fixture_")
                and fixture_root.stat().st_uid == os.getuid() and stat.S_IMODE(fixture_root.stat().st_mode) == 0o700,
                "owned private tmpfs synthetic fixture required")
        for row in rows:
            logical = physical(row["logical"])
            require(logical == fixture_root / member_name(row["relative"])
                    and str(logical) == row["resolved"] and logical.stat().st_uid == os.getuid()
                    and logical.stat().st_nlink == 1, "synthetic role cannot reference real runtime or linked payloads")
        provenance = {"source": source, "scope": cfg["scope"], "legacy_source": cfg["legacy_source"], "config": config_pin,
                      "execution_authority": execution_pin, "fixture": cfg["fixture"], "expected_shape": cfg["expected_shape"],
                      "fixture_generator_source_at_capture": fixture["producer_source"],
                      "real_runtime_payloads_used": False}
    else:
        qualification = read(cfg["qualification_review"])
        require(qualification["status"] == "PASS_QUALIFIED_STREAMING_RUNTIME_ARCHIVE_ALGORITHM"
                and qualification["source"] == source and qualification["expected_shape"] == cfg["expected_shape"],
                "actual independent same-source same-shape synthetic algorithm qualification required")
        proof = read(qualification["synthetic_guard"])
        require(type(proof.get("returncode")) is int and proof["returncode"] == 0
                and type(proof.get("command_returncode")) is int and proof["command_returncode"] == 0
                and type(proof.get("CPU_limit")) is int and proof["CPU_limit"] == 24
                and type(proof.get("aggregate_CPU_seconds")) in (int, float)
                and math.isfinite(proof["aggregate_CPU_seconds"]) and 0 <= proof["aggregate_CPU_seconds"] < 24
                and type(proof.get("complete_lifecycle_wall_seconds")) in (int, float)
                and math.isfinite(proof["complete_lifecycle_wall_seconds"])
                and 0 <= proof["complete_lifecycle_wall_seconds"] <= 300
                and proof.get("independent_guardian") is True and proof.get("kernel_escape_filter") is True
                and proof.get("all_owned_descendants_reaped") is True
                and proof.get("guardian_forced_monitor_stop") is False
                and "cap_reason" in proof and proof["cap_reason"] is None
                and type(proof.get("maximum_stop_wait_seconds")) in (int, float)
                and math.isfinite(proof["maximum_stop_wait_seconds"])
                and 0 <= proof["maximum_stop_wait_seconds"] <= 5,
                "actual original24CPU/300wall/5stop synthetic guardian did not pass")
        synthetic_result = read(qualification["synthetic_result"])
        require(json.loads(proof["stdout"]) == synthetic_result
                and synthetic_result["status"] == "PASS_COMPLETE_DURABLE_STREAMING_RUNTIME_ARCHIVE"
                and synthetic_result["role"] == "SYNTHETIC_SHAPE_AVAILABILITY"
                and synthetic_result["shape_sha256"] == shape["shape_sha256"]
                and synthetic_result["readback"]["all_member_SHA256s_verified"] is True,
                "actual complete synthetic same-shape result required")
        rows, native = gather_real(legacy, shape["rows"])
        provenance = {"source": source, "scope": cfg["scope"], "legacy_source": cfg["legacy_source"], "config": config_pin,
                      "execution_authority": execution_pin, "qualification_review": cfg["qualification_review"],
                      "expected_shape": cfg["expected_shape"], "native_dependency_metadata": native,
                      "real_runtime_payloads_used": True}
    require(shape_rows(rows) == shape_rows(shape["rows"]) and shape_identity(rows) == shape["shape_sha256"],
            "actual complete source shape differs; requalification required before archive creation")
    for row in rows:
        legacy.validate_source_names(Path(row["logical"]))
    return stream_archive(output, rows, cfg["role"], provenance, anchor)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config"); parser.add_argument("--config-sha256")
    parser.add_argument("--execution-authority"); parser.add_argument("--execution-authority-sha256")
    parser.add_argument("--prepare-fixture", action="store_true")
    parser.add_argument("--scope"); parser.add_argument("--scope-sha256")
    parser.add_argument("--partial-bank"); parser.add_argument("--fixture-root")
    parser.add_argument("--shape-output"); parser.add_argument("--fixture-output")
    args = parser.parse_args()
    if args.prepare_fixture:
        resource.setrlimit(resource.RLIMIT_CPU, (4, 4)); signal.alarm(60)
        require(os.sched_getaffinity(0) == {31}, "administrativeCPU31 required")
        result = prepare_fixture({"path": str(physical(args.scope)), "sha256": args.scope_sha256},
                                 args.partial_bank, args.fixture_root, args.shape_output, args.fixture_output)
    else:
        require(all((args.config, args.config_sha256, args.execution_authority, args.execution_authority_sha256)), "source-bound config/actual execution grant required")
        result = build({"path": str(physical(args.config)), "sha256": args.config_sha256},
                       {"path": str(physical(args.execution_authority)), "sha256": args.execution_authority_sha256})
    print(json.dumps(result, sort_keys=True))

if __name__ == "__main__":
    main()
