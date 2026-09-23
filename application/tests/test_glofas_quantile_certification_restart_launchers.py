#!/usr/bin/env python3.11

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, REPO / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


prepare = load("glofas_cert_prepare", "application/scripts/416_prepare_glofas_quantile_certification_restart.py")
launch = load("glofas_cert_launch", "application/scripts/418_launch_glofas_quantile_certification_restart.py")


class CertificationLauncherTests(unittest.TestCase):
    def test_exact_restart_set(self):
        self.assertEqual(len(prepare.UNRESOLVED), 9)
        self.assertEqual(sum(row[0] == "part1" for row in prepare.UNRESOLVED), 4)
        self.assertEqual(sum(row[0] == "part2" for row in prepare.UNRESOLVED), 4)
        self.assertEqual(sum(row[0] == "part3" for row in prepare.UNRESOLVED), 1)
        self.assertEqual(sum(row[1] == "joint_exal" for row in prepare.UNRESOLVED), 2)

    def test_state_and_certification_are_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "status").mkdir()
            job_id = "cert_fit"
            (root / "status" / f"{job_id}.completed").write_text("done\n")
            self.assertEqual(launch.state(root, job_id), "completed")
            self.assertFalse(launch.certified(root, job_id))
            (root / "status" / f"{job_id}.certified").write_text("certified\n")
            self.assertTrue(launch.certified(root, job_id))

    def test_health_reports_certified_fit_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "status").mkdir()
            jobs = [
                {"job_id": "fit_a", "action": "fit"},
                {"job_id": "forecast_a", "action": "forecast"},
            ]
            (root / "status/fit_a.completed").write_text("done\n")
            (root / "status/fit_a.certified").write_text("certified\n")
            payload = launch.health(root, jobs, {})
            self.assertEqual(payload["fit_completed"], 1)
            self.assertEqual(payload["fit_certified"], 1)
            self.assertEqual(payload["pending"], 1)
            saved = json.loads((root / "status/scheduler_health.json").read_text())
            self.assertEqual(saved["fit_certified"], 1)


if __name__ == "__main__":
    unittest.main()
