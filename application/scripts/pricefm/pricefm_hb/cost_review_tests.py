"""Independent offline failure regressions for the prospective cost controller.

All external commands and model arithmetic use the existing wire-test doubles.
These tests do not grant or launch FI/DK2 work.
"""
from __future__ import annotations

from pathlib import Path
import unittest
from unittest import mock

from . import cost_control as c
from . import cost_control_tests as fixtures


class IndependentCostReviewTests(unittest.TestCase):
    def setUp(self):
        self.wire = fixtures.CostControlTests(methodName="runTest")
        self.wire.setUp()
        self.addCleanup(self.wire.doCleanups)

    def worker_authority_result(self, wire, authority):
        remote_root = wire.claim()["remote_root"]
        original_metadata = c.p.read_metadata
        def mapped(path):
            value = str(path)
            return wire.release / value[len(remote_root) + 1:] if value.startswith(remote_root + "/") else Path(path)
        with mock.patch.object(c.b, "digest", side_effect=lambda path: c.r.digest(mapped(path))), \
             mock.patch.object(c.p, "read_metadata", side_effect=lambda path: original_metadata(mapped(path))):
            return c.b.validate_authority(authority, wire.plan, wire.plan_pin["sha256"], fixtures.ALLOCATION, fixtures.NOW)

    def assert_worker_authority_rejects(self, wire, authority):
        with self.assertRaises(c.b.BenchmarkError):
            self.worker_authority_result(wire, authority)

    def test_positive_issued_authority_passes_the_same_worker_validation_path(self):
        w = self.wire
        w.authorize_release()
        authority = c.r.read(w.release / "authorization/authority.json")
        gate = self.worker_authority_result(w, authority)
        self.assertTrue(gate["EE"]["assessment_accepted"])
        self.assertTrue(gate["parity"]["accepted"])

    def test_status_uses_user_queue_and_exact_id_when_the_cost_job_is_purged(self):
        w = self.wire
        claim = w.authorize_release()
        w.queue = fixtures.JOB + "0|RUNNING|node-08\n99999|PENDING|Resources\n"
        before = len(w.remote_calls)
        receipt = c.status(claim["task_key"], w.config_path, w.root / "status.json")
        queries = [args for args in w.remote_calls[before:] if args[0] == "squeue"]
        self.assertEqual(queries, [["squeue", "-h", "-u", "jaguir26", "-o", "%i|%T|%R"]])
        self.assertEqual(receipt["own_queue"], w.queue)
        self.assertEqual(receipt["squeue"], "")
        self.assertTrue(receipt["complete"])

    def test_changed_local_release_blocks_authority_issuance_before_transfer(self):
        w = self.wire
        claim = w.submit()
        release = c.r.read(w.release / "release.json")
        release["runtime_python"] = "/mnt/beegfs/home/jaguir26/unqualified/runtime/venv/bin/python"
        c.r.write(w.release / "release.json", release)
        before = (len(w.remote_calls), len(w.transfer_calls))
        with self.assertRaises(c.GateError):
            c.issue_authority(claim["task_key"], w.config_path)
        self.assertEqual((len(w.remote_calls), len(w.transfer_calls)), before)
        self.assertEqual(w.claim()["state"], "HELD")

    def test_changed_local_release_blocks_status_before_network(self):
        w = self.wire
        claim = w.authorize_release()
        release = c.r.read(w.release / "release.json")
        release["memory_mib"] = 8192
        c.r.write(w.release / "release.json", release)
        before = len(w.remote_calls)
        with self.assertRaises(c.GateError):
            c.status(claim["task_key"], w.config_path, w.root / "status.json")
        self.assertEqual(len(w.remote_calls), before)

    def test_changed_local_release_blocks_collection_before_download(self):
        w = self.wire
        claim = w.authorize_release()
        w.run_worker()
        receipt = w.root / "status.json"
        c.status(claim["task_key"], w.config_path, receipt)
        release = c.r.read(w.release / "release.json")
        release["memory_mib"] = 8192
        c.r.write(w.release / "release.json", release)
        before = len(w.transfer_calls)
        with self.assertRaises(c.GateError):
            c.collect(claim["task_key"], w.config_path, receipt, w.root / "incoming", w.root / "publication")
        self.assertEqual(len(w.transfer_calls), before)
        self.assertEqual(w.claim()["state"], "SUBMITTED")

    def test_worker_rejects_a_cross_server_proof_from_a_foreign_controller(self):
        w = self.wire
        w.authorize_release()
        path = w.release / "authorization/cross-server-claim.json"
        cross = c.r.read(path)
        cross["controller"] = "jerez.be.ucsc.edu"
        c.r.write(path, cross)
        authority = c.r.read(w.release / "authorization/authority.json")
        authority["cross_server_claim"]["sha256"] = c.r.digest(path)
        self.assert_worker_authority_rejects(w, authority)

    def test_worker_rejects_operational_EE_failure_even_with_consistent_hashes(self):
        w = self.wire
        w.authorize_release()
        authority = c.r.read(w.release / "authorization/authority.json")
        ee_path = w.release / "proofs/EE_completion_receipt.json"
        ee = c.r.read(ee_path)
        remote_root = w.claim()["remote_root"]
        assessment_path = w.release / ee["scientific_assessment"]["path"][len(remote_root) + 1:]
        assessment = c.r.read(assessment_path)
        assessment["disposition"] = "STOP_OPERATIONAL_FAILURE"
        c.r.write(assessment_path, assessment)
        ee["scientific_assessment"]["sha256"] = c.r.digest(assessment_path)
        c.r.write(ee_path, ee)
        authority["EE_completion_receipt"]["sha256"] = c.r.digest(ee_path)
        self.assert_worker_authority_rejects(w, authority)

    def test_worker_rejects_a_partial_matched_EE_set_even_with_consistent_hashes(self):
        w = self.wire
        w.authorize_release()
        authority = c.r.read(w.release / "authorization/authority.json")
        ee_path = w.release / "proofs/EE_completion_receipt.json"
        ee = c.r.read(ee_path)
        remote_root = w.claim()["remote_root"]
        assessment_path = w.release / ee["scientific_assessment"]["path"][len(remote_root) + 1:]
        assessment = c.r.read(assessment_path)
        required = ee["required_task_names"][:1]
        assessment["required_task_names"] = required
        c.r.write(assessment_path, assessment)
        ee.update(required_task_names=required, completed_task_names=required,
                  scientific_assessment=dict(ee["scientific_assessment"], sha256=c.r.digest(assessment_path)))
        c.r.write(ee_path, ee)
        authority["EE_completion_receipt"]["sha256"] = c.r.digest(ee_path)
        self.assert_worker_authority_rejects(w, authority)

    def test_publication_followed_by_ledger_failure_keeps_claim_unaccepted(self):
        w = self.wire
        claim = w.authorize_release()
        w.run_worker()
        receipt = w.root / "status.json"
        c.status(claim["task_key"], w.config_path, receipt)
        original = c.Ledger.transition
        def failed_transition(handle, key, expected, target, **fields):
            if target == "COLLECTED_COST_ONLY":
                raise OSError("synthetic registry publication failure")
            return original(handle, key, expected, target, **fields)
        with mock.patch.object(c.Ledger, "transition", new=failed_transition):
            with self.assertRaises(OSError):
                c.collect(claim["task_key"], w.config_path, receipt, w.root / "incoming", w.root / "publication")
        self.assertTrue((w.root / "publication/outputs/worker_evidence.json").is_file())
        self.assertEqual(w.claim()["state"], "SUBMITTED")
        self.assertEqual(w.claim()["reserved_CPU_seconds"], 1200)
        with self.assertRaises(c.GateError):
            c.Ledger().reserve(w.plan, w.plan_pin["sha256"], "a" * 64, "b" * 64, "/tmp/new", "/remote/new")


if __name__ == "__main__":
    unittest.main()
