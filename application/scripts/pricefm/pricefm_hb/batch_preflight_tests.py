"""Negative boundary tests: no network or real runtime execution."""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import resource
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("preflight", Path(__file__).with_name("batch_preflight.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class PreflightTests(unittest.TestCase):
    def test_python_R_submission_and_shell_injection_are_not_login_operations(self):
        for command in (("python3", "-c", "pass"), ("Rscript", "x.R"),
                        ("sbatch", "job.sh"), ("bash", "-lc", "module avail r; python3 x.py")):
            with self.assertRaises(ValueError):
                m.login_argv({}, "R_modules", command)

    def test_policy_requires_compute_and_preserves_original_caps(self):
        valid = dict(placement="SLURM_COMPUTE", nodes=1, tasks=1, cpus_per_task=1,
                     threads=1, memory_MiB=8192, requeue=False, login_fallback=False,
                     wall_seconds=600, aggregate_CPU_seconds=300,
                     scientific_data_access=False, optimizer_invocations=0)
        self.assertFalse(m.qualify_compute_policy(valid)["submission_authorized"])
        for key, value in (("placement", "LOGIN"), ("threads", 2), ("cpus_per_task", 2),
                           ("cpus_per_task", True), ("memory_MiB", 8192.0),
                           ("memory_MiB", 16384), ("requeue", True), ("login_fallback", True),
                           ("wall_seconds", 1201), ("aggregate_CPU_seconds", 601),
                           ("scientific_data_access", True), ("optimizer_invocations", 1)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                m.qualify_compute_policy(dict(valid, **{key: value}))
        with self.assertRaises(ValueError):
            m.qualify_compute_policy(dict(valid, optimizer_invocations=False))

    def test_input_pin_drift_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "a.json"
            p.write_text('{"a":1}')
            v = m.pin(p)
            p.write_text('{"a":2}')
            with self.assertRaises(ValueError):
                m.read(v)
            q = Path(name) / "link.json"
            q.symlink_to(p)
            with self.assertRaises(ValueError):
                m.pin(q)

    def test_verified_read_has_no_second_path_read_and_rejects_ambiguous_JSON(self):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "a.json"
            p.write_text('{"a":1}')
            v = m.pin(p)
            with patch.object(Path, "read_text", side_effect=AssertionError("second path open")):
                self.assertEqual(m.read(v), {"a": 1})
            for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":1e999}'):
                p.write_text(raw)
                with self.assertRaises(ValueError):
                    m.read(m.pin(p))

    def test_scope_rejects_wrong_role_expiry_and_unscoped_output(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            p = root / "scope.json"
            good = dict(status="PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                        issued_epoch=time.time()-1, expires_epoch=time.time()+100,
                        allowed_metadata_output_root=str(root))
            p.write_text(json.dumps(good))
            m.scope_check(m.pin(p), root / "child")
            with self.assertRaises(ValueError):
                m.scope_check(m.pin(p), root.parent / "elsewhere")
            for bad in (dict(good, status="OLD_SCOPE"), dict(good, expires_epoch=1)):
                p.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    m.scope_check(m.pin(p), root / "child")

    def test_site_scope_never_accepts_another_host_or_weak_credentials(self):
        with self.assertRaises(ValueError):
            m.site_ssh(dict(host="elsewhere", user="jaguir26", account="128x24",
                            partition="128x24", qos="normal"))

    def test_intent_is_exclusive_no_client_retry(self):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "intent.json"
            m.write(p, {"status": "intent"})
            with self.assertRaises(FileExistsError):
                m.write(p, {"status": "success"})
            self.assertEqual(json.loads(p.read_text())["status"], "intent")

    def test_prepare_and_same_PID_execution_intent_are_one_shot(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            for label in ("key", "hosts"):
                (root / label).write_text("owned-test-fixture-not-a-credential")
            site = dict(host="hb.ucsc.edu", user="jaguir26", account="128x24",
                        partition="128x24", qos="normal",
                        known_hosts_file=str(root / "hosts"), ssh_identity_file=str(root / "key"))
            scope = dict(status="PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                         issued_epoch=time.time()-1, expires_epoch=time.time()+200,
                         allowed_metadata_output_root=str(root))
            for label, value in (("site.json", site), ("scope.json", scope)):
                (root / label).write_text(json.dumps(value))
            out = root / "run"
            supervisor = Path(__file__).with_name("profile_supervisor.py")
            prepared = m.prepare(m.pin(root / "site.json"), m.pin(root / "scope.json"),
                                 out, m.pin(supervisor))
            self.assertEqual(len(prepared["plans"]), 5)
            with self.assertRaises(FileExistsError):
                m.prepare(m.pin(root / "site.json"), m.pin(root / "scope.json"), out, m.pin(supervisor))
            with patch.object(m, "execution_context", return_value={"pid": 123, "start_ticks": 456}), \
                 patch.object(m.os, "execvp", side_effect=RuntimeError("unit-fixture exec intercepted")) as executed:
                with self.assertRaisesRegex(RuntimeError, "unit-fixture"):
                    m.execute(prepared["plans"][0])
                with self.assertRaises(FileExistsError):
                    m.execute(prepared["plans"][0])
                self.assertEqual(executed.call_count, 1)
            self.assertFalse((out / "RESULT.json").exists())

    def test_wrong_supervisor_never_produces_prepare_intent(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "scope.json").write_text(json.dumps(dict(
                status="PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                issued_epoch=time.time()-1, expires_epoch=time.time()+200,
                allowed_metadata_output_root=str(root))))
            (root / "site.json").write_text("{}")
            (root / "fake.py").write_text("# not the approved supervisor")
            with self.assertRaises(ValueError):
                m.prepare(m.pin(root / "site.json"), m.pin(root / "scope.json"),
                          root / "run", m.pin(root / "fake.py"))
            self.assertFalse((root / "run").exists())

    def test_guard_rejects_negative_nonfinite_boolean_and_forced_stop_fields(self):
        valid = dict(returncode=0, command_returncode=0, all_owned_descendants_reaped=True,
                     kernel_escape_filter=True, independent_guardian=True, CPU_limit=4,
                     aggregate_CPU_seconds=.5, complete_lifecycle_wall_seconds=1.0,
                     cap_reason=None, guardian_forced_monitor_stop=False, stdout="", stderr="")
        m.validate_operation_guard(valid)
        for key, value in (("aggregate_CPU_seconds", -1), ("aggregate_CPU_seconds", False),
                           ("aggregate_CPU_seconds", float("inf")), ("complete_lifecycle_wall_seconds", -1),
                           ("complete_lifecycle_wall_seconds", False), ("returncode", False),
                           ("CPU_limit", 4.0), ("cap_reason", "CPU_BOUNDARY"),
                           ("guardian_forced_monitor_stop", True)):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                m.validate_operation_guard(dict(valid, **{key: value}))

    def test_actual_CLI_respects_inherited_four_CPU_hard_limit(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            for label in ("key", "hosts"):
                (root / label).write_text("owned-unit-fixture")
            (root / "site.json").write_text(json.dumps(dict(
                host="hb.ucsc.edu", user="jaguir26", account="128x24", partition="128x24",
                qos="normal", known_hosts_file=str(root / "hosts"), ssh_identity_file=str(root / "key"))))
            (root / "scope.json").write_text(json.dumps(dict(
                status="PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                issued_epoch=time.time()-1, expires_epoch=time.time()+200,
                allowed_metadata_output_root=str(root))))
            argv = [sys.executable, "-B", str(Path(m.__file__)), "--action", "prepare",
                    "--site", str(root / "site.json"), "--scope", str(root / "scope.json"),
                    "--output", str(root / "run"), "--supervisor",
                    str(Path(__file__).with_name("profile_supervisor.py"))]
            def inherited_limit():
                resource.setrlimit(resource.RLIMIT_CPU, (4, 4))
            run = subprocess.run(argv, capture_output=True, text=True, timeout=10,
                                 preexec_fn=inherited_limit)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(json.loads(run.stdout)["status"],
                             "PREPARED_FIVE_NATIVE_OPERATIONS_NOT_EXECUTED")

if __name__ == "__main__":
    unittest.main()
