"""Metadata-only negative tests; no guard observation or numerical runtime."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import local_readiness as m


def fixture():
    return {"schema": m.SCHEMA, "purpose": "METADATA_PREREQUISITES_ONLY", "affinity": [31],
            "signals": 0, "optimizer_invocations": 0, "maximum_CPU_seconds": 20,
            "maximum_wall_seconds": 60, "guard": {"path": str(m.GUARD), "sha256": m.GUARD_SHA},
            "peer_census": {"path": str(m.CENSUS), "sha256": m.CENSUS_SHA},
            "runtime_binding": {"path": str(m.RUNTIME), "sha256": m.RUNTIME_SHA},
            "numerical_admission": False, "new_peer_allowances": []}


class RequestTests(unittest.TestCase):
    def test_metadata_request_does_not_admit_numerical_work(self):
        m.validate_request(fixture(), {"issued_epoch": 100, "expires_epoch": 1000}, now=200)

    def test_no_expired_or_short_window(self):
        for issued, expiry in [(201,1000), (100,260), (100,199)]:
            with self.assertRaises(m.ReadinessError):
                m.validate_request(fixture(), {"issued_epoch": issued, "expires_epoch": expiry}, now=200)

    def test_no_scientific_execution_or_new_peer_allowances(self):
        changes = [("purpose","FIT"),("affinity",[30]),("signals",1),("optimizer_invocations",1),
                   ("maximum_CPU_seconds",21),("maximum_wall_seconds",61),
                   ("numerical_admission",True),("new_peer_allowances",[{"pid":123}])]
        for key, value in changes:
            request = fixture(); request[key] = value
            with self.subTest(key=key), self.assertRaises(m.ReadinessError):
                m.validate_request(request, {"issued_epoch":100,"expires_epoch":1000}, now=200)

    def test_guard_census_or_runtime_cannot_be_relabelled(self):
        for key in ("guard","peer_census","runtime_binding"):
            request = fixture(); request[key] = dict(request[key], sha256="a"*64)
            with self.subTest(key=key), self.assertRaises(m.ReadinessError):
                m.validate_request(request, {"issued_epoch":100,"expires_epoch":1000}, now=200)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/dev/shm")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def metadata(self, value):
        p = self.root/"evidence.json"; p.write_text(value); return m.pin(p)

    def test_reject_changed_pinned_bytes(self):
        p = self.root/"source.py"; p.write_text("first")
        binding = m.pin(p); p.write_text("second")
        with self.assertRaises(m.ReadinessError): m.verify(binding)

    def test_reject_symlink_and_parent_escape(self):
        p = self.root/"file"; p.write_text("original")
        q = self.root/"link"; q.symlink_to(p)
        for path in (q,self.root/".."/"file",Path("relative")):
            with self.assertRaises(m.ReadinessError): m.pin(path)

    def test_reject_directory_or_oversized_file(self):
        with self.assertRaises(m.ReadinessError): m.read_bytes(self.root)
        p = self.root/"large"; p.write_bytes(b"abcd")
        with self.assertRaises(m.ReadinessError): m.read_bytes(p,maximum=3)

    def test_duplicate_nonfinite_and_overflow_json_fail(self):
        for text in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":1e999}'):
            binding = self.metadata(text)
            with self.subTest(text=text), self.assertRaises(m.ReadinessError): m.read(binding)

    def test_only_json_may_be_parsed(self):
        p = self.root/"target.rds"; p.write_text('{}')
        with self.assertRaises(m.ReadinessError): m.read(m.pin(p))

    def test_output_cannot_overwrite_prior_receipt(self):
        p = self.root/"receipt.json"; m.save(p,{"a":1})
        with self.assertRaises(FileExistsError): m.save(p,{"a":2})
        self.assertEqual(json.loads(p.read_text()),{"a":1})

    def test_runtime_hashes_deduplicate_and_detect_conflicts(self):
        p = self.root/"R"; p.write_text("ELF placeholder")
        sha = m.pin(p)["sha256"]
        b = {"package_path":str(self.root),"actual_executable":str(p),"actual_executable_sha256":sha,
             "Rscript":str(p),"Rscript_sha256":sha,"loaded_shared_object_sha256":{},"package_files_sha256":{"R":sha}}
        self.assertEqual(len(m.runtime_targets(b)),1)
        self.assertEqual(m.audit_runtime(b)["status"],"PINNED_INSTALLED_BYTES_MATCH")
        b["package_files_sha256"]["R"]="a"*64
        with self.assertRaises(m.ReadinessError): m.runtime_targets(b)

    def test_runtime_traversal_is_not_a_target_data_reader(self):
        b = {"package_path":str(self.root),"actual_executable":"/bin/R","actual_executable_sha256":"a"*64,
             "Rscript":"/bin/Rscript","Rscript_sha256":"b"*64,"loaded_shared_object_sha256":{},"package_files_sha256":{"../target.rds":"c"*64}}
        with self.assertRaises(m.ReadinessError): m.runtime_targets(b)

    def test_runtime_byte_match_does_not_claim_startup_or_parity(self):
        p = self.root/"R"; p.write_text("only bytes")
        sha=m.pin(p)["sha256"]
        b = {"package_path":str(self.root),"actual_executable":str(p),"actual_executable_sha256":sha,
             "Rscript":str(p),"Rscript_sha256":sha,"loaded_shared_object_sha256":{},"package_files_sha256":{}}
        result=m.audit_runtime(b)
        for key in ("R_started","numerical_parity_proved","scientific_dependency_startup_proved"):
            self.assertIs(result[key],False)

    def test_runtime_missing_file_is_evidence_of_failure(self):
        b = {"package_path":str(self.root),"actual_executable":str(self.root/"missing"),"actual_executable_sha256":"a"*64,
             "Rscript":str(self.root/"missing"),"Rscript_sha256":"a"*64,"loaded_shared_object_sha256":{},"package_files_sha256":{}}
        result=m.audit_runtime(b)
        self.assertEqual(result["status"],"PINNED_INSTALLED_BYTES_DIFFER")
        self.assertEqual(len(result["failures"]),1)


if __name__ == "__main__":
    unittest.main()
