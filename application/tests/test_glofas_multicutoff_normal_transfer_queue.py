#!/usr/bin/env python3

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "application/scripts/395_launch_glofas_multicutoff_normal_transfer_queue.py"
SPEC = importlib.util.spec_from_file_location("multicutoff_queue", LAUNCHER)
queue = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(queue)


class MulticutoffNormalTransferQueueTest(unittest.TestCase):
    def test_cutoffs_are_unique_valid_and_chronological(self):
        self.assertEqual(
            queue.parse_cutoffs("2022-05-11,2021-01-23,2021-11-12"),
            ["2021-01-23", "2021-11-12", "2022-05-11"],
        )
        with self.assertRaises(ValueError):
            queue.parse_cutoffs("2021-01-23,2021-01-23")
        with self.assertRaises(ValueError):
            queue.parse_cutoffs("2021/01/23")

    def test_plan_has_one_sequential_entry_per_cutoff(self):
        with tempfile.TemporaryDirectory() as directory:
            rows = queue.build_plan(
                ["2021-01-23", "2021-11-12"],
                Path(directory),
                "glofas_normal_transfer",
                "winner_spec_20260911",
            )
        self.assertEqual([row["sequence"] for row in rows], [1, 2])
        self.assertTrue(rows[0]["run_label"].endswith("cutoff20210123_winner_spec_20260911"))
        self.assertTrue(rows[1]["runtime_root"].endswith(rows[1]["run_label"]))
        self.assertTrue(all(row["status"] == "pending" for row in rows))

    def test_prepared_runtime_requires_exact_normal_pair_and_cutoff(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory)
            (runtime / "configs").mkdir()
            (runtime / "status").mkdir()
            (runtime / "configs/part4_model_manifest.csv").write_text(
                "part4_family\nnormal_ridge_diagnostic\nnormal_rhs_vb_diagnostic\n",
                encoding="utf-8",
            )
            (runtime / "configs/cutoff.csv").write_text(
                "origin_date\n2021-01-23\n", encoding="utf-8"
            )
            queue.validate_prepared_runtime(runtime, "2021-01-23")
            with self.assertRaises(RuntimeError):
                queue.validate_prepared_runtime(runtime, "2021-11-12")


if __name__ == "__main__":
    unittest.main()
