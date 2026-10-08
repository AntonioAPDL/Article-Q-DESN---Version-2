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


prepare = load(
    "glofas_cert_cont_prepare",
    "application/scripts/422_prepare_glofas_quantile_certification_continuation.py",
)
selective = load(
    "glofas_cert_selective_prepare",
    "application/scripts/426_prepare_glofas_quantile_selective_continuation.py",
)
launch = load(
    "glofas_cert_cont_launch",
    "application/scripts/424_launch_glofas_quantile_certification_continuation.py",
)
check = load(
    "glofas_cert_cont_check",
    "application/scripts/425_check_glofas_quantile_certification_continuation.py",
)


class CertificationContinuationTests(unittest.TestCase):
    def test_exact_independent_source_set(self):
        self.assertEqual(len(prepare.ELIGIBLE_SOURCE_IDS), 4)
        self.assertEqual(sum("part1" in value for value in prepare.ELIGIBLE_SOURCE_IDS), 2)
        self.assertEqual(sum("part2" in value for value in prepare.ELIGIBLE_SOURCE_IDS), 2)
        self.assertTrue(all("independent_al" in value for value in prepare.ELIGIBLE_SOURCE_IDS))

    def test_selective_source_set_is_explicit_and_mixed_iteration(self):
        rows = selective.SELECTED_SOURCES
        self.assertEqual(len(rows), 4)
        self.assertEqual(sum(row["source_iterations"] == 600 for row in rows), 2)
        self.assertEqual(sum(row["source_iterations"] == 400 for row in rows), 2)
        self.assertEqual(sum(row["model_family"] == "independent_al" for row in rows), 2)
        self.assertEqual(sum(row["model_family"] == "joint_exal" for row in rows), 2)
        self.assertFalse(any(row["model_family"] == "joint_al" for row in rows))

    def test_checker_supports_per_job_iteration_contract(self):
        contract = {"iteration_contract": {"continuation_iterations": 200}}
        job = {
            "job_id": "fit_a", "expected_source_iterations": 600,
            "expected_cumulative_iterations": 800,
        }
        self.assertEqual(check.expected_iterations(job, contract), (600, 200, 800))
        old_contract = {"iteration_contract": {
            "source_iterations": 400, "continuation_iterations": 200,
            "cumulative_iterations": 600,
        }}
        self.assertEqual(check.expected_iterations({"job_id": "old"}, old_contract), (400, 200, 600))

    def test_completed_and_certified_are_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "status").mkdir()
            (root / "status/fit.completed").write_text("done\n")
            self.assertEqual(launch.state(root, "fit"), "completed")
            self.assertFalse(launch.certified(root, "fit"))
            (root / "status/fit.certified").write_text("certified\n")
            self.assertTrue(launch.certified(root, "fit"))

    def test_dynamic_health_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "status").mkdir()
            jobs = [
                {"job_id": "fit_a", "action": "fit"},
                {"job_id": "forecast_a", "action": "forecast"},
                {"job_id": "fit_b", "action": "fit"},
                {"job_id": "forecast_b", "action": "forecast"},
            ]
            (root / "status/fit_a.completed").write_text("done\n")
            (root / "status/fit_a.certified").write_text("certified\n")
            (root / "status/fit_b.running").write_text("running\n")
            payload = launch.health(root, jobs, {})
            self.assertEqual(payload["total"], 4)
            self.assertEqual(payload["fit_completed"], 1)
            self.assertEqual(payload["fit_certified"], 1)
            self.assertEqual(payload["running"], 1)
            self.assertEqual(payload["pending"], 2)
            saved = json.loads((root / "status/scheduler_health.json").read_text())
            self.assertEqual(saved["left"], 3)

    def test_completed_forecast_contract_uses_canonical_retained_fit_field(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "objects").mkdir()
            (root / "forecasts").mkdir()
            (root / "status").mkdir()
            fit = root / "objects/fit_a_fit.rds"
            fit.write_bytes(b"retained fit")
            forecast_rds = root / "forecasts/forecast_a.rds"
            forecast_csv = root / "forecasts/forecast_a.csv"
            forecast_rds.write_bytes(b"forecast")
            forecast_csv.write_text("date,value\n2022-12-26,1\n")
            (root / "status/fit_a.certified").write_text("certified\n")
            job = {"dependencies": ["fit_a"]}
            result = {
                "retained_fit": str(fit),
                "retained_fit_sha256": check.sha256(fit),
                "output_paths": f"{forecast_rds}|{forecast_csv}",
            }
            self.assertTrue(check.forecast_contract_valid(root, job, result))
            forecast_csv.unlink()
            self.assertFalse(check.forecast_contract_valid(root, job, result))


if __name__ == "__main__":
    unittest.main()
