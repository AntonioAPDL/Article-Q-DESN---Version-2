"""No production jobs: test the frozen DAG and process resource contract."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/launch_glofas_unit_member_correction.py"
spec = importlib.util.spec_from_file_location("unit_member_launcher", SCRIPT)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class UnitMemberSchedulerTests(unittest.TestCase):
    def jobs(self):
        return [{"run_id": f"fit_{i}", "dependencies": "" if i == 0 else f"fit_{i-1}",
            "worker_slots": "1", "target_schema": "glofas_unit_member_part4_v1"} for i in range(18)]

    def test_complete_bounded_dag(self):
        launcher.validate_jobs(self.jobs())

    def test_wrong_count(self):
        with self.assertRaises(ValueError):
            launcher.validate_jobs(self.jobs()[:-1])

    def test_duplicate(self):
        jobs = self.jobs()
        jobs[-1]["run_id"] = jobs[0]["run_id"]
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_unknown_dependency(self):
        jobs = self.jobs()
        jobs[-1]["dependencies"] = "not_owned"
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_cycle(self):
        jobs = self.jobs()
        jobs[0]["dependencies"] = jobs[-1]["run_id"]
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_inner_parallelism_not_multiplied(self):
        jobs = self.jobs()
        jobs[-1]["worker_slots"] = "7"
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_legacy_target_rejected(self):
        jobs = self.jobs()
        jobs[-1]["target_schema"] = "legacy"
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_cpu_scope(self):
        self.assertEqual(launcher.CPU_POOL, tuple(range(48, 56)))
        self.assertEqual(len(launcher.CPU_POOL), 8)
        self.assertTrue(all(x == "1" for x in launcher.THREAD_ENV.values()))

    def test_job_path_injection_rejected(self):
        jobs = self.jobs()
        jobs[-1]["run_id"] = "../other_lane"
        with self.assertRaises(ValueError):
            launcher.validate_jobs(jobs)

    def test_clean_commit_change_is_rejected(self):
        with patch.object(launcher, "git", side_effect=["", "different_clean_head"]):
            with self.assertRaises(RuntimeError):
                launcher.assert_source_unchanged("frozen_head")

    def test_dirty_source_is_rejected(self):
        with patch.object(launcher, "git", return_value=" M application/R/model.R"):
            with self.assertRaises(RuntimeError):
                launcher.assert_source_unchanged("frozen_head")

    def test_unchanged_source_is_accepted(self):
        with patch.object(launcher, "git", side_effect=["", "frozen_head"]):
            launcher.assert_source_unchanged("frozen_head")


if __name__ == "__main__":
    unittest.main()
