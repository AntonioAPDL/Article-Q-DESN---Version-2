#!/usr/bin/env python3

import csv
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "application/scripts/387_launch_glofas_part4_latent_family_dag.py"
CHECKER = ROOT / "application/scripts/388_check_glofas_part4_latent_family_dag.py"


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


if __name__ == "__main__":
    unittest.main()
