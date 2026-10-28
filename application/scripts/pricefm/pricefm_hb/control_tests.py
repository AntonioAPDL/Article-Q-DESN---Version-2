#!/usr/bin/env python3
"""Offline controller failure tests; every SSH/rsync/Slurm call is mocked."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pricefm_hb import control as ctl
from pricefm_hb import registry as reg
from pricefm_hb.registry_tests import authority, task, HOST, NOW

LIMITS = {"cpus": 1, "memory_MiB": 2048, "wall_seconds": 60}
JOB = "12345"


def accounting_text(state="COMPLETED", exit_code="0:0"):
    return "\n".join("|".join((job, state, exit_code, "10", "1", "00:00:01", "1024K", "node1"))
                     for job in (JOB, JOB + ".batch", JOB + ".0")) + "\n"


class AccountingTests(unittest.TestCase):
    def test_complete_requires_root_batch_and_scientific_step(self):
        parsed = ctl.accounting(accounting_text(), JOB, LIMITS)
        self.assertTrue(parsed["complete"])
        self.assertTrue(parsed["terminal"])
        partial = "\n".join(accounting_text().splitlines()[:2])
        self.assertFalse(ctl.accounting(partial, JOB, LIMITS)["complete"])
        self.assertFalse(ctl.accounting("", JOB, LIMITS)["terminal"])

    def test_terminal_failure_is_distinct_from_success(self):
        parsed = ctl.accounting(accounting_text("FAILED", "1:0"), JOB, LIMITS)
        self.assertTrue(parsed["terminal"])
        self.assertFalse(parsed["complete"])
        parsed = ctl.accounting(accounting_text("RUNNING"), JOB, LIMITS)
        self.assertFalse(parsed["terminal"])

    def test_duplicate_and_foreign_accounting_rows_are_rejected(self):
        for changed in (accounting_text() + accounting_text().splitlines()[0] + "\n",
                        accounting_text().replace(JOB + ".0", "999.0")):
            with self.subTest(text=changed), self.assertRaises(ValueError):
                ctl.accounting(changed, JOB, LIMITS)

    def test_cpu_wall_memory_and_exit_fields_cannot_exceed_the_scope(self):
        row = accounting_text().splitlines()[0].split("|")
        for index, value in ((2, "oops"), (3, "-1"), (3, "121"), (4, "2"),
                             (5, "00:02:01"), (5, "nan"), (6, "3G"), (6, "invalid")):
            changed = row.copy()
            changed[index] = value
            with self.subTest(index=index, value=value), self.assertRaises(ValueError):
                ctl.accounting("|".join(changed), JOB, LIMITS)

    def test_cpu_time_units_and_fractional_seconds(self):
        self.assertEqual(ctl.cpu_seconds("02:03.5"), 123.5)
        self.assertEqual(ctl.cpu_seconds("01:02:03"), 3723)
        self.assertEqual(ctl.cpu_seconds("1-01:02:03"), 90123)
        for value in ("00:60", "60:00", "bogus", "-1:00"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                ctl.cpu_seconds(value)


class OutputSealTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.outputs = self.root / "outputs"
        self.outputs.mkdir()
        reg.write(self.outputs / "report.json", {"synthetic": True})
        self.claim = {"task_key": reg.identity(task()), "release_sha256": "a" * 64, "job_id": JOB}
        self.manifest = {"task": task()}
        self.seal = {
            "schema": reg.SCHEMA, **self.claim, "kind": "environment", "fits": 0,
            "official_origins": 0, "application_passed": True,
            "allocation": {"job_id": JOB, "cpus_per_task": 1, "affinity": [17]},
            "files": {"report.json": reg.digest(self.outputs / "report.json")},
        }
        self.write_seal()

    def write_seal(self):
        reg.write(self.outputs / "completed_evidence.json", self.seal)

    def validate(self):
        return ctl.validate_outputs(self.outputs, self.claim, self.manifest)

    def test_complete_exact_output_hashes_are_required(self):
        self.assertEqual(self.validate(), self.seal)
        (self.outputs / "report.json").write_text("truncated")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.validate()

    def test_extra_and_missing_files_are_never_accepted(self):
        (self.outputs / "extra").write_text("extra")
        with self.assertRaisesRegex(ValueError, "unsealed/missing"):
            self.validate()
        (self.outputs / "extra").unlink()
        (self.outputs / "report.json").unlink()
        with self.assertRaisesRegex(ValueError, "unsealed/missing"):
            self.validate()

    def test_job_release_task_kind_and_no_production_provenance_are_bound(self):
        original = copy.deepcopy(self.seal)
        for field, value in (("schema", "production"), ("task_key", "b" * 64),
                             ("release_sha256", "b" * 64), ("job_id", "999"),
                             ("kind", "FI"), ("fits", 1), ("official_origins", 1)):
            self.seal = dict(original, **{field: value})
            self.write_seal()
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "provenance"):
                self.validate()

    def test_one_cpu_allocation_must_match_the_claimed_job(self):
        original = copy.deepcopy(self.seal["allocation"])
        for changed in ({"job_id": "999"}, {"cpus_per_task": 2},
                        {"affinity": []}, {"affinity": [17, 18]}):
            self.seal["allocation"] = dict(original, **changed)
            self.write_seal()
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, "allocation"):
                self.validate()

    def test_output_symlink_is_rejected_before_hash_validation(self):
        target = self.root / "external.json"
        target.write_text("outside")
        (self.outputs / "report.json").unlink()
        (self.outputs / "report.json").symlink_to(target)
        with self.assertRaises(ValueError):
            self.validate()


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.registry_root = self.root / "registry"
        self.release = self.root / "release"
        self.release.mkdir()
        (self.release / "job.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.release / "fixture.txt").write_text("metadata-only fixture\n")
        (self.release / "env").mkdir()
        (self.release / "env" / "wheel-manifest.json").write_text('{"synthetic":true}\n')
        self.manifest = ctl.seal_release(self.release, task(), ["/usr/bin/true"], LIMITS)
        self.grant = authority()
        self.grant["jobs"]["environment"].update(
            release_sha256=reg.digest(self.release / "release.json"),
            task_sha256=reg.identity(self.manifest["task"]))
        self.authority_path = self.root / "authority.json"
        reg.write(self.authority_path, self.grant)
        self.config_path = self.root / "config.json"
        self.identity_path = self.root / "synthetic_identity"
        self.trust_path = self.root / "synthetic_known_hosts"
        self.identity_path.write_text("not-a-key\n")
        self.trust_path.write_text("not-host-trust\n")
        self.config = {"host": "hb.ucsc.edu", "user": "jaguir26", "account": "128x24",
                       "partition": "128x24", "qos": "normal",
                       "ssh_identity_file": str(self.identity_path),
                       "known_hosts_file": str(self.trust_path),
                       "remote_root": "/home/jaguir26/pricefm_r156_offline_tests"}
        reg.write(self.config_path, self.config)
        self.queue = ""
        self.sacct = accounting_text()
        self.sbatch_response = JOB + ";hummingbird\n"
        self.remote_calls = []
        self.addCleanup(mock.patch.stopall)
        self.clock = mock.patch.object(reg.time, "time", return_value=NOW).start()
        mock.patch.object(reg.socket, "getfqdn", return_value=HOST).start()
        # Missing mocks fail before any external process or connection occurs.
        mock.patch.object(ctl.subprocess, "run", side_effect=AssertionError("external process forbidden")).start()
        self.remote_mock = mock.patch.object(ctl, "remote", side_effect=self.fake_remote).start()
        self.run_mock = mock.patch.object(ctl, "run", side_effect=self.fake_transfer).start()

    def fake_remote(self, config, args):
        self.remote_calls.append(list(args))
        if args[0] == "squeue":
            return self.queue
        if args[0] == "sacct":
            return self.sacct
        if args[0] == "sha256sum":
            return reg.digest(self.release / "release.json") + "  release.json\n"
        if args[0] == "sbatch":
            return self.sbatch_response
        if args[0] == "mkdir":
            return ""
        raise AssertionError("unexpected remote command: " + str(args))

    def fake_transfer(self, argv, timeout=120):
        self.assertEqual(argv[0], "rsync")
        self.assertLessEqual(timeout, 180)
        # Local qualification payloads contain no actual science or credentials.
        if argv[-2].startswith("jaguir26@hb.ucsc.edu:"):
            destination = Path(argv[-1])
            destination.mkdir(parents=True, exist_ok=True)
            if "/outputs/" in argv[-2]:
                claim = self.claim()
                allocation = {"job_id": JOB, "cpus_per_task": 1, "affinity": [17], "node": "node1"}
                evidence = destination / "environment-evidence"
                evidence.mkdir(exist_ok=True)
                artifacts = evidence / "interpreter-artifact-manifest.json"
                reg.write(artifacts, {"synthetic": True})
                reg.write(evidence / "runtime-verification.json", {
                    "status": "verified", "python_version": "3.11.13", "allocation": allocation,
                    "bundle": {"manifest_sha256": self.manifest["files"]["env/wheel-manifest.json"]["sha256"]},
                    "threadpoolctl": [{"num_threads": 1, "filepath": "synthetic-library"}],
                })
                reg.write(destination / "build-report.json", {
                    "schema": "pricefm-hb-environment-v1", "status": "verified", "allocation": allocation,
                    "interpreter_artifacts": {"manifest_sha256": reg.digest(artifacts)},
                })
                reg.write(destination / "completed_evidence.json", {
                    "schema": reg.SCHEMA, "task_key": claim["task_key"], "job_id": JOB,
                    "release_sha256": claim["release_sha256"], "kind": "environment",
                    "fits": 0, "official_origins": 0, "allocation": allocation, "application_passed": True,
                    "files": {str(p.relative_to(destination)): reg.digest(p) for p in destination.rglob("*")
                              if p.is_file() and p.name != "completed_evidence.json"},
                })
            else:
                (destination / "fixture.log").write_text("synthetic remote log\n")
        return ""

    def submit(self):
        return ctl.stage_and_submit(self.registry_root, self.config_path, self.authority_path, self.release)

    def claim(self):
        values = list(reg.Registry(self.registry_root).snapshot()["claims"].values())
        self.assertEqual(len(values), 1)
        return values[0]

    def receipt(self, claim=None):
        claim = claim or self.claim()
        path = self.root / ("status-" + str(len(list(self.root.glob("status-*.json")))) + ".json")
        ctl.status(self.registry_root, self.config_path, claim["task_key"], path)
        return path

    def collect(self, receipt=None, incoming=None, destination=None):
        claim = self.claim()
        return ctl.collect(self.registry_root, self.config_path, claim["task_key"],
                           receipt or self.receipt(claim), incoming or self.root / "incoming",
                           destination or self.root / "publication")

    def test_release_membership_and_hashes_are_exact(self):
        self.assertEqual(ctl.verify_release(self.release), self.manifest)
        (self.release / "extra.txt").write_text("extra")
        with self.assertRaisesRegex(ValueError, "membership"):
            ctl.verify_release(self.release)
        (self.release / "extra.txt").unlink()
        (self.release / "fixture.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "digest"):
            ctl.verify_release(self.release)

    def test_release_sealing_is_create_only(self):
        with self.assertRaises(FileExistsError):
            ctl.seal_release(self.release, task(), ["/usr/bin/true"], LIMITS)

    def test_production_fi_and_non_test_releases_reject(self):
        for value in (task(kind="FI"), task(kind="screening"), task(namespace="PRODUCTION")):
            target = self.root / ("invalid-" + value["kind"] + value["namespace"])
            target.mkdir()
            with self.subTest(task=value), self.assertRaises(ValueError):
                ctl.seal_release(target, value, ["/usr/bin/true"], LIMITS)
        self.remote_mock.assert_not_called()

    def test_symlinked_payload_and_private_directories_reject(self):
        target = self.root / "outside"
        target.write_text("private fixture")
        (self.release / "link").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular files"):
            ctl.verify_release(self.release)
        clean = self.root / "new-release"
        (clean / ".ssh").mkdir(parents=True)
        (clean / ".ssh" / "fake-key").write_text("not-a-key")
        with self.assertRaisesRegex(ValueError, "excluded"):
            ctl.seal_release(clean, task(), ["/usr/bin/true"], LIMITS)

    def test_trust_identity_and_remote_namespace_are_checked_offline(self):
        for changed in ({"host": "other.example"}, {"remote_root": "/tmp/unsafe"},
                        {"remote_root": "/home/jaguir26/new/../old"},
                        {"ssh_identity_file": "relative-key"}):
            value = dict(self.config, **changed)
            reg.write(self.config_path, value)
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                ctl.config(self.config_path)
        self.remote_mock.assert_not_called()

    def test_verified_canonical_beegfs_home_namespace_is_accepted(self):
        self.config["remote_root"] = "/mnt/beegfs/home/jaguir26/pricefm_r156_offline_tests"
        reg.write(self.config_path, self.config)
        self.assertEqual(ctl.config(self.config_path)["remote_root"], self.config["remote_root"])
        self.remote_mock.assert_not_called()

    def test_foreign_and_lookalike_canonical_home_prefixes_reject(self):
        for root in ("/mnt/beegfs/home/another_user/pricefm_r156", "/mnt/beegfs/home/jaguir260/pricefm_r156",
                     "/mnt/beegfs2/home/jaguir26/pricefm_r156", "/mnt/beegfs/home/jaguir26/../other/pricefm_r156",
                     "/home/another_user/pricefm_r156"):
            reg.write(self.config_path, dict(self.config, remote_root=root))
            with self.subTest(root=root), self.assertRaisesRegex(ValueError, "home namespace"):
                ctl.config(self.config_path)
        self.remote_mock.assert_not_called()

    def test_ssh_has_no_password_agent_forwarding_or_control_socket_fallback(self):
        args = ctl.ssh(self.config)
        for option in ("BatchMode=yes", "StrictHostKeyChecking=yes", "IdentitiesOnly=yes",
                       "IdentityAgent=none", "ForwardAgent=no", "ClearAllForwardings=yes",
                       "PasswordAuthentication=no", "KbdInteractiveAuthentication=no",
                       "ConnectionAttempts=1", "ControlMaster=no", "ControlPath=none"):
            self.assertIn(option, args)
        self.assertEqual(args[-1], "jaguir26@hb.ucsc.edu")
        self.assertEqual(args[args.index("-i") + 1], str(self.identity_path))

    def test_other_queue_work_defers_before_any_reservation_or_transfer(self):
        self.queue = "555\n"
        with self.assertRaisesRegex(ValueError, "another HB job"):
            self.submit()
        self.assertEqual(reg.Registry(self.registry_root).snapshot()["claims"], {})
        self.assertEqual([v[0] for v in self.remote_calls], ["squeue"])
        self.run_mock.assert_not_called()

    def test_resource_mismatch_rejects_before_any_network(self):
        self.grant["jobs"]["environment"]["memory_MiB"] = 4096
        reg.write(self.authority_path, self.grant)
        with self.assertRaisesRegex(ValueError, "resources differ"):
            self.submit()
        self.remote_mock.assert_not_called()
        self.run_mock.assert_not_called()

    def test_successful_submission_has_durable_intent_and_exact_slurm_resources(self):
        claim = self.submit()
        self.assertEqual(claim["state"], "SUBMITTED")
        self.assertEqual(claim["job_id"], JOB)
        self.assertEqual([e["to"] for e in claim["events"]], ["STAGED", "SUBMISSION_INTENT", "SUBMITTED"])
        argv = next(args for args in self.remote_calls if args[0] == "sbatch")
        for arg in ("--export=NONE", "--nodes=1", "--ntasks=1", "--cpus-per-task=1",
                    "--no-requeue", "--mem=2048M", "--time=00:01:00"):
            self.assertIn(arg, argv)
        self.assertEqual(sum(args[0] == "sbatch" for args in self.remote_calls), 1)

    def test_staging_transfer_failure_retains_ambiguous_claim_and_no_submit(self):
        self.run_mock.side_effect = OSError("transfer interrupted")
        with self.assertRaises(OSError):
            self.submit()
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        self.assertFalse(any(v[0] == "sbatch" for v in self.remote_calls))
        scope = reg.Registry(self.registry_root).snapshot()["scopes"][self.grant["scope_id"]]
        self.assertEqual(scope["attempts"], 1)
        self.assertEqual(scope["reserved_CPU_seconds"], 60)

    def test_remote_manifest_mismatch_holds_claim_and_never_submits(self):
        real = self.fake_remote
        self.remote_mock.side_effect = lambda c, args: ("b" * 64) if args[0] == "sha256sum" else real(c, args)
        with self.assertRaisesRegex(ValueError, "manifest differs"):
            self.submit()
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        self.assertFalse(any(v[0] == "sbatch" for v in self.remote_calls))

    def test_lost_sbatch_response_is_spent_and_cannot_trigger_resubmission(self):
        real = self.fake_remote
        def lost(config, args):
            if args[0] == "sbatch":
                self.remote_calls.append(list(args))
                self.assertEqual(self.claim()["state"], "SUBMISSION_INTENT")
                raise subprocess.TimeoutExpired("sbatch", 120)
            return real(config, args)
        self.remote_mock.side_effect = lost
        with self.assertRaises(subprocess.TimeoutExpired):
            self.submit()
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")
        with self.assertRaisesRegex(ValueError, "claimed/spent"):
            self.submit()
        self.assertEqual(sum(v[0] == "sbatch" for v in self.remote_calls), 1)

    def test_malformed_sbatch_response_is_ambiguous(self):
        self.sbatch_response = "12345\n67890\n"
        with self.assertRaisesRegex(ValueError, "ambiguous sbatch"):
            self.submit()
        self.assertEqual(self.claim()["state"], "AMBIGUOUS")

    def test_failed_intent_publication_prevents_sbatch_and_keeps_existing_claim(self):
        original = reg.Registry.transition
        def transition(handle, key, expected, target, **fields):
            if target == "SUBMISSION_INTENT":
                raise OSError("intent publication failed")
            return original(handle, key, expected, target, **fields)
        with mock.patch.object(reg.Registry, "transition", new=transition):
            with self.assertRaises(OSError):
                self.submit()
        self.assertEqual(self.claim()["state"], "STAGED")
        self.assertFalse(any(v[0] == "sbatch" for v in self.remote_calls))

    def test_status_requires_full_accounting_and_an_empty_queue(self):
        claim = self.submit()
        self.queue = JOB + "|RUNNING|node1\n"
        receipt = self.receipt(claim)
        self.assertFalse(reg.read(receipt)["complete"])
        self.assertFalse(reg.read(receipt)["terminal"])
        self.queue = ""
        self.clock.return_value = NOW + 300
        self.sacct = "\n".join(accounting_text().splitlines()[:2])
        receipt = self.receipt(claim)
        self.assertFalse(reg.read(receipt)["complete"])

    def test_status_uses_own_queue_and_filters_other_jobs_by_exact_id(self):
        claim = self.submit()
        # The purged job is absent; similar IDs and other live user jobs must
        # remain visible in own_queue without being attributed to this claim.
        self.queue = JOB + "0|RUNNING|node2\n99999|PENDING|Resources\n"
        before = len(self.remote_calls)
        receipt = reg.read(self.receipt(claim))
        queries = [args for args in self.remote_calls[before:] if args[0] == "squeue"]
        self.assertEqual(queries, [["squeue", "-h", "-u", "jaguir26", "-o", "%i|%T|%R"]])
        self.assertTrue(all("-j" not in args for args in queries))
        self.assertEqual(receipt["own_queue"], self.queue)
        self.assertEqual(receipt["squeue"], "")
        self.assertTrue(receipt["terminal"])
        self.assertTrue(receipt["complete"])
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_exact_job_in_own_queue_blocks_completion_and_retains_other_queue_rows(self):
        claim = self.submit()
        own = JOB + "|RUNNING|node1"
        self.queue = "99999|PENDING|Resources\n" + own + "\n" + JOB + "0|RUNNING|node2\n"
        receipt = reg.read(self.receipt(claim))
        self.assertEqual(receipt["squeue"], own)
        self.assertEqual(receipt["own_queue"], self.queue)
        self.assertFalse(receipt["complete"])
        self.assertFalse(receipt["terminal"])

    def test_purged_queue_job_still_requires_complete_accounting(self):
        claim = self.submit()
        self.queue = "99999|RUNNING|node2\n"
        self.sacct = ""
        receipt = reg.read(self.receipt(claim))
        self.assertEqual(receipt["squeue"], "")
        self.assertFalse(receipt["complete"])
        self.assertFalse(receipt["terminal"])
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_status_poll_throttle_blocks_repeated_external_queries(self):
        claim = self.submit()
        self.receipt(claim)
        before = len(self.remote_calls)
        with self.assertRaises(ValueError):
            self.receipt(claim)
        self.assertEqual(len(self.remote_calls), before)

    def test_changed_controller_config_rejects_before_status_network(self):
        claim = self.submit()
        self.config["remote_root"] += "_changed"
        reg.write(self.config_path, self.config)
        before = len(self.remote_calls)
        with self.assertRaisesRegex(ValueError, "configuration changed"):
            self.receipt(claim)
        self.assertEqual(len(self.remote_calls), before)

    def test_changed_local_manifest_cannot_relax_status_accounting_limits(self):
        claim = self.submit()
        changed = reg.read(self.release / "release.json")
        changed["limits"]["wall_seconds"] = 1800
        reg.write(self.release / "release.json", changed)
        before = len(self.remote_calls)
        with self.assertRaises(ValueError):
            self.receipt(claim)
        self.assertEqual(len(self.remote_calls), before)

    def test_changed_local_manifest_cannot_relax_collection_limits(self):
        self.submit()
        receipt = self.receipt()
        changed = reg.read(self.release / "release.json")
        changed["limits"]["memory_MiB"] = 8192
        reg.write(self.release / "release.json", changed)
        self.run_mock.reset_mock()
        with self.assertRaises(ValueError):
            self.collect(receipt)
        self.run_mock.assert_not_called()
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_unknown_accounting_holds_claim_and_defers_all_retrieval(self):
        self.submit()
        self.sacct = ""
        receipt = self.receipt()
        self.run_mock.reset_mock()
        with self.assertRaisesRegex(ValueError, "incomplete/unknown"):
            self.collect(receipt)
        self.run_mock.assert_not_called()
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_receipt_job_and_release_identities_cannot_be_substituted(self):
        self.submit()
        receipt = self.receipt()
        original = reg.read(receipt)
        for field in ("task_key", "job_id", "release_sha256"):
            changed = dict(original, **{field: "replacement"})
            path = self.root / ("bad-" + field + ".json")
            reg.write(path, changed)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "identity"):
                self.collect(path)
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_partial_download_retains_claim_and_no_publication(self):
        self.submit()
        receipt = self.receipt()
        def interrupted(argv, timeout=120):
            destination = Path(argv[-1])
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "build-report.json").write_text("truncated")
            raise OSError("interrupted download")
        self.run_mock.side_effect = interrupted
        with self.assertRaises(OSError):
            self.collect(receipt)
        self.assertEqual(self.claim()["state"], "SUBMITTED")
        self.assertFalse((self.root / "publication").exists())
        self.assertTrue((self.root / "incoming" / "outputs" / "build-report.json").exists())
        self.run_mock.side_effect = self.fake_transfer
        result = self.collect(receipt)
        self.assertEqual(result["state"], "COLLECTED")
        self.assertTrue(result["application_accepted"])

    def test_scheduler_success_without_a_complete_output_seal_holds_claim(self):
        self.submit()
        receipt = self.receipt()
        real = self.fake_transfer
        def unsealed(argv, timeout=120):
            value = real(argv, timeout)
            if "/outputs/" in argv[-2]:
                (Path(argv[-1]) / "completed_evidence.json").unlink()
            return value
        self.run_mock.side_effect = unsealed
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.collect(receipt)
        self.assertEqual(self.claim()["state"], "SUBMITTED")
        self.assertFalse((self.root / "publication").exists())

    def test_validated_collection_publishes_once_and_does_not_release_a_duplicate_task(self):
        self.submit()
        result = self.collect()
        self.assertEqual(result["state"], "COLLECTED")
        self.assertTrue(result["application_accepted"])
        self.assertTrue((self.root / "publication" / "outputs" / "completed_evidence.json").is_file())
        before = self.run_mock.call_count
        with self.assertRaises(ValueError):
            self.collect(self.root / "status-0.json")
        self.assertEqual(self.run_mock.call_count, before)
        with self.assertRaisesRegex(ValueError, "claimed/spent"):
            self.submit()

    def test_existing_publication_is_never_overwritten(self):
        self.submit()
        receipt = self.receipt()
        destination = self.root / "publication"
        destination.mkdir()
        (destination / "retained").write_text("original")
        self.run_mock.reset_mock()
        with self.assertRaises(FileExistsError):
            self.collect(receipt, destination=destination)
        self.run_mock.assert_not_called()
        self.assertEqual((destination / "retained").read_text(), "original")
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_symlinked_incoming_is_rejected_before_download(self):
        self.submit()
        receipt = self.receipt()
        incoming = self.root / "incoming"
        incoming.mkdir()
        (incoming / "outside").symlink_to(self.identity_path)
        self.run_mock.reset_mock()
        with self.assertRaises(ValueError):
            self.collect(receipt, incoming=incoming)
        self.run_mock.assert_not_called()
        self.assertEqual(self.claim()["state"], "SUBMITTED")

    def test_terminal_failed_job_can_reconcile_without_refunding_any_reservation(self):
        self.submit()
        self.sacct = accounting_text("FAILED", "1:0")
        receipt = self.receipt()
        result = self.collect(receipt)
        self.assertEqual(result["state"], "FAILED_RECONCILED")
        self.assertFalse(result["application_accepted"])
        self.assertTrue((self.root / "publication" / "accounting.json").exists())
        scope = reg.Registry(self.registry_root).snapshot()["scopes"][self.grant["scope_id"]]
        self.assertEqual((scope["attempts"], scope["reserved_CPU_seconds"]), (1, 60))
        with self.assertRaises(ValueError):
            self.submit()


if __name__ == "__main__":
    unittest.main()
