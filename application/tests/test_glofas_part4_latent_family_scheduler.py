#!/usr/bin/env python3

import csv
import hashlib
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "application/scripts/387_launch_glofas_part4_latent_family_dag.py"
CHECKER = ROOT / "application/scripts/388_check_glofas_part4_latent_family_dag.py"
SPEC = importlib.util.spec_from_file_location("part4_launcher", LAUNCHER)
part4_launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(part4_launcher)


class Part4SchedulerContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.runtime = Path(self.temp.name)
        (self.runtime / "configs").mkdir()
        (self.runtime / "status").mkdir()
        fields = ["run_id", "dependencies"]
        with (self.runtime / "configs/part4_model_manifest.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for index in range(18):
                writer.writerow({"run_id": "job_%02d" % index, "dependencies": ""})

    def tearDown(self):
        self.temp.cleanup()

    def test_launcher_is_fail_closed_without_approval(self):
        result = subprocess.run(
            [sys.executable, str(LAUNCHER), "--runtime-root", str(self.runtime)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Launch blocked", result.stdout)

    def test_checker_reports_prepared_not_launched(self):
        result = subprocess.run(
            [sys.executable, str(CHECKER), "--runtime-root", str(self.runtime)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            check=True,
        )
        self.assertIn("part4_latent_family,18,0,0,0,18,18", result.stdout)

    def test_serial_openblas_environment_is_hashed_and_pinned(self):
        library = self.runtime / "libopenblas.so"
        library.write_bytes(b"part4-test-library")
        env = part4_launcher.runtime_env(library)
        self.assertEqual(env["QDESN_NUMERICAL_BACKEND"], "openblas_serial")
        self.assertEqual(env["QDESN_BLAS_LIBRARY_PATH"], str(library))
        self.assertEqual(
            env["QDESN_BLAS_LIBRARY_SHA256"],
            hashlib.sha256(library.read_bytes()).hexdigest(),
        )
        self.assertTrue(all(env[key] == "1" for key in part4_launcher.THREAD_ENV))
        self.assertEqual(env["LD_PRELOAD"].split(":", 1)[0], str(library))


if __name__ == "__main__":
    unittest.main()
