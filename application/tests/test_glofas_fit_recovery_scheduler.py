import importlib.util
import hashlib
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
    def make_manifest_row(self, root):
        root = Path(root)
        config = root / "configs" / "candidate.yaml"
        grid = root / "configs" / "grid.csv"
        config.parent.mkdir(parents=True)
        config.write_text("value: 1\n", encoding="utf-8")
        grid.write_text("fit_id\nfit\n", encoding="utf-8")
        digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        return {
            "candidate_id": "candidate",
            "priority": "1",
            "config_path": str(config),
            "config_sha256": digest(config),
            "model_grid_path": str(grid),
            "model_grid_sha256": digest(grid),
            "run_id": "candidate_run",
            "run_dir": str(root / "runs" / "candidate_run"),
            "log_path": str(root / "logs" / "candidate.log"),
            "warm_start_source_fit_object": "",
            "warm_start_source_sha256": "",
        }

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

    def test_scheduler_retry_pending_supersedes_old_worker_failure(self):
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
            scheduler_state = {"status": "pending", "pid": ""}
            worker_state = {"status": "failed", "pid": "999999999"}
            status, live = health.reconcile_status(
                row,
                scheduler_state,
                worker_state,
            )
            self.assertEqual(status, "pending")
            self.assertFalse(live)

    def test_manifest_integrity_accepts_owned_hashed_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            scheduler.validate_manifest([row], Path(tmp), [0], 1)

    def test_manifest_integrity_rejects_changed_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            Path(row["config_path"]).write_text("value: 2\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Config hash changed"):
                scheduler.validate_manifest([row], Path(tmp), [0], 1)

    def test_manifest_integrity_rejects_unowned_run_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            row["run_dir"] = str(Path(tmp).parent / "outside")
            with self.assertRaisesRegex(ValueError, "escapes its owned runtime root"):
                scheduler.validate_manifest([row], Path(tmp), [0], 1)


if __name__ == "__main__":
    unittest.main()
