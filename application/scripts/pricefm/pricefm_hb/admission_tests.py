"""R157 self-exclusion, node capacity and read-only request integration tests."""
import copy
import json
from pathlib import Path
import signal
from unittest import mock
import unittest
from . import activation, admission as ad, policy, registry as r, readiness as rd
from .policy_tests import PolicyFixture


def node(name, *, cpus=24, allocated=0, real=122880, memory=0, free=100000, state="IDLE"):
    return ("NodeName=" + name + " CPUEfctv=" + str(cpus) + " CPUTot=" + str(cpus)
            + " CPUAlloc=" + str(allocated) + " RealMemory=" + str(real) + " AllocMem=" + str(memory)
            + " FreeMem=" + str(free) + " State=" + state + " Partitions=128x24")


class AdmissionTests(PolicyFixture):
    def setUp(self):
        super().setUp()
        self.central = self.root / "canonical"
        self.central.mkdir()
        patch = mock.patch.object(ad, "CENTRAL", self.central)
        patch.start()
        self.addCleanup(patch.stop)
        self.resources = {"cpus": 1, "memory_MiB": 4096, "wall_seconds": 1200, "cpu_seconds": 1200}

    def claim(self, key="task-one", job="123", purpose="COST_ONLY", state="SUBMITTED", exclusion="FI-key"):
        root = self.root / (key + "-release")
        root.mkdir()
        value = {"task_key": key, "task": {"purpose": purpose, "study": "FI", "plan_sha256": "a" * 64,
                  "scientific_exclusion_key": exclusion}, "scope_id": "scope-" + key, "state": state,
                 "job_id": job, "release_path": str(root), "resources": self.resources,
                 "remote_root": "/mnt/beegfs/home/jaguir26/" + key, "policy_pin": self.policy_pin}
        release = {"task_key": key, "plan_sha256": "a" * 64, "remote_root": value["remote_root"],
                   "resources": self.resources, "node": "node-13"}
        value["release_sha256"] = self.write(key + "-release/release.json", release)["sha256"]
        return value

    def ledger(self, claims):
        (self.central / "activation_registry.lock").touch()
        r.write(self.central / "activation_registry.json", {"schema": ad.LIFECYCLE_SCHEMA,
                  "owner": policy.OWNER, "claims": {c["task_key"]: c for c in claims}, "spent_tests": []})

    def test_absent_ledger_is_observed_without_creation(self):
        ad.canonical_claims(self.packet, "a" * 64, "FI-key")
        self.assertEqual(list(self.central.iterdir()), [])

    def test_self_exclusion_requires_exact_durable_claim_and_release(self):
        own = self.claim()
        self.ledger([own])
        _, accepted, peers = ad.canonical_claims(self.packet, "a" * 64, "FI-key", own)
        self.assertEqual(accepted, own)
        self.assertEqual(peers, [])
        for changed in (dict(own, state="ACTIVATED"), dict(own, job_id="124")):
            with self.assertRaises(ad.AdmissionError):
                ad.canonical_claims(self.packet, "a" * 64, "FI-key", changed)
        Path(own["release_path"], "release.json").write_text("{}")
        with self.assertRaises(ad.AdmissionError):
            ad.canonical_claims(self.packet, "a" * 64, "FI-key", own)

    def test_ambiguous_unknown_and_same_science_peer_claims_block(self):
        for state, purpose in (("AMBIGUOUS", "CACHED_NORMAL_COMPONENT"), ("SUBMITTED", "COST_ONLY")):
            own = self.claim(key="peer-" + state, purpose=purpose, state=state)
            self.ledger([own])
            with self.assertRaises(ad.AdmissionError):
                ad.canonical_claims(self.packet, "a" * 64, "FI-key")

    def test_dynamic_node_selection_rejects_old_memory_starved_node(self):
        snapshot = {"slurm": {"nodes": node("node-07", memory=120832) + "\n" + node("node-13"),
                              "partition": "State=UP MaxTime=UNLIMITED"}}
        chosen = ad.select_node(snapshot, 4096, 1200)
        self.assertEqual(chosen["node"], "node-13")
        self.assertFalse(chosen["self_allocation_added_back"])

    def test_activation_adds_back_only_its_verified_allocation_and_keeps_node(self):
        own = self.claim()
        snapshot = {"slurm": {"nodes": node("node-13", cpus=1, allocated=1, real=4096, memory=4096, free=4096)
                              + "\n" + node("node-14"), "partition": "State=UP MaxTime=UNLIMITED",
                              "self_job": "JobId=123 JobState=RUNNING NodeList=node-13 NumCPUs=1 AllocTRES=cpu=1,mem=4G,node=1"}}
        chosen = ad.select_node(snapshot, 4096, 1200, own)
        self.assertEqual(chosen["node"], "node-13")
        self.assertEqual(chosen["available_cpus"], 1)
        self.assertEqual(chosen["available_memory_mib"], 4096)
        with self.assertRaises(ad.AdmissionError):
            ad.select_node(dict(snapshot, slurm=dict(snapshot["slurm"], nodes=node("node-13", cpus=1, allocated=1, real=4096, memory=4096, free=4096))), 4096, 1200)

    def test_self_addback_cannot_use_wrong_job_node_cpu_or_memory(self):
        own = self.claim()
        fields = "JobId=123 JobState=RUNNING NodeList=node-13 NumCPUs=1 AllocTRES=cpu=1,mem=4G,node=1"
        for wrong in (fields.replace("123", "124"), fields.replace("RUNNING", "PENDING"),
                      fields.replace("node-13", "node-14"), fields.replace("NumCPUs=1", "NumCPUs=2"),
                      fields.replace("mem=4G", "mem=8G")):
            snap = {"slurm": {"nodes": node("node-13"), "partition": "State=UP MaxTime=UNLIMITED", "self_job": wrong}}
            with self.assertRaises(ad.AdmissionError):
                ad.select_node(snap, 4096, 1200, own)

    def test_down_drain_or_too_short_partition_blocks(self):
        for state in ("DOWN", "MIXED+DRAIN", "FAIL", "MAINT"):
            with self.assertRaises(ad.AdmissionError):
                ad.select_node({"slurm": {"nodes": node("node-13", state=state),
                               "partition": "State=UP MaxTime=UNLIMITED"}}, 4096, 1200)
        with self.assertRaises(ad.AdmissionError):
            ad.select_node({"slurm": {"nodes": node("node-13"), "partition": "State=UP MaxTime=00:10:00"}}, 4096, 1200)

    def test_free_memory_guard_is_not_bypassed_by_scheduler_reservation(self):
        with self.assertRaises(ad.AdmissionError):
            ad.select_node({"slurm": {"nodes": node("node-13", free=1024), "partition": "State=UP MaxTime=UNLIMITED"}}, 4096, 1200)

    def refresh_fixture(self):
        plan = {"study": "FI", "claim": {"scientific_exclusion_key": "FI-key"}, "inventory": {"bytes": 100}}
        plan_pin = self.write("cost-plan.json", plan)
        root = self.root / "qualification"
        outputs = root / "outputs"
        (outputs / "TEST/parity").mkdir(parents=True)
        self.write("qualification/outputs/TEST/parity/completed_evidence.json", {"fixture": True})
        self.write("qualification/outputs/environment-runtime.json", {"fixture": True})
        runtime = self.write("runtime.json", {"executable": "/mnt/beegfs/home/jaguir26/r157/runtime/venv/bin/python"})
        parity = self.write("parity.json", {"execution": {"fixture_manifest_sha256": "b" * 64}})
        sizing = self.write("sizing.json", {"study": "FI", "plan_sha256": plan_pin["sha256"],
                  "memory_mib": 4096, "minimum_required_memory_mib": 1400, "maximum_parent_p": 961})
        calendar = self.write("calendar.json", {"study": "FI", "plan_sha256": plan_pin["sha256"],
                  "status": "PROPOSED_FINITE_COST_WINDOW_NOT_AUTHORITY", "authority_issued": False,
                  "claim_created": False, "created_epoch": self.now, "expires_epoch": self.now + 7200})
        closure = self.write("closure.json", {"status": "PASS_CLOSED_CACHED_SCOPE_PRESERVED", "errors": []})
        review = self.write("review.json", {"fixture": True})
        delivery = self.write("delivery.json", {"fixture": True})
        config = {"schema": rd.SCHEMA, "site_config": "site.json", "runtime_publication": str(root),
                  "parity_publication": str(root), "adapter_reviews": {"FI": review}, "delivered_EE_report": delivery,
                  "legacy_registries": [{"host": policy.OWNER, "path": str(self.root / "old-closed.json")}],
                  "legacy_outputs": {}, "known_legacy_closure_audit": closure,
                  "sizing_evidence": {"FI": sizing}, "calendar_evidence": {"FI": calendar}}
        common = {"observed_epoch": self.now, "matching_processes": [], "unreadable_own_processes": []}
        muscat = dict(common, registries=[{"path": str(self.root / "old-closed.json"), "present": True,
                    "value": {"status": "CLOSED_NO_NEW_WORK"}},
                    {"path": str(self.central / "cost_only_registry.json"), "present": False}])
        jerez = dict(common, registries=[])
        hb = dict(common, registries=[], free_disk_bytes=10 * 1024**3,
                  slurm={"nodes": node("node-07", memory=120832) + "\n" + node("node-13"),
                         "partition": "State=UP MaxTime=UNLIMITED", "queue": ""})
        patches = [mock.patch.object(ad.cost, "load_plan", return_value=plan),
                   mock.patch.object(ad.ctl, "config", return_value={"remote_root": "/mnt/beegfs/home/jaguir26/r157",
                                    "account": "128x24", "partition": "128x24", "qos": "normal"}),
                   mock.patch.object(rd, "qualification", side_effect=lambda path, name: {name + "_result": runtime if name == "runtime" else parity}),
                   mock.patch.object(ad.a, "validate_qualification", return_value={}),
                   mock.patch.object(rd, "run", return_value=json.dumps({"fixture": True})),
                   mock.patch.object(ad.handoff, "build_handoff_receipt", return_value={"status": "EE_CLOSED_RELEASED_PERMIT_HANDOFF_VERIFIED", "observed_epoch": self.now}),
                   mock.patch.object(rd, "observe", side_effect=lambda host, *args: muscat if host == policy.OWNER else jerez),
                   mock.patch.object(ad, "hb_snapshot", return_value=hb)]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        return plan_pin, config, hb

    def test_fresh_request_uses_dynamic_node_and_creates_no_claim(self):
        plan_pin, config, _ = self.refresh_fixture()
        out = self.root / "fresh-output"
        result = ad.refresh_request(plan_pin["path"], config, self.policy_pin, out)
        self.assertEqual(result["status"], "READY_FOR_PREPARE_ONLY_NOT_ADMITTED", result)
        request = r.read(result["request"]["path"])
        self.assertEqual(request["node"], "node-13")
        self.assertEqual(request["calendar_proposal"], config["calendar_evidence"]["FI"])
        self.assertEqual(request["execution_plan_sha256"], plan_pin["sha256"])
        self.assertFalse((self.central / "activation_registry.json").exists())
        self.assertEqual(result["claims_created"], 0)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL)[0], 0)

    def test_control_test_request_is_separate_from_FI_scientific_scope(self):
        plan_pin, config, _ = self.refresh_fixture()
        result = ad.refresh_request(plan_pin["path"], config, self.policy_pin, self.root / "test-output", purpose="CONTROL_TEST")
        self.assertEqual(result["status"], "READY_FOR_PREPARE_ONLY_NOT_ADMITTED", result)
        request = r.read(result["request"]["path"])
        self.assertEqual(request["study"], "TEST")
        self.assertEqual(request["resource_study"], "FI")
        self.assertEqual(request["scientific_exclusion_key"], "R157_CONTROL_TEST|" + "b" * 64)
        self.assertEqual(request["requested_wall_seconds"], 120)

    def test_stale_unclaimed_calendar_or_unknown_queue_emits_blocked_receipt(self):
        plan_pin, config, hb = self.refresh_fixture()
        hb["slurm"]["queue"] = "999|unknown|RUNNING|node-13\n"
        result = ad.refresh_request(plan_pin["path"], config, self.policy_pin, self.root / "unknown-output")
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("unknown_HB_job", result["reason"])
        hb["slurm"]["queue"] = ""
        old = policy.pinned(config["calendar_evidence"]["FI"])
        config["calendar_evidence"]["FI"] = self.write("stale-calendar.json", dict(old, created_epoch=self.now - 301))
        result = ad.refresh_request(plan_pin["path"], config, self.policy_pin, self.root / "stale-output")
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("fresh unclaimed", result["reason"])


if __name__ == "__main__":
    unittest.main()
