import csv
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_script_module(name, relative_path):
    path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


launcher = load_script_module(
    "glofas_part1_deliverable_deferred_launch",
    "application/scripts/46_prepare_glofas_part1_deliverable_deferred_launch.py",
)


class GlofasPart1DeliverableDeferredLauncherTests(unittest.TestCase):
    def test_manifest_has_requested_18_one_core_slots(self):
        rows = launcher.build_job_manifest(
            root=REPO_ROOT,
            runtime_root="local_trackers/test_deferred_launcher",
            config_path=launcher.DEFAULT_CONFIG,
            score_path=launcher.DEFAULT_SCORE_PATH,
            seed=20260903,
            n_draws=500,
            horizon_days=30,
        )
        self.assertEqual(len(rows), 18)
        self.assertEqual(sum(int(row["core_slots"]) for row in rows), 18)
        self.assertEqual(sum(row["launch_status"] == "ready" for row in rows), 0)
        self.assertEqual(
            sum(row["launch_status"] == "blocked_manual_hold" for row in rows),
            18,
        )
        self.assertEqual(rows[0]["job_id"], "normal_ridge")
        self.assertEqual(rows[1]["job_id"], "normal_rhs_vb")
        self.assertEqual(rows[0]["command"], "")
        self.assertIn("blocked_manual_hold", rows[0]["block_reason"])

    def test_manifest_can_be_explicitly_armed_for_manual_forecast_use(self):
        rows = launcher.build_job_manifest(
            root=REPO_ROOT,
            runtime_root="local_trackers/test_deferred_launcher",
            config_path=launcher.DEFAULT_CONFIG,
            score_path=launcher.DEFAULT_SCORE_PATH,
            seed=20260903,
            n_draws=500,
            horizon_days=30,
            enable_forecast_jobs=True,
        )
        self.assertEqual(sum(row["launch_status"] == "ready" for row in rows), 16)
        self.assertEqual(
            sum(row["launch_status"] == "blocked_missing_scalable_joint_backend" for row in rows),
            2,
        )
        self.assertIn("--method ridge", rows[0]["command"])
        self.assertIn("--method rhs", rows[1]["command"])
        self.assertIn("--fit_object_path", rows[1]["command"])
        self.assertIn("--forecast_backend auto", rows[1]["command"])
        quantile_commands = [row["command"] for row in rows if row["job_family"] == "independent_quantile"]
        self.assertEqual(len(quantile_commands), 14)
        self.assertTrue(all("63_run_glofas_part1_quantile_oracle_forecast.R" in cmd for cmd in quantile_commands))
        self.assertTrue(all("synthesize" not in cmd.lower() for cmd in quantile_commands))

    def test_manifest_contains_the_expected_quantile_deliverables(self):
        rows = launcher.build_job_manifest(
            root=REPO_ROOT,
            runtime_root="local_trackers/test_deferred_launcher",
            config_path=launcher.DEFAULT_CONFIG,
            score_path=launcher.DEFAULT_SCORE_PATH,
            seed=20260903,
            n_draws=500,
            horizon_days=30,
        )
        independent_al = [
            row["quantile"]
            for row in rows
            if row["job_family"] == "independent_quantile"
            and row["likelihood"] == "AL"
        ]
        independent_exal = [
            row["quantile"]
            for row in rows
            if row["job_family"] == "independent_quantile"
            and row["likelihood"] == "exAL"
        ]
        self.assertEqual(independent_al, list(launcher.QUANTILES))
        self.assertEqual(independent_exal, list(launcher.QUANTILES))
        self.assertEqual(
            [(row["job_family"], row["likelihood"], row["quantile"]) for row in rows[-2:]],
            [("joint_quantile", "AL", "all7"), ("joint_quantile", "exAL", "all7")],
        )

    def test_prepare_writes_fail_closed_runtime_bundle(self):
        local_trackers = REPO_ROOT / "local_trackers"
        local_trackers.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=str(local_trackers)) as tmp:
            runtime_root = str(Path(tmp).relative_to(REPO_ROOT))
            args = launcher.parse_args(
                [
                    "--runtime-root",
                    runtime_root,
                    "--part2-runtime-root",
                    launcher.DEFAULT_PART2_RUNTIME_ROOT,
                    "--poll-seconds",
                    "5",
                ]
            )
            result = launcher.prepare(args)
            manifest_path = Path(result["manifest"])
            metadata_path = Path(result["metadata"])
            launch_path = Path(result["launcher"])
            self.assertTrue(manifest_path.is_file())
            self.assertTrue(metadata_path.is_file())
            self.assertTrue(launch_path.is_file())
            with open(str(metadata_path), encoding="utf-8") as handle:
                metadata = json.load(handle)
            self.assertEqual(metadata["requested_total_jobs"], 18)
            self.assertEqual(metadata["requested_total_cores"], 18)
            self.assertEqual(metadata["ready_jobs"], 0)
            self.assertEqual(metadata["ready_cores"], 0)
            self.assertEqual(metadata["blocked_jobs"], 18)
            self.assertTrue(metadata["manual_forecast_launch_required"])
            self.assertFalse(metadata["enable_forecast_jobs"])
            self.assertFalse(metadata["synthesis_enabled"])
            with open(str(manifest_path), newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows[0]["launch_status"], "blocked_manual_hold")
            self.assertTrue(all(row["command"] == "" for row in rows))
            script_text = launch_path.read_text(encoding="utf-8")
            self.assertIn('MIN_FREE_CORES="$need"', script_text)
            self.assertIn("GLOFAS_ALLOW_DEFERRED_FORECAST_LAUNCH", script_text)
            self.assertIn("42_check_glofas_normal_part2_ridge_screen.R", script_text)
            self.assertIn("bundle_ready", script_text)
            self.assertNotIn("synthesize", script_text.lower())
            self.assertNotIn(
                "/data/jaguir26/local/src/Article-Q-DESN/application",
                script_text,
            )
            subprocess.check_call(["bash", "-n", str(launch_path)])

    def test_enabled_bundle_has_no_synthesis_and_joint_rows_fail_closed(self):
        local_trackers = REPO_ROOT / "local_trackers"
        local_trackers.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=str(local_trackers)) as tmp:
            runtime_root = str(Path(tmp).relative_to(REPO_ROOT))
            args = launcher.parse_args(
                [
                    "--runtime-root",
                    runtime_root,
                    "--part2-runtime-root",
                    launcher.DEFAULT_PART2_RUNTIME_ROOT,
                    "--enable-forecast-jobs",
                    "--poll-seconds",
                    "5",
                ]
            )
            result = launcher.prepare(args)
            with open(result["manifest"], newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(sum(row["launch_status"] == "ready" for row in rows), 16)
            self.assertEqual(sum(row["launch_status"] != "ready" for row in rows), 2)
            self.assertTrue(all("synthesize" not in row["command"].lower() for row in rows))
            self.assertTrue(all("10_synthesize_glofas_quantile_runs.R" not in row["command"] for row in rows))
            blocked = [row for row in rows if row["launch_status"] != "ready"]
            self.assertEqual({row["job_family"] for row in blocked}, {"joint_quantile"})
            with open(result["metadata"], encoding="utf-8") as handle:
                metadata = json.load(handle)
            self.assertEqual(metadata["ready_jobs"], 16)
            self.assertEqual(metadata["ready_cores"], 16)
            self.assertFalse(metadata["synthesis_enabled"])

    def test_path_guard_rejects_paths_outside_repo(self):
        with self.assertRaisesRegex(ValueError, "escapes repository root"):
            launcher.require_repo_relative("/tmp/not_this_repo", REPO_ROOT)
        with self.assertRaisesRegex(ValueError, "may not contain"):
            launcher.require_repo_relative("../outside", REPO_ROOT)


if __name__ == "__main__":
    unittest.main()
