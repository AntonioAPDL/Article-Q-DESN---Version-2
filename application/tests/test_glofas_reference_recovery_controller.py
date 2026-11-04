#!/usr/bin/env python3.11
"""Generated tiny process fixtures only: no scientific data or R invocation."""
import importlib.util
import csv
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "scripts/run_glofas_reference_recovery.py"
spec = importlib.util.spec_from_file_location("recovery_controller", CONTROLLER)
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def until(predicate, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError("generated fixture did not reach expected state")


class ControllerTests(unittest.TestCase):
    def test_atomic_write_is_complete_before_publication_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "terminal.json"
            real_link = os.link
            def publish(pending, destination, **kwargs):
                self.assertFalse(target.exists())
                self.assertEqual(json.loads(Path(pending).read_text()), {"complete": True})
                return real_link(pending, destination, **kwargs)
            with mock.patch.object(C.os, "link", side_effect=publish):
                C.write_new(target, dict(complete=True))
            self.assertEqual(json.loads(target.read_text()), {"complete": True})
            with self.assertRaisesRegex(ValueError, "overwrite"):
                C.write_new(target, dict(complete=False))
            self.assertEqual(json.loads(target.read_text()), {"complete": True})
            self.assertEqual([p.name for p in Path(tmp).iterdir()], ["terminal.json"])

    def test_atomic_write_preserves_evidence_created_during_publish_race(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "terminal.json"
            real_link = os.link
            def competing_publish(pending, destination, **kwargs):
                target.write_text('{"prior_failure":"preserve"}')
                return real_link(pending, destination, **kwargs)
            with mock.patch.object(C.os, "link", side_effect=competing_publish):
                with self.assertRaises(FileExistsError):
                    C.write_new(target, dict(replacement="forbidden"))
            self.assertEqual(json.loads(target.read_text()), {"prior_failure": "preserve"})
            self.assertEqual(len(list(Path(tmp).iterdir())), 1)

    def process_snapshot_mocks(self, starts):
        def proc_stat(start):
            fields = ["S", "100", "200", "200"] + ["0"] * 16
            fields[19] = str(start)
            return "123 (generated_fixture) " + " ".join(fields)
        files = {name: mock.Mock() for name in ("stat", "status", "cmdline", "limits")}
        files["stat"].read_text.side_effect = [proc_stat(x) for x in starts]
        files["status"].read_text.return_value = "Cpus_allowed_list:\t19\nVmRSS:\t10 kB\n"
        files["cmdline"].read_bytes.return_value = b"generated_fixture\0"
        files["limits"].read_text.return_value = "generated limits"
        proc = mock.MagicMock()
        proc.__truediv__.side_effect = lambda name: files[name]
        proc.stat.return_value = SimpleNamespace(st_uid=os.getuid())
        root = mock.MagicMock()
        root.__truediv__.return_value = proc
        return root, files

    def test_process_snapshot_rechecks_starttime_and_retries_pid_reuse(self):
        root, files = self.process_snapshot_mocks([1, 2, 2, 2])
        with mock.patch.object(C, "Path", return_value=root):
            snapshot = C.process(123)
        self.assertEqual(snapshot["starttime_ticks"], "2")
        self.assertEqual(files["stat"].read_text.call_count, 4)

    def test_process_snapshot_skips_persistently_unstable_unrelated_pid(self):
        root, files = self.process_snapshot_mocks([1, 2] * 3)
        with mock.patch.object(C, "Path", return_value=root):
            self.assertIsNone(C.process(123))
        self.assertEqual(files["stat"].read_text.call_count, 6)

    def test_owned_leader_identity_retries_then_requires_conclusive_proof(self):
        identity = dict(pid=123, session=123, starttime_ticks="1")
        leader = dict(identity, uid=os.getuid(), state="S")
        with mock.patch.object(C, "process", side_effect=[None, leader]), \
             mock.patch.object(C.Path, "exists", return_value=True), \
             mock.patch.object(C, "process_table", return_value=[leader]), mock.patch.object(C.time, "sleep"):
            self.assertEqual(C.owned_rows(identity), [leader])
        with mock.patch.object(C, "process", return_value=None), \
             mock.patch.object(C.Path, "exists", return_value=True), mock.patch.object(C.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "inconclusive"):
                C.owned_rows(identity)

    def scan_context(self, entries):
        context = mock.MagicMock()
        context.__enter__.return_value = entries
        return context

    def scan_entry(self, path, *, inode=1, size=17, mode=stat.S_IFREG):
        entry = mock.Mock(path=str(path))
        entry.stat.return_value = SimpleNamespace(st_mode=mode, st_dev=1, st_ino=inode, st_size=size)
        return entry

    def test_output_scanner_rescans_progress_and_control_atomic_temporaries(self):
        control, output = Path("/GENERATED_CONTROL"), Path("/GENERATED_OUTPUT")
        for base, temporary, published in (
            (output, "progress_worker_01.json.new", "progress_worker_01.json"),
            (control, ".terminal.json.pending-abcdefgh", "terminal.json"),
        ):
            with self.subTest(temporary=temporary):
                vanished = self.scan_entry(base / temporary)
                vanished.stat.side_effect = FileNotFoundError(errno.ENOENT, "generated atomic rename", str(base / temporary))
                stable = self.scan_entry(base / published)
                first = [self.scan_context([vanished] if base == control else []),
                         self.scan_context([vanished] if base == output else [])]
                second = [self.scan_context([stable] if base == control else []),
                          self.scan_context([stable] if base == output else [])]
                with mock.patch.object(C.os, "scandir", side_effect=first + second) as scan, mock.patch.object(C.time, "sleep"):
                    self.assertEqual(C.scan_output_bytes(control, output), 17)
                self.assertEqual(scan.call_count, 4)

    def test_output_scanner_fails_closed_on_persistent_or_unexpected_errors(self):
        control, output = Path("/GENERATED_CONTROL"), Path("/GENERATED_OUTPUT")
        pending = self.scan_entry(output / "progress_worker_01.json.new")
        pending.stat.side_effect = FileNotFoundError(errno.ENOENT, "generated race", pending.path)
        scans = [self.scan_context([]), self.scan_context([pending])] * 4
        with mock.patch.object(C.os, "scandir", side_effect=scans) as scan, mock.patch.object(C.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "bounded atomic-publication"):
                C.scan_output_bytes(control, output)
        self.assertEqual(scan.call_count, 8)
        for entry, exception in (
            (self.scan_entry(output / "unexpected.json"), FileNotFoundError(errno.ENOENT, "unexpected disappearance", "unexpected.json")),
            (self.scan_entry(output / "progress_worker_01.json.new"), PermissionError("permission must remain strict")),
        ):
            entry.stat.side_effect = exception
            with mock.patch.object(C.os, "scandir", side_effect=[self.scan_context([]), self.scan_context([entry])]):
                with self.assertRaises(type(exception)):
                    C.scan_output_bytes(control, output)
        symlink = self.scan_entry(output / "bad-link", mode=stat.S_IFLNK)
        with mock.patch.object(C.os, "scandir", side_effect=[self.scan_context([]), self.scan_context([symlink])]):
            with self.assertRaisesRegex(ValueError, "symlink"):
                C.scan_output_bytes(control, output)

    def test_output_scanner_counts_atomic_control_inode_once_and_budget_stays_strict(self):
        control, output = Path("/GENERATED_CONTROL"), Path("/GENERATED_OUTPUT")
        entries = [self.scan_entry(control / name) for name in ("terminal.json", ".terminal.json.pending-abcdefgh")]
        with mock.patch.object(C.os, "scandir", side_effect=[self.scan_context(entries), self.scan_context([])]):
            self.assertEqual(C.scan_output_bytes(control, output), 17)
        child = mock.Mock()
        child.poll.return_value = None
        c = dict(output_root=str(output), limits=dict(aggregate_memory_bytes=1000, aggregate_cpu_seconds=1000,
                                                      wall_seconds=1000, output_bytes=16))
        with mock.patch.object(C, "owned_rows", return_value=[]), mock.patch.object(C, "scan_output_bytes", return_value=17):
            with self.assertRaisesRegex(ValueError, "compact output budget"):
                C.monitor(child, {}, c, control)

    def test_cleanup_snapshot_retries_new_owned_children_but_not_foreign_members(self):
        identity = dict(session=123)
        first = dict(pid=123, starttime_ticks="1", pgid=123, session=123, uid=os.getuid(), state="S")
        forked = dict(first, pid=124, starttime_ticks="2")
        with mock.patch.object(C, "process_table", return_value=[first, forked]) as table, \
             mock.patch.object(C, "owned_rows", return_value=[first, forked]) as owned, mock.patch.object(C.time, "sleep"):
            self.assertEqual(C.validated_group(identity, 123, [first]), [first, forked])
        self.assertEqual(table.call_count, 2)
        owned.assert_called_once_with(identity)
        with mock.patch.object(C, "process_table", return_value=[first, dict(forked, session=999)]), \
             mock.patch.object(C, "owned_rows") as owned:
            with self.assertRaisesRegex(ValueError, "foreign"):
                C.validated_group(identity, 123, [first])
            owned.assert_not_called()
        with mock.patch.object(C, "process_table", return_value=[first, forked]) as table, \
             mock.patch.object(C, "owned_rows", return_value=[first]), mock.patch.object(C.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "remained unstable"):
                C.validated_group(identity, 123, [first])
        self.assertEqual(table.call_count, 4)

    def generated_manifest(self, out):
        """No input paths exist: only newly generated test bytes are hashed."""
        c = dict(source_commit="a" * 40, source_tree="b" * 40, output_root=str(out),
            draw_export=dict(max_bytes=C.MiB), limits=dict(output_bytes=4 * C.MiB, child_cpu_seconds=60, memory_bytes=C.GiB))
        reads = []
        for role in ("design", "median_model", "calibration_draws"):
            c[role] = dict(path="/NONEXISTENT_TEST_ONLY/" + role + ".rds", size_bytes=123, sha256="c" * 64)
            reads.append(dict(role=role, **c[role], pre_read_sha256="c" * 64, post_read_sha256="c" * 64, status="DESERIALIZED"))
        exports = []
        for name in ("calibrated_random_walk_draws.rds", "mixture_random_walk_student_t_draws.rds"):
            p = out / name
            p.write_bytes(b"tiny GENERATED test fixture; not a scientific array")
            exports.append(dict(path=str(p), relative_path=name, size_bytes=p.stat().st_size,
                sha256=hashlib.sha256(p.read_bytes()).hexdigest(), generated_array_only=True,
                full_parameter_posterior_draws=False, dimensions=[1000, 4, 28], finite_values=100000, missing_values=12000))
        receipt = dict(schema_version="glofas_reference_recovery_receipt_v1", status="PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION",
            source_commit=c["source_commit"], source_tree=c["source_tree"], purpose_sha256="d" * 64,
            original_RDS_deserializations=2, generated_numeric_array_deserializations=1, saved_callback_calls=0,
            full_parameter_refits=0, future_truth_read=False, attempted_reads=reads, generated_draw_exports=exports,
            worker_proofs=[dict(pid=900000+i, cpus=str(cpu), native_cpu_limits=[60, 60],
                native_address_space_limits=[C.GiB, C.GiB], CPU_seconds=0.1, starttime="0")
                for i, cpu in enumerate(sorted(C.CPUS))], **{key: False for key in C.QUALIFICATIONS})
        C.write_new(out / "REFERENCE_RECOVERY_RECEIPT.json", receipt)
        with (out / "artifact_manifest.csv").open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["relative_path", "size_bytes", "sha256"])
            for p in sorted(out.iterdir()):
                if p.name != "artifact_manifest.csv":
                    writer.writerow([p.name, p.stat().st_size, hashlib.sha256(p.read_bytes()).hexdigest()])
        return c

    def test_complete_generated_manifest_closes_without_reopening_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = self.generated_manifest(Path(tmp))
            closed = C.verify_manifest(c)
            self.assertTrue(closed["output_manifest_verified"])
            self.assertEqual(closed["original_RDS_deserializations"], 2)
            self.assertEqual(len(C.SOURCE_PATHS), 19)

    def test_generated_manifest_tamper_and_unlisted_outputs_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            c = self.generated_manifest(Path(tmp))
            (Path(tmp) / "unlisted.json").write_text("{}")
            with self.assertRaisesRegex(ValueError, "complete flat"):
                C.verify_manifest(c)
            (Path(tmp) / "unlisted.json").unlink()
            (Path(tmp) / "calibrated_random_walk_draws.rds").write_bytes(b"tampered GENERATED bytes")
            with self.assertRaisesRegex(ValueError, "manifest mismatch"):
                C.verify_manifest(c)

    def test_default_is_no_launch(self):
        with mock.patch.object(C, "launch_tmux") as launch:
            self.assertEqual(C.main([]), 0)
            launch.assert_not_called()

    def test_launch_needs_explicit_external_purpose(self):
        with self.assertRaisesRegex(ValueError, "requires explicit"):
            C.main(["--launch"])

    def test_native_command_matches_inherited_exact_timeout_guard(self):
        c = dict(limits=dict(logical_cpu=20, wall_seconds=3600, cpu_seconds=3600,
                            memory_bytes=16*C.GiB, output_bytes=64*C.MiB), command="NEVER_EXECUTE_CONTRACT_COMMAND")
        argv = C.native_command(c, "/EXTERNAL/purpose.json", "a"*64, Path("/PRIVATE"))
        at = argv.index("/usr/bin/timeout")
        self.assertEqual(argv[at+1:at+5], ["--signal=TERM", "--kill-after=1s", "3599s", "/usr/bin/prlimit"])
        self.assertIn(C.READER, argv)
        self.assertNotIn(c["command"], argv)
        self.assertEqual(argv[-1], "--execute")

    def test_original_payload_hash_is_never_permitted(self):
        with tempfile.TemporaryDirectory() as tmp:
            original = Path(tmp) / "fit.rds"
            original.write_bytes(b"generated test sentinel, not scientific input")
            with self.assertRaisesRegex(ValueError, "must not open"):
                C.sha(original)
            with self.assertRaisesRegex(ValueError, "only exact bounded generated"):
                C.generated_array_sha(original, Path(tmp), 1000)

    def test_private_socket_directory_ownership_and_existing_socket_guards(self):
        nonce = "ab" * 16
        control = C.new_control(nonce)
        try:
            self.assertEqual(C.private_control(control, nonce), control)
            with self.assertRaisesRegex(ValueError, "ownership changed"):
                C.private_control(control, "cd" * 16)
            os.chmod(control, 0o755)
            with self.assertRaisesRegex(ValueError, "0700"):
                C.private_control(control, nonce)
            os.chmod(control, 0o700)
            (control / "server.sock").symlink_to(control / "nonexistent-target")
            with mock.patch.object(C.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "existing tmux socket"):
                    C.launch_tmux(control, nonce, [sys.executable, "-c", "pass"])
                run.assert_not_called()
        finally:
            shutil.rmtree(control)

    def test_pid_reuse_refuses_cleanup_without_signaling(self):
        child = mock.Mock(pid=123456)
        identity = dict(pid=child.pid, session=child.pid, pgid=child.pid, ppid=os.getpid(), uid=os.getuid(), starttime_ticks="1")
        with mock.patch.object(C, "process", return_value={**identity, "starttime_ticks": "2"}), mock.patch.object(C.os, "killpg") as kill:
            with self.assertRaisesRegex(ValueError, "PID reused"):
                C.cleanup_owned(child, identity)
            kill.assert_not_called()

    def test_uncaptured_timeout_group_cleanup_preserves_unrelated_session(self):
        unrelated = subprocess.Popen(["/usr/bin/sleep", "30"], start_new_session=True)
        child = subprocess.Popen(["/usr/bin/bash", "--noprofile", "--norc", "-c",
            "/usr/bin/timeout --signal=TERM --kill-after=1s 30s /usr/bin/sleep 30 &\nwait\nrc=$?\nexit \"$rc\""],
            start_new_session=True)
        identity = C.process(child.pid)
        try:
            rows = until(lambda: [r for r in C.owned_rows(identity) if r["comm"] == "timeout"])
            self.assertNotEqual(rows[0]["pgid"], child.pid)
            actions = C.cleanup_owned(child, identity)
            self.assertTrue(actions)
            self.assertFalse(C.owned_rows(identity))
            self.assertIsNone(unrelated.poll())
        finally:
            if child.poll() is None:
                C.cleanup_owned(child, identity)
            unrelated.terminate()
            unrelated.wait(timeout=3)

    def test_process_lookup_during_signal_is_safe(self):
        child = subprocess.Popen(["/usr/bin/sleep", "30"], start_new_session=True)
        identity = C.process(child.pid)
        real_kill = os.killpg
        def gone(group, sig):
            real_kill(group, sig)
            raise ProcessLookupError("generated race after signal")
        with mock.patch.object(C.os, "killpg", side_effect=gone):
            C.cleanup_owned(child, identity)
        self.assertFalse(C.owned_rows(identity))

    def test_failed_native_records_unknown_reads_and_closes_actors(self):
        with tempfile.TemporaryDirectory() as tmp:
            control = Path(tmp)
            c = dict(source_root=tmp, output_root=str(control / "outputs"),
                limits=dict(aggregate_memory_bytes=256 * C.MiB, aggregate_cpu_seconds=20,
                            wall_seconds=5, output_bytes=4 * C.MiB))
            rc = C.run_owned_job(c=c, control=control, argv=["/usr/bin/sleep", "30"], env=os.environ.copy(),
                capture_live=lambda *_: (_ for _ in ()).throw(ValueError("generated capture failure")),
                verify_after=lambda: self.fail("failed job must not verify scientific success"))
            terminal = json.loads((control / "terminal.json").read_text())
            self.assertEqual(rc, 1)
            self.assertEqual(terminal["original_RDS_deserializations"], "UNKNOWN_NO_INDEPENDENT_CLOSED_RECEIPT")
            self.assertTrue(terminal["owner_terminated"])
            self.assertFalse(terminal["computational_closure"])

    @unittest.skipUnless(shutil.which("tmux"), "tmux required for real detach fixture")
    def test_real_tmux_supervisor_survives_launcher_exit_and_writes_closure(self):
        # Separate generated launcher and supervisor processes are essential:
        # a same-process mock cannot detect the lost-outer-controller failure.
        nonce = "ef" * 16
        control = C.new_control(nonce)
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            driver = temp / "generated_supervisor.py"
            driver.write_text('''import importlib.util, json, os, pathlib, sys
spec = importlib.util.spec_from_file_location("controller", sys.argv[1])
C = importlib.util.module_from_spec(spec); spec.loader.exec_module(C)
p = pathlib.Path(sys.argv[2])
C.write_new(p / "fixture_supervisor_started.json", {"pid": os.getpid()})
c = dict(source_root=str(p), output_root=str(p / "generated_output"),
 limits=dict(aggregate_memory_bytes=512*C.MiB, aggregate_cpu_seconds=20, wall_seconds=5, output_bytes=4*C.MiB))
def capture(child, identity):
 return {"generated_fixture": True, "shell": identity}
def verify():
 assert (p / "generated_done.json").read_text() == "done"
 return {"generated_fixture_verified": True, "original_RDS_deserializations": 0}
job = "import pathlib,time; time.sleep(1.5); pathlib.Path(" + repr(str(p / "generated_done.json")) + ").write_text('done')"
sys.exit(C.run_owned_job(c=c, control=p, argv=[sys.executable, "-B", "-c", job],
 env=os.environ.copy(), capture_live=capture, verify_after=verify))
''')
            launcher = temp / "generated_launcher.py"
            launcher.write_text('''import importlib.util,json,sys
spec=importlib.util.spec_from_file_location("controller",sys.argv[1])
C=importlib.util.module_from_spec(spec);spec.loader.exec_module(C)
print(json.dumps(C.launch_tmux(sys.argv[2],sys.argv[3],
 [sys.executable,"-B",sys.argv[4],sys.argv[1],sys.argv[2]])))
''')
            try:
                front = subprocess.run([sys.executable, "-B", str(launcher), str(CONTROLLER), str(control), nonce, str(driver)],
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(front.returncode, 0, front.stderr)
                launch = json.loads(front.stdout)
                self.assertEqual(launch["socket"], str(control / "server.sock"))
                started = until(lambda: (control / "fixture_supervisor_started.json").exists())
                self.assertTrue(started)
                self.assertFalse((control / "terminal.json").exists(), "fixture must continue after launcher exits")
                supervisor_pid = json.loads((control / "fixture_supervisor_started.json").read_text())["pid"]
                self.assertIsNotNone(C.process(supervisor_pid))
                until(lambda: (control / "terminal.json").exists())
                terminal = json.loads((control / "terminal.json").read_text())
                self.assertTrue(terminal["computational_closure"], terminal)
                self.assertTrue(terminal["generated_fixture_verified"])
                self.assertEqual(terminal["native_exit_code"], 0)
                self.assertTrue(all(terminal[k] is False for k in C.QUALIFICATIONS))
                until(lambda: C.process(supervisor_pid) is None or C.process(supervisor_pid)["state"] == "Z")
            finally:
                # This fixture's owned private server only; never a default
                # tmux server or an existing user session.
                if (control / "server.sock").exists():
                    subprocess.run(["/usr/bin/tmux", "-S", str(control / "server.sock"), "kill-server"],
                                   capture_output=True, timeout=5)
                shutil.rmtree(control)


if __name__ == "__main__":
    unittest.main()
