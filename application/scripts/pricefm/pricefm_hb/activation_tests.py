"""Metadata-only independent tests of immutable authority/compute activation."""
import copy
import datetime as dt
import os
from pathlib import Path
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest import mock
from . import activation as a, registry as r, policy, handoff


class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.now = time.time()
        self.start = self.now - 10
        self.sources = a.executed_sources("COST_ONLY")
        self.allocation = {"job_id": "868900", "node": "node-13"}
        self.authority = dict(schema=a.AUTHORITY_SCHEMA, purpose="COST_ONLY", study="FI",
            role="FI_COST_ONLY_BENCHMARK", issuer=a.OWNER,
            controller=a.OWNER, plan_sha256="a" * 64, executed_sources=self.sources,
            reference_numerical_environment=a.REFERENCE_NUMERICAL_ENV, automatic_retry=False,
            new_model_fits=0, official_origins=0, promotion=False, issued_epoch=self.now - 110,
            calendar_expires_epoch=self.now + 1800, max_queue_seconds=180,
            resources=dict(cpus=1, memory_MiB=4096, wall_seconds=1200, cpu_seconds=1200),
            slurm_job_id=self.allocation["job_id"], node="node-13", release_sha256="b" * 64,
            scientific_exclusion_key="FI|fixed-cost", proof_manifest={})

    def stage(self, name, value):
        path = self.root / name
        r.write(path, value)
        pin = dict(path="/original/muscat/" + name, sha256=r.digest(path))
        self.authority["proof_manifest"][pin["path"]] = dict(relative_path=name,
            sha256=pin["sha256"], bytes=path.stat().st_size)
        return pin

    def worker_fixture(self, purpose="COST_ONLY"):
        if purpose == "CONTROL_TEST":
            self.sources = a.executed_sources(purpose)
            self.authority.update(purpose=purpose, study="TEST", executed_sources=self.sources,
                issued_epoch=self.now - 610, max_queue_seconds=1800,
                scientific_exclusion_key="TEST|fixed-fixture",
                resources=dict(cpus=1, memory_MiB=4096, wall_seconds=120, cpu_seconds=120))
            self.authority.pop("role", None)
        self.authority["policy_pin"] = self.stage("policy.json", {"fixture_matrix": True,
            "execution_sources": [{"path": "/frozen/code/" + name, "sha256": sha} for name,sha in self.sources.items()]})
        identity = r.identity(self.authority)
        # READY depends on authority identity, so its allowlist is fresh activation evidence.
        ready = dict(schema=a.READY_SCHEMA, job_id=self.allocation["job_id"], node="node-13",
            allocation=self.allocation, authority_identity_sha256=identity,
            allocation_start_epoch=self.start, release_sha256="b" * 64, observed_epoch=self.now - 2)
        manifest = self.authority["proof_manifest"]
        self.authority["proof_manifest"] = dict(manifest)
        ready_pin = self.stage("ready.json", ready)
        closed_pin = self.stage("handoff.json", {"observed_epoch": self.now - 1, "owner": "UNKNOWN"})
        hosts_pin = self.stage("hosts.json", dict(status="NO_OVERLAP", controller=a.OWNER,
            observed_epoch=self.now - 1, hosts=[a.OWNER,"jerez.be.ucsc.edu","hb.ucsc.edu"],
            scientific_exclusion_key=self.authority["scientific_exclusion_key"], overlapping_scientific_claims=[]))
        extra = {k: v for k, v in self.authority["proof_manifest"].items() if k not in manifest}
        self.authority["proof_manifest"] = manifest
        self.activation = dict(schema=a.ACTIVATION_SCHEMA, status="ACTIVATED_ONCE", controller=a.OWNER,
            authority_identity_sha256=r.identity(self.authority), job_id=self.allocation["job_id"],
            node="node-13", plan_sha256="a" * 64, observed_epoch=self.now - 1,
            ready=ready_pin, handoff_receipt=closed_pin, all_hosts_observation=hosts_pin,
            started_epoch=self.start,
            expires_epoch=self.start + self.authority["resources"]["wall_seconds"], proof_manifest=extra)
        self.assertEqual(identity, r.identity(self.authority))

    def validate(self):
        return a.validate_worker(self.authority, self.activation, self.allocation,
                                 self.authority["purpose"], "a" * 64, self.sources)

    def worker_patches(self):
        stack = __import__("contextlib").ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(a.time, "time", return_value=self.now))
        stack.enter_context(mock.patch.object(a, "require_compute", return_value=self.allocation))
        stack.enter_context(mock.patch.object(a, "allocation_start", return_value=self.start))
        stack.enter_context(mock.patch.object(a, "validate_qualification", return_value={"qualified": True}))
        stack.enter_context(mock.patch.object(policy, "validate_policy"))
        self.handoff_validator = stack.enter_context(mock.patch.object(handoff, "validate_handoff_receipt"))
        stack.enter_context(mock.patch.dict(os.environ, dict(a.THREAD_ENV, **a.REFERENCE_NUMERICAL_ENV,
            PRICEFM_RELEASE_ROOT=str(self.root))))

    def test_delayed_queue_uses_fresh_READY_without_refreshing_authority_clock(self):
        self.worker_fixture("CONTROL_TEST"); self.worker_patches()
        result = self.validate()
        self.assertEqual(result["started_epoch"], self.start)
        self.assertGreater(self.now - self.authority["issued_epoch"], 300)
        self.handoff_validator.assert_called_once_with(mock.ANY, mock.ANY, now=self.now, check_live=False)

    def test_stale_activation_and_estimated_queue_overrun_block(self):
        self.worker_fixture(); self.worker_patches()
        self.activation["observed_epoch"] = self.now - 301
        with self.assertRaises(a.ActivationError): self.validate()
        self.activation["observed_epoch"] = self.now - 1
        self.authority["max_queue_seconds"] = 60
        self.worker_fixture()  # Rebuild identity/proofs so the valid queue cap is the failing condition.
        with self.assertRaises(a.ActivationError): self.validate()

    def test_live_EE_unknown_owner_decision_is_delegated_and_not_ignored(self):
        self.worker_fixture(); self.worker_patches()
        self.handoff_validator.side_effect = handoff.HandoffError("unknown owner")
        with self.assertRaisesRegex(handoff.HandoffError, "unknown owner"): self.validate()

    def test_proof_bytes_and_source_edits_block_before_payload(self):
        self.worker_fixture(); self.worker_patches()
        (self.root / "handoff.json").write_text("{}")
        with self.assertRaises(a.ActivationError): self.validate()
        self.assertFalse(self.handoff_validator.called)
        wrong = dict(self.sources, **{"science.py": "f" * 64})
        with self.assertRaises(a.ActivationError):
            a.validate_authority(self.authority, "COST_ONLY", "a" * 64, wrong, now=self.now)

    def test_READY_allocation_start_and_notification_latency_are_exact(self):
        self.worker_fixture(); self.worker_patches()
        self.activation["started_epoch"] += 1
        with self.assertRaises(a.ActivationError): self.validate()
        self.activation["started_epoch"] = self.start
        self.activation["observed_epoch"] = self.now + 1
        with self.assertRaises(a.ActivationError): self.validate()

    def test_original_proof_cannot_be_replaced_by_activation(self):
        old = {"proof_manifest": {"/x": {"sha256": "a" * 64}}}
        with self.assertRaises(a.ActivationError):
            a.merge_proofs(old, {"proof_manifest": {"/x": {"sha256": "b" * 64}}})

    def test_policy_source_closure_requires_every_actual_module_and_hash(self):
        pins=[dict(path='/frozen/'+name,sha256=sha) for name,sha in self.sources.items()]
        a.validate_policy_sources({'execution_sources':pins},self.sources)
        with self.assertRaises(a.ActivationError):a.validate_policy_sources({'execution_sources':pins[:-1]},self.sources)
        wrong=copy.deepcopy(pins);wrong[0]['sha256']='f'*64
        with self.assertRaises(a.ActivationError):a.validate_policy_sources({'execution_sources':wrong},self.sources)
        duplicate=pins+[dict(path='/other/'+Path(pins[0]['path']).name,sha256='e'*64)]
        with self.assertRaises(a.ActivationError):a.validate_policy_sources({'execution_sources':duplicate},self.sources)

    def test_remote_pin_resolution_preserves_original_JSON_bytes(self):
        pin = self.stage("json.json", {"foreign": {"path": "/muscat/original"}})
        self.assertEqual(a.read_pin(pin, self.authority, root=self.root)["foreign"]["path"], "/muscat/original")
        other = dict(pin, path="/unlisted/original.json")
        with self.assertRaises(a.ActivationError): a.read_pin(other, self.authority, root=self.root)

    def test_proof_traversal_and_symlink_are_rejected(self):
        pin = self.stage("json.json", {})
        self.authority["proof_manifest"][pin["path"]]["relative_path"] = "../json.json"
        with self.assertRaises(a.ActivationError): a.read_pin(pin, self.authority, root=self.root)
        (self.root / "link").symlink_to(self.root / "json.json")
        self.authority["proof_manifest"][pin["path"]]["relative_path"] = "link"
        with self.assertRaises(ValueError): a.read_pin(pin, self.authority, root=self.root)

    def test_actual_Slurm_start_requires_RUNNINGS_server_and_environment_agreement(self):
        iso = dt.datetime.fromtimestamp(int(self.start), dt.timezone.utc).replace(tzinfo=None).isoformat()
        line = "JobId=868900 JobState=RUNNING NodeList=node-13 NumCPUs=1 StartTime=" + iso
        runner = mock.Mock(return_value=SimpleNamespace(stdout=line))
        actual = a.allocation_start(self.allocation, runner, {"SLURM_JOB_START_TIME": str(int(self.start))}, self.now)
        self.assertEqual(actual, int(self.start))
        self.assertEqual(runner.call_args.kwargs["env"]["TZ"], "UTC")
        for wrong in (line.replace("RUNNING", "PENDING"), line.replace("node-13", "node-07"), line.replace("NumCPUs=1", "NumCPUs=2")):
            with self.subTest(wrong=wrong), self.assertRaises(a.ActivationError):
                a.allocation_start(self.allocation, lambda *x, **y: SimpleNamespace(stdout=wrong),
                                   {"SLURM_JOB_START_TIME": str(int(self.start))}, self.now)
        with self.assertRaises(a.ActivationError):
            a.allocation_start(self.allocation, runner, {"SLURM_JOB_START_TIME": str(int(self.start) + 2)}, self.now)

    def test_finite_authority_cannot_renew_or_expand_CPU(self):
        for patch in ({"calendar_expires_epoch": self.now + 9000}, {"issued_epoch": self.now + 1},
                      {"automatic_retry": True}, {"resources": dict(self.authority["resources"], cpus=2)}):
            with self.subTest(patch=patch), self.assertRaises(a.ActivationError):
                a.validate_authority(dict(self.authority, **patch), "COST_ONLY", "a" * 64, self.sources, self.now)


if __name__ == "__main__": unittest.main()
