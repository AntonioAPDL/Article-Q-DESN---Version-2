"""Opaque carrier selection tests; no R, ELF execution, network or production writes."""
import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
import subprocess

s = importlib.util.spec_from_file_location("carrier", Path(__file__).with_name("runtime_carrier.py"))
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)

class CarrierTests(unittest.TestCase):
    def test_system_glibc_must_not_be_carried(self):
        for name in ("libc.so.6", "libm.so.6", "libpthread.so.0", "ld-linux-x86-64.so.2", "libnss_files.so.2"):
            self.assertTrue(m.host_glibc(name))
        for name in ("libmvec.so.1", "libthread_db.so.1", "libc-2.28.so",
                     "libmemusage.so", "libpcprofile.so", "libc_nonshared.a"):
            self.assertTrue(m.host_glibc(name))
        for name in ("libR.so", "libicuuc.so.60", "libgfortran.so.5", "libcrypto.so.1.1"):
            self.assertFalse(m.host_glibc(name))

    def test_dependency_names_cannot_escape_or_become_commands(self):
        for name in ("../../libc.so.6", "/tmp/x.so", "x;python", "$(x)"):
            with self.assertRaises(ValueError):
                m.resolve_library(name)

    def test_scientific_package_is_not_in_fixed_default_startup_set(self):
        self.assertNotIn("exdqlm", m.PACKAGES)
        self.assertNotIn("nimble", m.PACKAGES)
        self.assertIn("utils", m.PACKAGES)
        self.assertEqual((m.MAX_FILES, m.MAX_BYTES), (2048, 128*1024**2))

    def test_initial_tree_cannot_hide_glibc_through_a_logical_or_resolved_alias(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            ordinary = root / "ordinary.so"
            ordinary.write_bytes(b"not executed")
            alias = root / "libmvec.so.1"
            alias.symlink_to(ordinary)
            with self.assertRaises(ValueError):
                m.validate_source_names(alias)
            alias.unlink()
            forbidden = root / "libc-2.28.so"
            forbidden.write_bytes(b"not executed")
            alias = root / "innocent.so"
            alias.symlink_to(forbidden)
            with self.assertRaises(ValueError):
                m.validate_source_names(alias)

    def test_private_glibc_requirement_rejected_before_any_runtime_code(self):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "fake.so"
            p.write_bytes(b"\x7fELF" + b"owned header fixture")
            value = subprocess.CompletedProcess([], 0, b"Name: GLIBC_PRIVATE", b"")
            with patch.object(m.subprocess, "run", return_value=value):
                with self.assertRaises(ValueError):
                    m.dynamic(p)

    def test_readelf_uses_public_child_setup_without_private_runtime_flags(self):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "owned.so"
            p.write_bytes(b"\x7fELF" + b"owned header fixture")
            value = subprocess.CompletedProcess([], 0, b"Shared library: [libR.so]", b"")
            with patch.object(m.subprocess, "run", return_value=value) as run:
                self.assertEqual(m.dynamic(p)[0], ["libR.so"])
            self.assertIs(run.call_args.kwargs["preexec_fn"], m.public_fork_child_setup)
            self.assertIsNone(m.public_fork_child_setup())

if __name__ == "__main__":
    unittest.main()
