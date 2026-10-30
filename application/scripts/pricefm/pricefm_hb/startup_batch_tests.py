"""Temporary metadata/transport doubles only; no SSH, Slurm, R or child runs."""
import errno
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tarfile
import io
import time
import unittest
from unittest.mock import Mock, patch

from . import startup_batch as b
from . import startup_batch_worker as w
from . import startup_helper as h


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm_batch_unit_")
        self.base = Path(self.temp.name); self.registry = self.base / "registry"; self.registry.mkdir()
        self.root = self.registry / b.ROLES[0]; self.root.mkdir()
        self.p = dict(role=b.ROLES[0], scope_id="r174-unit", remote_root="/mnt/beegfs/home/jaguir26/pricefm_unit/r174-unit",
                      spec_sha256="a" * 64, sources={})
        self.save(self.root / "PACKET.json", self.p)
        b.append(self.root, "PREPARED", packet=h.pin(self.root / "PACKET.json"))
        self.site = dict(host="hb.ucsc.edu", user="jaguir26", account="128x24", partition="128x24", qos="normal",
                         known_hosts_file="/tmp/unit-known-host-path", ssh_identity_file="/tmp/unit-key-path-not-opened")

    def tearDown(self): self.temp.cleanup()

    def save(self, path, value):
        path.write_text(json.dumps(value, sort_keys=True)); return h.pin(path)

    def account(self, missing=False, failed=False):
        role = self.p["scope_id"]
        lines = [f"123|COMPLETED|0:0|01:21.924|287|1|{role}|128x24|128x24|8Gn|",
                 "123.batch|COMPLETED|0:0|00:00.027|287|1|batch|128x24|128x24|8Gn|6184K"]
        if not missing:
            lines.append("123.0|%s|%s|01:21.897|287|1|python|128x24|128x24|8Gn|574612K"
                         % ("FAILED" if failed else "COMPLETED", "7:0" if failed else "0:0"))
        return "\n".join(lines) + "\n"

    def ready(self):
        return dict(status="READY_SOURCE_BOUND_COMPUTE_METADATA", scope_id=self.p["scope_id"], job_id="123", role=b.ROLES[0],
                    spec_sha256=self.p["spec_sha256"], node="node-13", affinity=[0], cpus_per_task=1, models=0, sources={})

    def test_no_interpreter_or_shell_on_login(self):
        for executable in ("python", "python3", "R", "Rscript", "bash", "sh"):
            with self.subTest(executable=executable), self.assertRaises(ValueError): b.native_command([executable, "-c", "unit"])

    def test_native_arguments_are_shell_quoted(self):
        self.assertIn("'name;echo bad'", b.native_command(["test", "-f", "name;echo bad"]))

    def test_public_fork_path_and_no_inner_kill_timeout(self):
        runner = Mock(return_value=Mock(returncode=0, stdout="", stderr=""))
        b.run_native(self.site, ["test", "-f", "/safe"], runner=runner)
        self.assertIn("preexec_fn", runner.call_args.kwargs)
        self.assertNotIn("timeout", runner.call_args.kwargs)

    def test_complete240_envelope_with_three_polls(self):
        self.assertEqual(b.NATIVE_CONTROL_TOTAL, 240)
        self.assertEqual(b.ACTION_ENVELOPE["observe"]["maximum_calls"], 3)

    def test_exact_numeric_job_id_only(self):
        self.assertEqual(b.parse_job_id("123;hummingbird\n"), "123")
        for value in ("", "warning\n123\n", "123 extra", "0", "123_2"):
            with self.subTest(value=value), self.assertRaises(ValueError): b.parse_job_id(value)

    def test_lost_submit_reply_is_spent_not_retried(self):
        b.append(self.root, "STAGED")
        with patch.object(b, "run_native", side_effect=[dict(returncode=0, stdout="", stderr=""), TimeoutError("unit lost reply")]):
            with self.assertRaises(TimeoutError): b.submit(dict(node="node-13"), dict(expires_epoch=time.time() + 3600), self.site, self.root)
        self.assertEqual(b.records(self.root)[-1]["state"], "AMBIGUOUS_SPENT")
        self.assertFalse((self.root / "JOB.json").exists())
        with self.assertRaises(ValueError): b.submit(dict(node="node-13"), dict(expires_epoch=time.time() + 3600), self.site, self.root)

    def test_primary_CPU_once_with_step_rows_diagnostic(self):
        value = b.parse_accounting(self.account(), "123", self.p["scope_id"])
        self.assertTrue(value["complete"] and value["terminal"])
        self.assertAlmostEqual(value["canonical_primary_CPU_seconds"], 81.924)
        self.assertIsNone(value["MaxRSS_raw"]["123"])

    def test_missing_step_rows_are_unknown_not_complete(self):
        value = b.parse_accounting(self.account(missing=True), "123", self.p["scope_id"])
        self.assertFalse(value["complete"] or value["terminal"])

    def test_failed_step_prevents_success(self):
        value = b.parse_accounting(self.account(failed=True), "123", self.p["scope_id"])
        self.assertFalse(value["complete"]); self.assertTrue(value["terminal"])

    def test_primary_CPU_lag_is_unknown_not_zero_or_double_charge(self):
        raw = self.account().replace("123|COMPLETED|0:0|01:21.924", "123|COMPLETED|0:0|00:00.000")
        value = b.parse_accounting(raw, "123", self.p["scope_id"])
        self.assertFalse(value["complete"] or value["terminal"])
        self.assertFalse(value["primary_CPU_consistent_with_each_step"])

    def test_duplicate_or_foreign_accounting_rejected(self):
        for extra in (self.account().splitlines()[0], self.account().splitlines()[0].replace("123|", "999|")):
            with self.assertRaises(ValueError): b.parse_accounting(self.account() + extra + "\n", "123", self.p["scope_id"])

    def test_wrong_memory_request_rejected(self):
        with self.assertRaises(ValueError): b.parse_accounting(self.account().replace("8Gn", "16Gn"), "123", self.p["scope_id"])

    def test_stale_job_or_source_READY_rejected(self):
        for field, bad in (("job_id", "999"), ("sources", {"foreign": "source"}), ("spec_sha256", "b" * 64), ("models", False)):
            value = self.ready(); value[field] = bad
            with self.subTest(field=field), self.assertRaises(ValueError): b.validate_ready(value, self.p, "123")

    def test_partial_ready_JSON_rejected(self):
        with self.assertRaises(ValueError): w.read_json('{"status":"READY"')

    def test_duplicate_worker_JSON_rejected(self):
        with self.assertRaises(ValueError): w.read_json('{"role":1,"role":2}')

    def test_worker_float_overflow_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "nonfinite"): w.read_json('{"number":1e999}')

    def test_unlisted_carrier_directory_is_rejected(self):
        archive = self.base / "carrier.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            directory = tarfile.TarInfo("unlisted"); directory.type = tarfile.DIRTYPE; tar.addfile(directory)
            item = tarfile.TarInfo("R_HOME/file"); item.size = 1; item.mode = 0o644
            tar.addfile(item, io.BytesIO(b"x"))
        manifest = self.save(self.base / "carrier_manifest.json", dict(files=[dict(relative="R_HOME/file", bytes=1,
            sha256=hashlib.sha256(b"x").hexdigest(), mode=0o644)]))
        root = self.base / "remote_private"; root.mkdir()
        spec = dict(remote_root=str(root), carrier=h.pin(archive), carrier_manifest=manifest)
        with self.assertRaisesRegex(ValueError, "unexpected file"): w.extract_carrier(spec)
        self.assertFalse((root / "runtime_carrier/unlisted").exists())

    def test_READY_atomic_publication_never_overwrites(self):
        target = self.base / "READY.json"; w.publish_atomic_new(target, {"unit": "complete"})
        self.assertEqual(json.loads(target.read_text()), {"unit": "complete"})
        with self.assertRaises(OSError): w.publish_atomic_new(target, {"unit": "replacement"})
        self.assertEqual(json.loads(target.read_text()), {"unit": "complete"})

    def test_READY_link_publication_complete_single_link_and_durable(self):
        target = self.base / "READY.json"; real_link = os.link; real_sync = os.fsync; events = []
        def linking(source, destination, **kwargs):
            folder = Path(os.readlink("/proc/self/fd/" + str(kwargs["src_dir_fd"])))
            self.assertEqual(json.loads((folder / source).read_text()), {"unit": "complete"})
            self.assertFalse((folder / destination).exists())
            events.append("link"); return real_link(source, destination, **kwargs)
        def syncing(fd): events.append("sync"); return real_sync(fd)
        with patch.object(w.os, "link", side_effect=linking), patch.object(w.os, "fsync", side_effect=syncing):
            w.publish_atomic_new(target, {"unit": "complete"})
        self.assertEqual(target.stat().st_nlink, 1)
        self.assertFalse(target.with_name("READY.json.partial").exists())
        self.assertGreaterEqual(events.index("link"), 2)
        self.assertEqual(events[-1], "sync")
        self.assertEqual(w.read_json(w.read_exact(w.pin(target))), {"unit": "complete"})

    def test_READY_unsupported_link_fails_without_final_or_partial(self):
        for number in (errno.EOPNOTSUPP, errno.EPERM, errno.EXDEV):
            target = self.base / ("READY_%s.json" % number)
            with patch.object(w.os, "link", side_effect=OSError(number, "unit unsupported")):
                with self.assertRaises(OSError): w.publish_atomic_new(target, {"unit": "complete"})
            self.assertFalse(target.exists()); self.assertFalse(target.with_name(target.name + ".partial").exists())

    def test_READY_partial_write_never_publishes(self):
        target = self.base / "READY.json"
        def incomplete(_value, handle, **_kwargs): handle.write('{"partial":'); raise OSError("unit write failure")
        with patch.object(w.json, "dump", side_effect=incomplete), patch.object(w.os, "link") as link:
            with self.assertRaises(OSError): w.publish_atomic_new(target, {"unit": "complete"})
        link.assert_not_called(); self.assertFalse(target.exists())
        self.assertFalse(target.with_name("READY.json.partial").exists())

    def test_READY_directory_sync_failure_is_not_success(self):
        target = self.base / "READY.json"; real_sync = os.fsync; count = 0
        def syncing(fd):
            nonlocal count
            count += 1
            if count == 3: raise OSError("unit final directory sync failure")
            return real_sync(fd)
        with patch.object(w.os, "fsync", side_effect=syncing):
            with self.assertRaises(OSError): w.publish_atomic_new(target, {"unit": "complete"})
        self.assertEqual(json.loads(target.read_text()), {"unit": "complete"})
        self.assertEqual(target.stat().st_nlink, 1)

    def test_READY_existing_symlink_is_never_followed(self):
        original = self.base / "original"; original.write_text("preserve")
        target = self.base / "READY.json"; target.symlink_to(original)
        with self.assertRaises(ValueError): w.publish_atomic_new(target, {"unit": "replacement"})
        self.assertEqual(original.read_text(), "preserve"); self.assertTrue(target.is_symlink())

    def test_READY_absent_is_single_observation_and_retains_terminal_accounting(self):
        self.save(self.root / "JOB.json", dict(job_id="123"))
        account = self.save(self.root / "account.json", dict(terminal=True, complete=False, state="FAILED"))
        b.append(self.root, "OBSERVED", accounting=account)
        with patch.object(b, "run_native", return_value=dict(returncode=1)) as native, patch.object(b.time, "sleep") as sleep, patch.object(b, "observe") as observe:
            with self.assertRaisesRegex(ValueError, "READY absent"): b.ready(self.site, self.root)
        native.assert_called_once(); sleep.assert_not_called(); observe.assert_not_called()
        last = b.records(self.root)[-1]; self.assertEqual(last["state"], "READY_ABSENT_DIAGNOSTIC")
        self.assertEqual(last["accounting"]["state"], "FAILED"); self.assertFalse(last["automatic_retry"])

    def test_READY_absent_one_accounting_diagnostic_then_failure(self):
        self.save(self.root / "JOB.json", dict(job_id="123"))
        calls = [dict(returncode=1), dict(returncode=0, stdout=self.account(failed=True))]
        with patch.object(b, "run_native", side_effect=calls) as native, patch.object(b.time, "sleep") as sleep:
            with self.assertRaisesRegex(ValueError, "READY absent"): b.ready(self.site, self.root)
        self.assertEqual(native.call_count, 2); sleep.assert_not_called()
        self.assertEqual(len(list(self.root.glob("observe_*.intent.json"))), 1)
        self.assertTrue(b.records(self.root)[-1]["accounting"]["terminal"])

    def test_READY_present_fetches_once_without_sleep_or_accounting(self):
        self.save(self.root / "JOB.json", dict(job_id="123"))
        def fetch(_site, _commands, _batch):
            self.save(self.root / "READY.json", self.ready()); return dict(returncode=0)
        with patch.object(b, "run_native", return_value=dict(returncode=0)) as native, patch.object(b, "run_sftp", side_effect=fetch) as transfer, patch.object(b.time, "sleep") as sleep:
            self.assertEqual(b.ready(self.site, self.root), self.ready())
        native.assert_called_once(); transfer.assert_called_once(); sleep.assert_not_called()

    def test_return_paths_and_scientific_binary_rejected(self):
        for path in ("../escape", "/absolute", "fit.rds", "array.npz"):
            value = dict(schema="pricefm_startup_batch_return_manifest_v1", scope_id=self.p["scope_id"], job_id="123",
                files=[dict(relative="RESULT.json", bytes=2, sha256="a" * 64), dict(relative=path, bytes=2, sha256="b" * 64)])
            with self.subTest(path=path), self.assertRaises(ValueError): b.validate_manifest(value, self.p, "123")

    def test_partial_transfer_hash_is_not_acceptance(self):
        self.save(self.root / "JOB.json", dict(job_id="123"))
        account = self.save(self.root / "account.json", dict(terminal=True))
        b.append(self.root, "OBSERVED", accounting=account)
        manifest = dict(schema="pricefm_startup_batch_return_manifest_v1", scope_id=self.p["scope_id"], job_id="123",
            files=[dict(relative="RESULT.json", bytes=2, sha256=hashlib.sha256(b"{}").hexdigest())])
        def transfer(_site, commands, _batch):
            if "RETURN_MANIFEST.json" in commands[0]:
                Path(commands[0].split()[-1]).write_text(json.dumps(manifest))
            elif "RESULT.json" in commands[0]: Path(commands[0].split()[-1]).write_bytes(b"[]")
            return dict(returncode=0, stdout="", stderr="")
        with patch.object(b, "run_sftp", side_effect=transfer):
            with self.assertRaisesRegex(ValueError, "hash differ"): b.collect(self.site, self.root)
        self.assertFalse((self.root / "ACCEPTED.json").exists())
        self.assertFalse(any(x["state"] == "RETURNED" for x in b.records(self.root)))

    def test_false_or_late_outer_guard_cannot_accept(self):
        value = dict(status="ACCEPTANCE_PENDING_ACTUAL_OUTER_GUARD", role=b.ROLES[0], job_id="123")
        started = b.started_action(self.registry, b.ROLES[0], "accept")
        b.pending_action(started, value)
        pending = h.read(h.pin(next(self.registry.glob("control_*.pending.json"))))
        guard = dict(returncode=124, command_returncode=0, CPU_limit=5, aggregate_CPU_seconds=.1,
            complete_lifecycle_wall_seconds=1, session_id=pending["command_pid"], leader_start_ticks=pending["command_birth_ticks"],
            stdout=json.dumps(value), all_owned_descendants_reaped=True, independent_guardian=True, kernel_escape_filter=True)
        guard.update(guardian_forced_monitor_stop=False, orphan_subreaper=True, guardian_included_in_CPU=True,
                     inherited_waited_history_included_once=True, cap_reason=None)
        path = self.base / "guard.json"; self.save(path, guard)
        with self.assertRaises(ValueError): b.finish_previous(self.registry, str(path))
        self.assertFalse((self.root / "ACCEPTED.json").exists())
        guard["returncode"] = 0; self.save(path, guard)
        b.finish_previous(self.registry, str(path))
        self.assertEqual(h.read(h.pin(self.root / "ACCEPTED.json"))["status"], "ACCEPTED_COMPLETE_STARTUP_BATCH_METADATA_ROLE")

    def test_incomplete_action_publication_blocks_successor(self):
        b.started_action(self.registry, b.ROLES[0], "stage")
        with self.assertRaisesRegex(ValueError, "actual prior outer guardian"):
            b.finish_previous(self.registry, None)
        with self.assertRaisesRegex(ValueError, "did not complete internal publication"):
            b.finish_previous(self.registry, str(self.base / "unused_guard.json"))

    def test_failed_guard_only_opens_known_job_failure_tail(self):
        job = self.save(self.root / "JOB.json", dict(job_id="123", scope_id=self.p["scope_id"]))
        b.append(self.root, "SUBMITTED", job_id="123", job=job)
        started = b.started_action(self.registry, b.ROLES[0], "release")
        start = h.read(h.pin(started))
        guard = dict(returncode=124, independent_guardian=True, all_owned_descendants_reaped=True, CPU_limit=4,
                     session_id=start["command_pid"], leader_start_ticks=start["command_birth_ticks"])
        path = self.base / "failed.json"; self.save(path, guard)
        value = b.acknowledge_failed_previous(self.registry, b.ROLES[0], str(path))
        self.assertTrue(value["no_successor_compute_authority"])
        self.assertTrue((self.root / "ROLE_FAILED_SPENT.json").is_file())
        self.assertFalse((self.root / "ACCEPTED.json").exists())
        self.assertIsNone(b.finish_previous(self.registry, None))

    def test_mutated_original_packet_pin_rejected(self):
        self.save(self.root / "PACKET.json", dict(self.p, scope_id="foreign"))
        with self.assertRaises(ValueError): b.packet(self.root)

    def test_wrong_release_role_rejected_before_helpers(self):
        ready = self.ready(); ready["role"] = b.ROLES[0]
        rpin = self.save(self.base / "READY.json", ready)
        spec = dict(self.p, role=b.ROLES[0], sources={}, scope=dict(sha256="f" * 64), expires_epoch=time.time() + 3600)
        release = dict(status="ROOT_RELEASED_STARTUP_BATCH_ROLE", role=b.ROLES[1], scope_id=self.p["scope_id"], job_id="123")
        release_pin = self.save(self.base / "RELEASE.json", release)
        with patch.dict(os.environ, SLURM_JOB_ID="123"):
            with self.assertRaises(ValueError): w.validate_release(spec, dict(sha256="a" * 64), rpin, release_pin)


if __name__ == "__main__": unittest.main()
