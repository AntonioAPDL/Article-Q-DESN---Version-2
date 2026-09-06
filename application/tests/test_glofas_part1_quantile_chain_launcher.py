import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_script_module(name, relative_path):
    path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


launcher = load_script_module(
    "glofas_part1_quantile_chain_launcher",
    "application/scripts/64_prepare_glofas_part1_quantile_chain_launcher.py",
)


class GlofasPart1QuantileChainLauncherTests(unittest.TestCase):
    def test_manifest_encodes_requested_quantile_dependency_graph(self):
        rows = launcher.build_manifest(
            root=REPO_ROOT,
            runtime_root="local_trackers/test_quantile_chain",
            config_path=launcher.DEFAULT_CONFIG,
            score_path=launcher.DEFAULT_SCORE_PATH,
            normal_rhs_fit=launcher.DEFAULT_NORMAL_RHS_FIT,
            max_iter=100,
            min_iter=30,
            tol=0.01,
            tau0=1.0,
            max_parallel=20,
            max_dense_dim=4000,
            rhs_vb_inner=5,
            horizon_days=30,
            session_prefix="test_chain",
        )
        by_id = {row["job_id"]: row for row in rows}
        self.assertEqual(len(rows), 16)
        self.assertEqual(by_id["independent_al_0p50"]["depends_on"], "")
        self.assertEqual(by_id["independent_al_0p35"]["depends_on"], "independent_al_0p50")
        self.assertEqual(by_id["independent_al_0p20"]["depends_on"], "independent_al_0p35")
        self.assertEqual(by_id["independent_al_0p05"]["depends_on"], "independent_al_0p20")
        self.assertEqual(by_id["independent_al_0p65"]["depends_on"], "independent_al_0p50")
        self.assertEqual(by_id["independent_al_0p80"]["depends_on"], "independent_al_0p65")
        self.assertEqual(by_id["independent_al_0p95"]["depends_on"], "independent_al_0p80")
        for quantile in launcher.QUANTILES:
            qslug = quantile.replace(".", "p")
            self.assertEqual(
                by_id[f"independent_exal_{qslug}"]["depends_on"],
                f"independent_al_{qslug}",
            )
        self.assertEqual(
            set(by_id["joint_al_all7"]["depends_on"].split("|")),
            {f"independent_al_{q.replace('.', 'p')}" for q in launcher.QUANTILES},
        )
        self.assertEqual(
            set(by_id["joint_exal_all7"]["depends_on"].split("|")),
            {f"independent_exal_{q.replace('.', 'p')}" for q in launcher.QUANTILES},
        )

    def test_commands_are_warm_started_and_use_fast_controls(self):
        rows = launcher.build_manifest(
            root=REPO_ROOT,
            runtime_root="local_trackers/test_quantile_chain",
            config_path=launcher.DEFAULT_CONFIG,
            score_path=launcher.DEFAULT_SCORE_PATH,
            normal_rhs_fit=launcher.DEFAULT_NORMAL_RHS_FIT,
            max_iter=100,
            min_iter=30,
            tol=0.01,
            tau0=1.0,
            max_parallel=20,
            max_dense_dim=4000,
            rhs_vb_inner=5,
            horizon_days=30,
            session_prefix="test_chain",
        )
        by_id = {row["job_id"]: row for row in rows}
        for row in rows:
            self.assertEqual(row["core_slots"], "1")
            self.assertIn("--max_iter 100", row["command"])
            self.assertIn("--tol 0.01", row["command"])
            self.assertIn("--min_iter 30", row["command"])
            self.assertIn("--progress_every 1", row["command"])
            self.assertNotIn("synthesize", row["command"].lower())
        self.assertIn(launcher.DEFAULT_NORMAL_RHS_FIT, by_id["independent_al_0p50"]["init_fit_path"])
        self.assertIn("--init_fit_path", by_id["independent_exal_0p50"]["command"])
        self.assertIn("independent_al_0p50", by_id["independent_exal_0p50"]["init_fit_path"])
        self.assertIn("--init_fit_paths", by_id["joint_al_all7"]["command"])
        self.assertIn("--joint_backend blockmf", by_id["joint_al_all7"]["command"])
        self.assertIn("--joint_backend blockmf", by_id["joint_exal_all7"]["command"])

    def test_prepare_writes_runtime_bundle_and_valid_launch_script(self):
        local_trackers = REPO_ROOT / "local_trackers"
        local_trackers.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=str(local_trackers)) as tmp:
            runtime_root = str(Path(tmp).relative_to(REPO_ROOT))
            result = launcher.prepare(
                launcher.parse_args(
                    [
                        "--runtime-root", runtime_root,
                        "--max-iter", "100",
                        "--min-iter", "30",
                        "--tol", "0.01",
                        "--poll-seconds", "5",
                    ]
                )
            )
            manifest = Path(result["manifest"])
            metadata = Path(result["metadata"])
            launch_script = Path(result["launcher"])
            self.assertTrue(manifest.is_file())
            self.assertTrue(metadata.is_file())
            self.assertTrue(launch_script.is_file())
            with open(manifest, newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 16)
            subprocess.check_call(["bash", "-n", str(launch_script)])
            text = launch_script.read_text(encoding="utf-8")
            self.assertIn("MAX_PARALLEL=20", text)
            self.assertIn("depends_on", manifest.read_text(encoding="utf-8"))
            self.assertNotIn("10_synthesize_glofas_quantile_runs.R", text)

    def test_path_guard_rejects_non_repo_paths(self):
        with self.assertRaisesRegex(ValueError, "escapes repository root"):
            launcher.require_repo_relative("/tmp/outside", REPO_ROOT)
        with self.assertRaisesRegex(ValueError, "may not contain"):
            launcher.require_repo_relative("../outside", REPO_ROOT)


if __name__ == "__main__":
    unittest.main()
