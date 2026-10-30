"""Owned synthetic streaming archive tests; no real runtime or model reads."""
import copy
import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import resource
import signal
import tarfile
import tempfile
import unittest

SOURCE = Path(__file__).with_name("runtime_archive.py")
SPEC = importlib.util.spec_from_file_location("tested_runtime_archive", SOURCE)
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)

class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm_runtime_archive_")
        self.root = Path(self.temp.name)
        self.sources = self.root / "sources"
        self.sources.mkdir()
        self.rows = []
        for name, payload, mode in (("R_HOME/bin/exec/R", b"synthetic-not-ELF" * 100, 0o755),
                                    ("lib/libfixture.so.1", b"opaque-byte-fixture" * 100, 0o644)):
            path = self.sources / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload); os.chmod(path, mode)
            self.rows.append(dict(a.binding(path), relative=name, sha256=hashlib.sha256(payload).hexdigest()))

    def tearDown(self):
        self.temp.cleanup()

    def archive(self, changed=None, duplicate=False, trailer=None):
        path = self.root / ("mutated" + str(len(list(self.root.glob("mutated*")))) + ".tar.gz")
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as tar:
            for i, row in enumerate(self.rows):
                info = tarfile.TarInfo(row["relative"])
                payload = Path(row["resolved"]).read_bytes()
                info.size = len(payload); info.mode = row["mode"]; info.uid = info.gid = 0
                info.uname = info.gname = ""; info.mtime = 0
                if i == 0 and changed:
                    info, payload = changed(info, payload)
                tar.addfile(info, io.BytesIO(payload) if info.isreg() else None)
                if i == 0 and duplicate:
                    tar.addfile(info, io.BytesIO(payload))
        data = raw.getvalue() + (trailer or b"")
        with gzip.open(path, "wb") as handle:
            handle.write(data)
        return path

    def test_stream_roundtrip_complete_readback_sidecar_only(self):
        result = a.stream_archive(self.root / "output", self.rows, "SYNTHETIC_SHAPE_AVAILABILITY",
                                  {"purpose": "OWNED_SYNTHETIC_TEST"}, self.root)
        self.assertEqual(result["runtime_file_count"], 2)
        self.assertTrue(result["readback"]["all_member_SHA256s_verified"])
        with tarfile.open(result["archive"]["path"], "r:gz") as tar:
            self.assertEqual(set(tar.getnames()), set(x["relative"] for x in self.rows))
            self.assertNotIn("CARRIER_MANIFEST.json", tar.getnames())
        manifest = a.read_json(result["manifest"]["path"])
        self.assertTrue(manifest["manifest_sidecar_only_not_tar_member"])
        self.assertFalse(manifest["ABI_and_startup_proved"])

    def test_shape_same_names_sizes_modes_is_exact(self):
        self.assertEqual(a.shape_identity(self.rows), a.shape_identity(list(reversed(self.rows))))
        changed = copy.deepcopy(self.rows); changed[0]["mode"] = 0o644
        self.assertNotEqual(a.shape_identity(self.rows), a.shape_identity(changed))

    def test_traversal_absolute_and_outside_prefix_rejected(self):
        for name in ("../escape", "/R_HOME/escape", "R_HOME/../escape", "other/file", "R_HOME//file"):
            with self.assertRaises(ValueError):
                a.member_name(name)

    def test_duplicate_source_member_rejected(self):
        with self.assertRaises(ValueError):
            a.shape_rows(self.rows + [self.rows[0]])

    def test_file_total_and_mode_caps(self):
        for key, value in (("bytes", a.MAX_FILE + 1), ("bytes", -1), ("mode", 0o4755), ("bytes", True)):
            rows = copy.deepcopy(self.rows); rows[0][key] = value
            with self.assertRaises(ValueError):
                a.shape_rows(rows)
        too_many = [dict(relative="lib/file" + str(i), bytes=0, mode=0o644) for i in range(2049)]
        with self.assertRaises(ValueError):
            a.shape_rows(too_many)

    def test_source_lifetime_drift_fails_without_complete_result(self):
        Path(self.rows[0]["resolved"]).write_bytes(b"changed")
        with self.assertRaises(ValueError):
            a.stream_archive(self.root / "failed", self.rows, "SYNTHETIC_SHAPE_AVAILABILITY", {}, self.root)
        self.assertFalse((self.root / "failed/RESULT.json").exists())

    def test_wrong_source_hash_fails(self):
        self.rows[0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            a.stream_archive(self.root / "failedhash", self.rows, "SYNTHETIC_SHAPE_AVAILABILITY", {}, self.root)

    def test_archive_duplicate_member_rejected(self):
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(duplicate=True), self.rows)

    def test_archive_symlink_rejected(self):
        def mutate(info, payload):
            info.type = tarfile.SYMTYPE; info.linkname = "/etc/passwd"; info.size = 0
            return info, b""
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(changed=mutate), self.rows)

    def test_archive_hardlink_rejected(self):
        def mutate(info, payload):
            info.type = tarfile.LNKTYPE; info.linkname = "lib/libfixture.so.1"; info.size = 0
            return info, b""
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(changed=mutate), self.rows)

    def test_archive_directory_rejected(self):
        def mutate(info, payload):
            info.type = tarfile.DIRTYPE; info.size = 0
            return info, b""
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(changed=mutate), self.rows)

    def test_archive_mode_and_size_drift_rejected(self):
        def mode(info, payload):
            info.mode = 0o777
            return info, payload
        def size(info, payload):
            info.size += 1
            return info, payload + b"x"
        for change in (mode, size):
            with self.assertRaises(ValueError):
                a.validate_archive(self.archive(changed=change), self.rows)

    def test_archive_member_hash_drift_rejected(self):
        def mutate(info, payload):
            return info, b"x" + payload[1:]
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(changed=mutate), self.rows)

    def test_archive_unlisted_member_rejected(self):
        def mutate(info, payload):
            info.name = "lib/unlisted"
            return info, payload
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(changed=mutate), self.rows)

    def test_archive_truncated_gzip_rejected(self):
        path = self.archive()
        path.write_bytes(path.read_bytes()[:-12])
        with self.assertRaises((ValueError, EOFError, OSError)):
            a.validate_archive(path, self.rows)

    def test_nonzero_trailing_tar_bytes_rejected(self):
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(trailer=b"not-hidden-member"), self.rows)

    def test_extra_zero_tar_record_rejected(self):
        with self.assertRaises(ValueError):
            a.validate_archive(self.archive(trailer=bytes(tarfile.RECORDSIZE)), self.rows)

    def test_changed_legacy_helper_pin_rejected_before_import(self):
        path = self.root / "wrong.py"
        path.write_text("raise RuntimeError('must not execute')")
        with self.assertRaises(ValueError):
            a.load_legacy(a.pin(path))

    def test_unknown_role_and_existing_output_rejected(self):
        with self.assertRaises(ValueError):
            a.stream_archive(self.root / "badrole", self.rows, "REAL_ABI_PASS", {}, self.root)
        output = self.root / "exists"; output.mkdir()
        with self.assertRaises(FileExistsError):
            a.stream_archive(output, self.rows, "SYNTHETIC_SHAPE_AVAILABILITY", {}, self.root)

if __name__ == "__main__":
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3)); signal.alarm(45)
    if os.sched_getaffinity(0) != {31}:
        raise SystemExit("administrativeCPU31 required")
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ArchiveTests))
    print(stream.getvalue())
    print(json.dumps({"status": "PASS" if result.wasSuccessful() else "FAIL",
                      "tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
                      "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
                      "real_runtime_R_models_network": 0}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
