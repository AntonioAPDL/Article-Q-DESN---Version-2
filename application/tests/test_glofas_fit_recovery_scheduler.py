import importlib.util
import os
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


scheduler = load_script_module(
    "glofas_fit_recovery_scheduler",
    "application/scripts/glofas_fit_recovery_scheduler.py",
)
health = load_script_module(
    "glofas_fit_recovery_health",
    "application/scripts/glofas_fit_recovery_health.py",
)


class GlofasFitRecoverySchedulerTests(unittest.TestCase):
    def test_scheduler_state_roundtrip_is_priority_ordered(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "state.csv"
            rows = [
                {"candidate_id": "second", "priority": "2", "status": "pending"},
                {"candidate_id": "first", "priority": "1", "status": "pending"},
            ]
            scheduler.atomic_csv(path, rows, list(rows[0]))
            observed = scheduler.read_manifest(path)
            self.assertEqual(
                [row["candidate_id"] for row in observed],
                ["first", "second"],
            )

    def test_pid_liveness_uses_explicit_process_identity(self):
        self.assertTrue(scheduler.pid_alive(str(os.getpid())))
        self.assertTrue(health.pid_alive(str(os.getpid())))
        self.assertFalse(scheduler.pid_alive("not-a-pid"))

    def test_absolute_runtime_config_can_be_made_repo_relative(self):
        config = REPO_ROOT / "local_trackers" / "runtime" / "config.yaml"
        self.assertEqual(
            str(config.relative_to(REPO_ROOT)),
            "local_trackers/runtime/config.yaml",
        )

    def test_health_reconciles_completed_run_from_marker_and_score(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "runtime"
            run_dir = output_root / "runs" / "candidate_run"
            log_path = output_root / "logs" / "candidate.log"
            score_path = (
                output_root / "scores" / "candidate_observed_fit_scores.csv"
            )
            run_dir.mkdir(parents=True)
            log_path.parent.mkdir(parents=True)
            score_path.parent.mkdir(parents=True)
            (run_dir / ".fit_recovery_complete").write_text(
                "complete\n",
                encoding="utf-8",
            )
            score_path.write_text(
                "candidate_id,window\ncandidate,all\n",
                encoding="utf-8",
            )
            row = {
                "candidate_id": "candidate",
                "run_dir": str(run_dir),
                "log_path": str(log_path),
            }
            status, live = health.reconcile_status(row, {}, {})
            self.assertEqual(status, "completed")
            self.assertFalse(live)

    def test_health_recognizes_scheduler_restart_worker(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "runtime"
            run_dir = output_root / "runs" / "candidate_run"
            log_path = output_root / "logs" / "candidate.log"
            run_dir.mkdir(parents=True)
            row = {
                "candidate_id": "candidate",
                "run_dir": str(run_dir),
                "log_path": str(log_path),
            }
            scheduler_state = {
                "status": "running_external",
                "pid": str(os.getpid()),
            }
            worker_state = {"status": "running", "pid": str(os.getpid())}
            status, live = health.reconcile_status(
                row,
                scheduler_state,
                worker_state,
            )
            self.assertEqual(status, "running")
            self.assertTrue(live)


if __name__ == "__main__":
    unittest.main()
