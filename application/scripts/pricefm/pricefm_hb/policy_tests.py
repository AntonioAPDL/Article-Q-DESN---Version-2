"""Finite metadata-only tests for explicit cross-host policy conservation."""
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock
from . import policy as p, registry as r


class PolicyFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.now = time.time()
        self.owner_patch = mock.patch.object(p, "owner")
        self.owner_patch.start()
        self.addCleanup(self.owner_patch.stop)
        self.lock = self.root / "muscat_cpu30.lock"
        self.lock.touch()
        self.source = self.root / "guard_entry.py"
        self.source.write_text("# pinned metadata fixture, never executed\n")
        self.source_pin = p.pin(self.source)
        self.history = self.write("historical.json", {"fixture": True})
        resource = {"schema": "r154_resource_policy_v1", "max_new_numerical_workers": 1,
                    "nonrenewing": True, "physical_CPU_allocation": {"cpu": 30, "SMT62_additional_worker": False},
                    "created_epoch": self.now - 100, "expires_epoch": self.now + 3600,
                    "Jerez_new_predictive_or_repair_worker_admitted": False}
        self.resource_pin = self.write("legacy_resource.json", resource)
        contract = {"schema": "r154_global_permits_v1", "max_new_numerical": 1,
                    "new_numerical_concurrency_above_one_authorized": False, "nonrenewing": True,
                    "jerez_numerical_allocation": None, "SMT62_science_authorized": False,
                    "all_original_allocation_clocks_ceilings_and_lock_identity_preserved": True,
                    "evidence": {"resource_policy": self.resource_pin},
                    "created_epoch": self.now - 100, "expires_epoch": self.now + 3600,
                    "permits": [{"cpu": 30, "host": "muscat", "id": "muscat_cpu30",
                                 "science": ["EE", "LV", "CERTIFICATE_REFERENCE"], "sequential": True}],
                    "lock_dir": str(self.root)}
        self.contract_pin = self.write("legacy_global.json", contract)
        self.owners = self.root / "owners"
        self.owners.mkdir()
        self.draft = p.build_policy(self.contract_pin, self.resource_pin,
                                   [self.source_pin], [self.source_pin], scope_id="fixture-policy-01",
                                   expires_epoch=self.now + 7200, owner_admission_dir=self.owners,
                                   historical_EE_release=self.history, now=self.now)
        self.packet = self.admit(self.draft)
        self.policy_pin = self.write("policy.json", self.packet)

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        r.write(path, value)
        return p.pin(path)

    def admit(self, draft):
        authorization = {"status": "ROOT_REVIEWED_CROSS_HOST_IMPLEMENTATION_AUTHORIZATION",
                         "controller": p.OWNER, "policy_draft_sha256": r.identity(draft),
                         "user_requested_implementation": True,
                         "old_local_clock_and_charges_preserved": True}
        auth = self.write("adoption-" + r.identity(draft) + ".json", authorization)
        return p.admit_policy(draft, auth, now=self.now)

    def owner_admission(self):
        grant = {"status": "ROOT_ADMITTED_R157_PERMIT_HANDOFF_TEST", "host": "muscat",
                 "affinity": [30], "cores": 1, "permit_id": "muscat_cpu30",
                 "global_contract": self.contract_pin, "source_bindings": [self.source_pin],
                 "expires_epoch": self.now + 600}
        gp = self.write("standin_grant.json", grant)
        value = p.build_owner_admission(self.policy_pin, gp, self.source_pin,
                                        scope_id="fixture-owner-01", started_epoch=self.now,
                                        expires_epoch=self.now + 600, now=self.now)
        return value, self.write("owners/fixture-owner-01.json", value)


