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
    "glofas_part2_rhs_then_closeout_deferred_launch",
    "application/scripts/57_prepare_glofas_part2_rhs_then_closeout_deferred_launch.py",
)


class GlofasPart2RhsDeferredLauncherTests(unittest.TestCase):
    def test_generated_chain_script_has_expected_gates(self):
        script = launcher.render_chain_script(
            root=REPO_ROOT,
            chain_root="local_trackers/test_part2_chain",
            forecast_runtime_root=launcher.DEFAULT_FORECAST_RUNTIME_ROOT,
            ridge_runtime_root=launcher.DEFAULT_RIDGE_RUNTIME_ROOT,
            ridge_scores_path=launcher.DEFAULT_RIDGE_SCORES_PATH,
            rhs_run_label=launcher.DEFAULT_RHS_RUN_LABEL,
            base_config=launcher.DEFAULT_BASE_CONFIG,
            top_n=50,
            workers=20,
            poll_seconds=60,
            tau0_reference_values="1",
            tau0_discrepancy_values="1,0.1,0.01,0.001",
            max_iter=100,
            min_iter=30,
            tol="1e-4",
        )
        self.assertIn("part1_forecasts_done", script)
        self.assertIn("FORECAST_RUNTIME_ROOT", script)
        self.assertIn("42_check_glofas_normal_part2_ridge_screen.R", script)
        self.assertIn("52_prepare_glofas_normal_part2_rhs_vb.R", script)
        self.assertIn("--ridge_scores_path", script)
        self.assertIn("combined_part2_ridge_scores_latest.csv", script)
        self.assertIn("56_launch_glofas_normal_part2_rhs_vb.R", script)
        self.assertIn("55_check_glofas_normal_part2_rhs_vb.R", script)
        self.assertIn("MIN_RHS_FREE_CORES=20", script)
        self.assertIn("GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH", script)
        self.assertIn("manual hold: not launching RHS/closeout after Part 1 forecasts", script)
        self.assertIn("waiting for Part 1 forecasts", script)
        self.assertIn("TAU0_REFERENCE_VALUES=1", script)
        self.assertIn("TAU0_DISCREPANCY_VALUES=1,0.1,0.01,0.001", script)
        self.assertIn('"normal_rhs_bridge_forecast"', script)
        self.assertIn('"blocked_missing_part2_independent_quantile_bridge_runner"', script)
        self.assertNotIn(
            "/data/jaguir26/local/src/Article-Q-DESN/application",
            script,
        )

    def test_prepare_writes_ignored_chain_bundle(self):
        local_trackers = REPO_ROOT / "local_trackers"
        local_trackers.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=str(local_trackers)) as tmp:
            chain_root = str(Path(tmp).relative_to(REPO_ROOT))
            args = launcher.parse_args(
                [
                    "--chain-root",
                    chain_root,
                    "--forecast-runtime-root",
                    launcher.DEFAULT_FORECAST_RUNTIME_ROOT,
                    "--ridge-runtime-root",
                    launcher.DEFAULT_RIDGE_RUNTIME_ROOT,
                    "--ridge-scores-path",
                    launcher.DEFAULT_RIDGE_SCORES_PATH,
                    "--rhs-run-label",
                    "glofas_part2_rhs_chain_test",
                    "--top-n",
                    "50",
                    "--workers",
                    "20",
                    "--poll-seconds",
                    "60",
                ]
            )
            result = launcher.prepare(args)
            script_path = Path(result["script"])
            metadata_path = Path(result["metadata"])
            self.assertTrue(script_path.is_file())
            self.assertTrue(metadata_path.is_file())
            with open(str(metadata_path), encoding="utf-8") as handle:
                metadata = json.load(handle)
            self.assertEqual(metadata["top_n"], 50)
            self.assertEqual(metadata["workers"], 20)
            self.assertEqual(metadata["max_iter"], 100)
            self.assertEqual(metadata["min_iter"], 30)
            self.assertEqual(metadata["forecast_runtime_root"], launcher.DEFAULT_FORECAST_RUNTIME_ROOT)
            self.assertEqual(metadata["ridge_scores_path"], launcher.DEFAULT_RIDGE_SCORES_PATH)
            self.assertTrue(metadata["fail_closed_post_rhs"])
            self.assertTrue(metadata["manual_autolaunch_required"])
            self.assertEqual(
                metadata["manual_autolaunch_env"],
                "GLOFAS_ALLOW_PART2_RHS_AUTOLAUNCH=1",
            )
            subprocess.check_call(["bash", "-n", str(script_path)])

    def test_path_guard_rejects_external_paths(self):
        with self.assertRaisesRegex(ValueError, "escapes repository root"):
            launcher.require_repo_relative("/tmp/not_this_repo", REPO_ROOT)
        with self.assertRaisesRegex(ValueError, "may not contain"):
            launcher.require_repo_relative("../outside", REPO_ROOT)


if __name__ == "__main__":
    unittest.main()
