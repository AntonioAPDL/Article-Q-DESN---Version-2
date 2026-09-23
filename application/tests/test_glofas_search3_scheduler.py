from __future__ import annotations

import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


launcher = load("search3_launcher", "application/scripts/430_launch_glofas_search3.py")
controller = load("search3_controller", "application/scripts/432_run_glofas_search3_campaign.py")


class Search3SchedulerTest(unittest.TestCase):
    def test_manifest_and_thread_guards(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "configs").mkdir(); (root / "status").mkdir()
            with (root / "configs/job_manifest.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=("job_id", "memory_weight"))
                writer.writeheader(); writer.writerow({"job_id": "a", "memory_weight": 1})
            jobs = launcher.read_jobs(root)
            self.assertEqual(len(jobs), 1)
            command = launcher.command(ROOT, root, "a", "Rscript")
            self.assertIn("OMP_NUM_THREADS=1", command)
            self.assertIn("428_run_glofas_search3_worker.R", command)
            self.assertIn("429_score_glofas_search3.R", command)

    def test_stage_order_and_closeout_patterns(self):
        self.assertEqual(controller.STAGES[0], "ridge_a")
        self.assertEqual(controller.STAGES[-1], "confirmation")
        self.assertEqual(len(controller.STAGES), 6)
        self.assertIn("389_continue_glofas_part4_joint_fit.R", controller.ACTIVE_PATTERNS)
        self.assertIn("423_run_glofas_quantile_certification_continuation.R", controller.ACTIVE_PATTERNS)


if __name__ == "__main__":
    unittest.main()