class PolicyTests(PolicyFixture):
    def test_original_toy_status_requires_exact_synthetic_bounds_and_no_production_authority(self):
        grant = {"status": "ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY", "schema": "r157_projection_toy_grant_v1",
                 "host": "muscat", "affinity": [30], "cores": 1, "permit_id": "muscat_cpu30",
                 "global_contract": self.contract_pin, "source_bindings": [self.source_pin],
                 "expires_epoch": self.now + 600, "authorizes_toy_optimizer": True,
                 "authorizes_production_fits": False, "authorizes_production_acceptance": False,
                 "maximum_optimizer_invocations": 8, "maximum_total_optimizer_iterations": 30,
                 "maximum_n": 128, "maximum_p": 32, "memory_GiB": 8,
                 "maximum_new_attempts": 1, "attempt_index": 1, "old_costs_refunded": False,
                 "maximum_CPU_seconds": 280, "maximum_combined_CPU_seconds": 300,
                 "maximum_wall_seconds": 600}
        def admission(value):
            gp = self.write("toy-grant.json", value)
            return p.build_owner_admission(self.policy_pin, gp, self.source_pin, scope_id="fixture-toy-owner",
                started_epoch=self.now, expires_epoch=self.now + 600, now=self.now)
        self.assertEqual(admission(grant)["owner_source"], self.source_pin)
        for change in ({"maximum_optimizer_invocations": 9}, {"maximum_n": 129}, {"maximum_p": 33},
                       {"authorizes_production_acceptance": True}, {"maximum_combined_CPU_seconds": 301},
                       {"maximum_new_attempts": 2}, {"old_costs_refunded": True}, {"maximum_p": True}):
            with self.subTest(change=change), self.assertRaises(p.PolicyError): admission(dict(grant, **change))

    def test_draft_is_not_an_execution_authority(self):
        p.validate_policy(self.draft, now=self.now, require_admitted=False)
        with self.assertRaises(p.PolicyError):
            p.validate_policy(self.draft, now=self.now)

    def test_admitted_matrix_adds_HB_without_rewriting_old_one(self):
        old_bytes = Path(self.contract_pin["path"]).read_bytes()
        accepted = p.validate_policy(self.packet, now=self.now)
        self.assertEqual(accepted["HB_max_workers"], 1)
        self.assertEqual(accepted["max_additional_numerical_workers"], 2)
        self.assertEqual(Path(self.contract_pin["path"]).read_bytes(), old_bytes)
        self.assertEqual(r.read(self.contract_pin["path"])["max_new_numerical"], 1)

    def test_adoption_requires_exact_reviewed_draft(self):
        altered = dict(self.draft, scope_id="different-draft-01")
        with self.assertRaises(p.PolicyError):
            p.admit_policy(altered, self.packet["authorization"], now=self.now)

    def test_manual_status_flip_does_not_admit_unreviewed_bytes(self):
        changed = dict(self.packet, scope_id="forged-policy-02")
        with self.assertRaises(p.PolicyError):
            p.validate_policy(changed, now=self.now)

    def test_both_scope_expiry_and_absolute_duration_are_bounded(self):
        for change in ({"expires_epoch": self.now}, {"created_epoch": self.now + 1},
                       {"expires_epoch": self.now + 86401}, {"expires_epoch": float("inf")}):
            with self.subTest(change=change), self.assertRaises(p.PolicyError):
                p.validate_policy(dict(self.packet, **change), now=self.now)

    def test_local_expiry_cannot_be_extended_even_by_a_new_HB_matrix(self):
        changed = copy.deepcopy(self.packet)
        changed["local_permit"]["expires_epoch"] += 1
        changed["legacy_expires_epoch"] += 1
        with self.assertRaises(p.PolicyError):
            p.validate_policy(changed, now=self.now)

    def test_SMT_or_Jerez_or_baseline_expansion_is_rejected(self):
        variants = []
        for key, value in (("Jerez_extra_workers", 1), ("HB_total_CPU_ceiling", 92),
                           ("baseline_allocations_changed", True), ("old_scope_renewed", True),
                           ("numerical_grant_created", True)):
            variants.append(dict(self.packet, **{key: value}))
        changed = copy.deepcopy(self.packet)
        changed["local_permit"]["science_cpus"] = [30, 62]
        variants.append(changed)
        for value in variants:
            with self.assertRaises(p.PolicyError):
                p.validate_policy(value, now=self.now)

    def test_changed_old_contract_and_lock_inode_are_not_normalized(self):
        before = r.read(self.contract_pin["path"])
        r.write(self.contract_pin["path"], dict(before, max_new_numerical=2))
        with self.assertRaises(p.PolicyError):
            p.validate_policy(self.packet, now=self.now)
        r.write(self.contract_pin["path"], before)
        self.lock.rename(self.root / "retained-original.lock")
        self.lock.write_text("replacement inode")
        with self.assertRaises(p.PolicyError):
            p.validate_policy(self.packet, now=self.now)

    def test_source_change_and_duplicate_source_paths_block(self):
        self.source.write_text("changed source")
        with self.assertRaises(p.PolicyError):
            p.validate_policy(self.packet, now=self.now)
        with self.assertRaises(p.PolicyError):
            p.source_pins([self.source_pin, self.source_pin], check_files=False)

    def test_remote_validation_never_reads_foreign_paths(self):
        with mock.patch.object(p, "legacy_view", side_effect=AssertionError("foreign read")), \
                mock.patch.object(r, "digest", side_effect=AssertionError("foreign read")):
            p.validate_policy(self.packet, now=self.now, check_files=False)

    def test_unmeasured_worker_count_and_scale_skip_are_rejected(self):
        changed = copy.deepcopy(self.packet)
        changed["HB_max_workers"] = 8
        changed["max_additional_numerical_workers"] = 9
        with self.assertRaises(p.PolicyError):
            p.validate_policy(changed, now=self.now)
        changed["scale_amendments"] = [{"from": 1, "to": 8, "local_assignment_changed": False,
                                         "evidence": self.history}]
        with self.assertRaises(p.PolicyError):
            p.validate_policy(changed, now=self.now)

    def test_measured_scale_is_new_packet_with_original_local_bounds(self):
        evidence = self.write("scale12.json", {"status": "ROOT_ACCEPTED_MEASURED_HB_SCALE_STAGE",
                            "from": 1, "to": 2, "exact_outputs_validated": True,
                            "all_regional_caps_preserved": True, "no_new_candidate_selection": True})
        old_bytes = Path(self.policy_pin["path"]).read_bytes()
        draft = p.build_scale_amendment(self.policy_pin, evidence, scope_id=self.packet["scope_id"],
                                        expires_epoch=self.packet["expires_epoch"], now=self.now)
        adopted = self.admit(draft)
        self.assertEqual(p.hb_concurrency(adopted, now=self.now), 2)
        self.assertEqual(adopted["local_permit"], self.packet["local_permit"])
        self.assertEqual(adopted["previous_policy"], self.policy_pin)
        self.assertEqual(adopted["created_epoch"], self.packet["created_epoch"])
        self.assertEqual(adopted["expires_epoch"], self.packet["expires_epoch"])
        self.assertEqual(Path(self.policy_pin["path"]).read_bytes(), old_bytes)

    def test_owner_admission_binds_root_policy_source_and_current_stage(self):
        value, _ = self.owner_admission()
        p.validate_owner_admission(value, self.packet, self.policy_pin, now=self.now)
        for key, val in (("cross_host_policy", self.history), ("science_cpus", [31]),
                         ("owner_source", self.history), ("expires_epoch", self.now + 3601),
                         ("scope_id", "../../outside")):
            with self.subTest(key=key), self.assertRaises(p.PolicyError):
                p.validate_owner_admission(dict(value, **{key: val}), self.packet, self.policy_pin, now=self.now)

    def test_owner_envelope_cannot_outlive_its_numerical_stage(self):
        value, _ = self.owner_admission()
        value["expires_epoch"] += 1
        with self.assertRaises(p.PolicyError):
            p.validate_owner_admission(value, self.packet, self.policy_pin, now=self.now)

    def test_owner_envelope_cannot_admit_a_draft_stage(self):
        value, _ = self.owner_admission()
        grant = r.read(value["stage_grant"]["path"])
        value["stage_grant"] = self.write("draft_stage.json", dict(grant, status="PROPOSED_NOT_ADMITTED"))
        with self.assertRaises(p.PolicyError):
            p.validate_owner_admission(value, self.packet, self.policy_pin, now=self.now)

    def test_symlink_or_relative_evidence_paths_are_rejected(self):
        link = self.root / "linked.json"
        link.symlink_to(self.history["path"])
        for pin in ({"path": str(link), "sha256": self.history["sha256"]},
                    {"path": "relative.json", "sha256": "a" * 64}):
            with self.assertRaises((p.PolicyError, ValueError)):
                p.pinned(pin)

    def test_foreign_controller_cannot_build_policy(self):
        self.owner_patch.stop()
        with mock.patch.object(p.socket, "getfqdn", return_value="jerez.be.ucsc.edu"), self.assertRaises(p.PolicyError):
            p.owner()


if __name__ == "__main__":
    unittest.main()
