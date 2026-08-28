import importlib.util
import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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
cpu_selector = load_script_module(
    "glofas_select_free_cpus",
    "application/scripts/glofas_select_free_cpus.py",
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
            "warm_start_numerical_certificate": "",
            "warm_start_numerical_certificate_sha256": "",
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

    def test_scheduler_canonicalizes_r_style_boolean_values(self):
        self.assertEqual(scheduler.canonical_bool("TRUE"), "true")
        self.assertEqual(scheduler.canonical_bool("FALSE"), "false")
        with self.assertRaisesRegex(ValueError, "Invalid boolean value"):
            scheduler.canonical_bool("maybe")

    def test_scheduler_builds_disjoint_cpu_sets(self):
        self.assertEqual(
            scheduler.build_cpu_sets("0,1,2,3", "", 2),
            [[0, 1], [2, 3]],
        )
        self.assertEqual(
            scheduler.build_cpu_sets("", "0,4;1,5", 2),
            [[0, 4], [1, 5]],
        )
        with self.assertRaisesRegex(ValueError, "disjoint"):
            scheduler.build_cpu_sets("", "0,1;1,2", 2)

    def test_scheduler_spreads_auto_physical_cores(self):
        fixture = """# CPU,CORE,SOCKET,NODE,ONLINE
0,0,0,0,Y
1,1,1,1,Y
2,2,0,0,Y
3,3,1,1,Y
4,0,0,0,Y
5,1,1,1,Y
"""
        with mock.patch.object(scheduler.subprocess, "check_output", return_value=fixture), \
                mock.patch.object(scheduler.os, "sched_getaffinity", return_value=set(range(6))):
            self.assertEqual(scheduler.discover_physical_cpus(), [0, 1, 2, 3])

    def test_cpu_selector_collapses_hyperthread_siblings(self):
        fixture = """# CPU,CORE,SOCKET,NODE,ONLINE
0,0,0,0,Y
1,1,0,0,Y
32,0,0,0,Y
33,1,0,0,Y
"""
        with mock.patch.object(
            cpu_selector.subprocess,
            "check_output",
            return_value=fixture,
        ), mock.patch.object(
            cpu_selector.os,
            "sched_getaffinity",
            return_value={0, 1, 32, 33},
        ):
            representatives, mapping = cpu_selector.cpu_topology()
        self.assertEqual(representatives, [0, 1])
        self.assertEqual(mapping[32], 0)
        self.assertEqual(mapping[33], 1)

    def test_scheduler_memory_calibration_limits_parallelism(self):
        safe, limit = scheduler.memory_safe_parallel_jobs(
            max_parallel=20,
            available_gb=100,
            campaign_rss_gb=20,
            memory_reserve_gb=40,
            peak_per_fit_gb=10,
            calibration_ready=True,
            calibration_target=4,
        )
        self.assertEqual((safe, limit), (8, 8))
        safe, limit = scheduler.memory_safe_parallel_jobs(
            max_parallel=20,
            available_gb=100,
            campaign_rss_gb=0,
            memory_reserve_gb=40,
            peak_per_fit_gb=0,
            calibration_ready=False,
            calibration_target=4,
        )
        self.assertEqual((safe, limit), (4, 4))

    def test_scheduler_reads_latest_logged_vb_iteration(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "worker.log"
            path.write_text(
                "[latent-path VB] iter=3 step=theta elapsed=1\n"
                "[latent-path VB] iter=11 step=theta elapsed=1\n",
                encoding="utf-8",
            )
            self.assertEqual(scheduler.max_logged_iteration(path), 11)

    def test_scheduler_process_tree_rss_uses_one_snapshot(self):
        snapshot = (
            {10: [11, 12], 11: [13]},
            {10: 1024, 11: 2048, 12: 3072, 13: 4096},
        )
        self.assertAlmostEqual(
            scheduler.process_tree_rss_gb(10, snapshot),
            10 / 1024,
        )

    def test_reference_feature_cache_must_remain_in_owned_output_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "runtime"
            cache_root = output_root / "cache" / "reference_features"
            self.assertEqual(
                scheduler.resolve_reference_feature_cache_root(
                    cache_root, output_root
                ),
                str(cache_root.resolve()),
            )
            with self.assertRaisesRegex(ValueError, "escapes its owned runtime root"):
                scheduler.resolve_reference_feature_cache_root(
                    Path(tmp).parent / "outside", output_root
                )

    def test_valid_checkpoint_requires_matching_sidecar_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkpoint = Path(tmp) / "fit.checkpoint.rds"
            checkpoint.write_bytes(b"checkpoint")
            digest = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
            Path(str(checkpoint) + ".sha256").write_text(digest + "\n", encoding="utf-8")
            self.assertTrue(scheduler.checkpoint_valid({"checkpoint_path": str(checkpoint)}))
            checkpoint.write_bytes(b"changed")
            self.assertFalse(scheduler.checkpoint_valid({"checkpoint_path": str(checkpoint)}))

    def test_checkpoint_resume_requires_enabled_valid_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkpoint = Path(tmp) / "fit.checkpoint.rds"
            row = {
                "checkpoint_resume_enabled": "true",
                "checkpoint_path": str(checkpoint),
            }
            self.assertFalse(scheduler.checkpoint_resume_requested(row))
            checkpoint.write_bytes(b"checkpoint")
            digest = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
            Path(str(checkpoint) + ".sha256").write_text(
                digest + "\n", encoding="utf-8"
            )
            self.assertTrue(scheduler.checkpoint_resume_requested(row))
            row["checkpoint_resume_enabled"] = "false"
            self.assertFalse(scheduler.checkpoint_resume_requested(row))

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

    def test_health_recognizes_terminal_reservoir_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "runtime"
            run_dir = output_root / "runs" / "candidate_run"
            log_path = output_root / "logs" / "candidate.log"
            run_dir.mkdir(parents=True)
            (run_dir / ".reservoir_preflight_rejected").write_text(
                "rejected\n",
                encoding="utf-8",
            )
            row = {
                "candidate_id": "candidate",
                "run_dir": str(run_dir),
                "log_path": str(log_path),
            }
            status, live = health.reconcile_status(row, {}, {})
            self.assertEqual(status, "rejected")
            self.assertFalse(live)

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

    def test_retry_failed_selects_only_failed_unfinished_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "runtime"
            rows = []
            template = self.make_manifest_row(tmp)
            for candidate_id in ("failed", "unknown", "completed", "rejected"):
                row = dict(template)
                row.update({
                    "candidate_id": candidate_id,
                    "priority": str(len(rows) + 1),
                    "run_id": f"{candidate_id}_run",
                    "run_dir": str(output_root / "runs" / f"{candidate_id}_run"),
                    "log_path": str(output_root / "logs" / f"{candidate_id}.log"),
                })
                Path(row["run_dir"]).mkdir(parents=True)
                rows.append(row)
            status_dir = output_root / "status"
            status_dir.mkdir(parents=True)
            (status_dir / "failed.csv").write_text(
                "candidate_id,status,timestamp,pid,exit_code\n"
                "failed,failed,2026-08-23T00:00:00+00:00,999999999,1\n",
                encoding="utf-8",
            )
            (Path(rows[2]["run_dir"]) / ".fit_recovery_complete").write_text(
                "complete\n", encoding="utf-8"
            )
            (Path(rows[3]["run_dir"]) / ".reservoir_preflight_rejected").write_text(
                "rejected\n", encoding="utf-8"
            )

            states = {
                row["candidate_id"]: scheduler.reconcile_existing_candidate(
                    row, output_root, {}, retry_failed=True
                )["status"]
                for row in rows
            }
            self.assertEqual(states["failed"], "pending")
            self.assertEqual(states["unknown"], "excluded_from_failed_retry")
            self.assertEqual(states["completed"], "completed_existing")
            self.assertEqual(states["rejected"], "rejected_existing")

    def test_manifest_integrity_accepts_owned_hashed_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            scheduler.validate_manifest([row], Path(tmp), [0], 1)

    def test_manifest_integrity_hashes_shared_warm_source_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            warm_fit = Path(tmp) / "source_fit.rds"
            warm_fit.write_bytes(b"shared warm-start fixture")
            warm_hash = hashlib.sha256(warm_fit.read_bytes()).hexdigest()
            row.update({
                "warm_start_source_fit_object": str(warm_fit),
                "warm_start_source_sha256": warm_hash,
            })
            second = dict(row)
            second.update({
                "candidate_id": "candidate_second",
                "priority": "2",
                "run_id": "candidate_second_run",
                "run_dir": str(Path(tmp) / "runs" / "candidate_second_run"),
                "log_path": str(Path(tmp) / "logs" / "candidate_second.log"),
            })
            with mock.patch.object(
                scheduler,
                "sha256_file",
                wraps=scheduler.sha256_file,
            ) as digest:
                scheduler.validate_manifest([row, second], Path(tmp), [0], 1)
            self.assertEqual(digest.call_count, 3)

    def test_manifest_integrity_hashes_owned_numerical_certificate_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            certificate = Path(tmp) / "warm_start_certificate.rds"
            certificate.write_bytes(b"numerical certificate fixture")
            certificate_hash = hashlib.sha256(certificate.read_bytes()).hexdigest()
            row.update({
                "warm_start_numerical_certificate": str(certificate),
                "warm_start_numerical_certificate_sha256": certificate_hash,
            })
            second = dict(row)
            second.update({
                "candidate_id": "candidate_second",
                "priority": "2",
                "run_id": "candidate_second_run",
                "run_dir": str(Path(tmp) / "runs" / "candidate_second_run"),
                "log_path": str(Path(tmp) / "logs" / "candidate_second.log"),
            })
            with mock.patch.object(
                scheduler,
                "sha256_file",
                wraps=scheduler.sha256_file,
            ) as digest:
                scheduler.validate_manifest([row, second], Path(tmp), [0], 1)
            self.assertEqual(digest.call_count, 3)

            certificate.write_bytes(b"changed certificate")
            with self.assertRaisesRegex(
                ValueError,
                "certificate hash changed",
            ):
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

    def test_manifest_integrity_requires_owned_checkpoint_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            run_dir = Path(row["run_dir"])
            row.update({
                "checkpoint_resume_enabled": "true",
                "checkpoint_path": str(run_dir / "objects" / "fit.checkpoint.rds"),
            })
            scheduler.validate_manifest([row], Path(tmp), [0], 1)
            row["checkpoint_path"] = str(Path(tmp) / "runs" / "other" / "fit.rds")
            with self.assertRaisesRegex(ValueError, "Checkpoint path escapes"):
                scheduler.validate_manifest([row], Path(tmp), [0], 1)

    def test_manifest_integrity_rejects_resume_without_checkpoint_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            row["checkpoint_resume_enabled"] = "true"
            with self.assertRaisesRegex(ValueError, "enabled without a path"):
                scheduler.validate_manifest([row], Path(tmp), [0], 1)

    def test_manifest_integrity_checks_owned_preflight_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            row = self.make_manifest_row(tmp)
            row.update({
                "reservoir_preflight_enabled": "true",
                "reservoir_preflight_run_id": "candidate_preflight",
                "reservoir_preflight_summary_path": str(
                    Path(tmp) / "runs" / "candidate_preflight" / "tables" / "summary.csv"
                ),
            })
            scheduler.validate_manifest([row], Path(tmp), [0], 1)
            row["reservoir_preflight_summary_path"] = str(Path(tmp).parent / "outside.csv")
            with self.assertRaisesRegex(ValueError, "escapes its owned runtime root"):
                scheduler.validate_manifest([row], Path(tmp), [0], 1)


if __name__ == "__main__":
    unittest.main()
