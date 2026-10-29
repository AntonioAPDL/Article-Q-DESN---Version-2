"""Source-only adversarial tests; no R, production payload, or process action."""
import copy
import datetime as dt
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

from . import repair_authority as a
from . import repair_readiness as r


def fixture(directory):
    old = dict(schema="r154_global_permits_v1", created_epoch=1., expires_epoch=10., lock_dir=str(a.LEGACY_LOCK.parent))
    policy = dict(schema=a.POLICY_SCHEMA, status=a.POLICY_STATUS, purpose=a.PURPOSE,
        study_id="r164-projection-toy-fixture01", created_epoch=20., expires_epoch=4000.,
        max_new_numerical=1, host="muscat", science_cpus=[30], physical_guard_cpus=[30, 62], max_workers=1,
        memory_GiB=8, SMT62_science_authorized=False, CPU31_SMT63_reserved=True,
        HB_profile_overlap_authorized=False,
        maximum_new_attempts=1, maximum_combined_CPU_seconds=300, maximum_wall_seconds=1800,
        old_pool_clock_inherited=False, old_costs_refunded=False, old_claims_reopened=False, old_contracts_mutated=False,
        allocation_relationship="DISTINCT_NEW_ALLOCATION_NO_OLD_FUNDS",
        prior_global_contract=dict(path="oldpool", sha256=a.OLD_POOL_SHA),
        prior_resource_policy=dict(path="oldpolicy", sha256=a.OLD_POLICY_SHA),
        prior_failed_grant=dict(path=str(a.OLD_TOY), sha256=a.OLD_TOY_SHA),
        prior_clock=dict(created_epoch=1., expires_epoch=10.),
        lock=dict(path=str(a.LEGACY_LOCK), device=10, inode=20),
        owner_admission_dir=str(Path(directory) / "owners"), claim_registry_dir=str(Path(directory) / "claims"),
        output_dir=str(Path(directory) / "output"), execution_source_bindings=[],
        root_authorization=dict(path="authorization", sha256="root"))
    auth = dict(schema="r164_distinct_study_root_authorization_v1", status="ROOT_REVIEWED_NEW_PROSPECTIVE_SYNTHETIC_STUDY",
        study_id=policy["study_id"], source_bindings=[], maximum_combined_CPU_seconds=300,
        old_costs_refunded=False, authorizes_production_fits=False)
    auth["policy_draft_sha256"] = a.identity(a.draft_policy(policy))
    records = dict(oldpool=old, oldpolicy=dict(expires_epoch=10.), authorization=auth)
    records[str(a.OLD_TOY)] = dict(paid_history_pins=[])
    pool = dict(schema=a.POOL_SCHEMA, purpose=a.PURPOSE, study_id=policy["study_id"], max_new_numerical=1,
        created_epoch=20., expires_epoch=4000., lock_dir=str(a.LEGACY_LOCK.parent), old_pool_renewed=False)
    grant = dict(schema=a.GRANT_SCHEMA, purpose=a.PURPOSE, status="ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY", created_epoch=20.,
        study_id=policy["study_id"], scope_id=policy["study_id"], authorizes_toy_optimizer=True,
        authorizes_production_fits=False, authorizes_production_acceptance=False,
        maximum_optimizer_invocations=8, maximum_total_optimizer_iterations=30, maximum_n=128, maximum_p=32,
        host="muscat", affinity=[30], cores=1, memory_GiB=8, permit_id="muscat_cpu30",
        maximum_new_attempts=1, attempt_index=1, old_costs_refunded=False, old_claims_reopened=False,
        old_pool_clock_inherited=False, maximum_CPU_seconds=280., maximum_combined_CPU_seconds=300.,
        maximum_wall_seconds=1800., stage_deadline_epoch=3900., expires_UTC=dt.datetime.fromtimestamp(3800, dt.timezone.utc).isoformat(),
        source=dict(kind=a.SOURCE_KIND, branch="work/pricefm-r157-native-bootstrap-20261028", head=r.NATIVE_HEAD),
        output_dir=policy["output_dir"], source_bindings=[],
        paid_history_pins=[dict(path=str(p), sha256="cost") for p in a.OLD_COSTS])
    for p in a.OLD_COSTS: records[str(p)] = dict(status="PAID_HISTORY_RETAINED")
    reader = lambda pin: records[pin["path"]]
    return grant, pool, policy, records, reader


class ProspectiveAuthorityWitnesses(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.grant, self.pool, self.policy, self.records, self.reader = fixture(self.tmp.name)

    def tearDown(self): self.tmp.cleanup()

    def validate(self):
        return a.validate_grant(self.grant, self.pool, self.policy, now=21., metadata_reader=self.reader)

    def test_distinct_valid_study_can_follow_unchanged_expired_pool(self):
        self.assertEqual(self.validate()["schema"], a.GRANT_SCHEMA)
        self.assertEqual(self.records["oldpool"]["expires_epoch"], 10.)
        self.assertEqual(self.policy["prior_clock"]["expires_epoch"], 10.)

    def test_fake_new_expiry_of_old_pool_and_old_schema_rejected(self):
        for change in ("hash", "oldschema", "oldclock", "inherit"):
            with self.subTest(change=change):
                grant, pool, policy, records, reader = fixture(self.tmp.name)
                if change == "hash": policy["prior_global_contract"]["sha256"] = "edited-old-expiry"
                if change == "oldschema": pool["schema"] = "r154_global_permits_v1"
                if change == "oldclock": policy["prior_clock"]["expires_epoch"] = 3999.
                if change == "inherit": grant["old_pool_clock_inherited"] = True
                with self.assertRaises(r.EvidenceError):
                    a.validate_grant(grant, pool, policy, now=21., metadata_reader=reader)

    def test_relabelled_old_grant_and_broader_production_authority_rejected(self):
        for key, value in (("schema", "r157_projection_toy_grant_v1"), ("authorizes_production_fits", True),
                           ("authorizes_production_acceptance", True), ("attempt_index", 2), ("maximum_new_attempts", 2)):
            with self.subTest(key=key):
                grant = copy.deepcopy(self.grant); grant[key] = value
                with self.assertRaises(r.EvidenceError): a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)

    def test_same_cpu_sibling_headroom_and_one_worker_enforced(self):
        for key, value in (("science_cpus", [30, 62]), ("physical_guard_cpus", [30]), ("max_workers", 2),
                           ("SMT62_science_authorized", True), ("CPU31_SMT63_reserved", False), ("memory_GiB", 16)):
            with self.subTest(key=key):
                policy = copy.deepcopy(self.policy); policy[key] = value
                with self.assertRaises(r.EvidenceError): a.validate_policy(policy, now=21., metadata_reader=self.reader)

    def test_shape_calls_budget_and_finalizer_reserve_enforced(self):
        for key, value in (("maximum_optimizer_invocations", 9), ("maximum_total_optimizer_iterations", 31),
                           ("maximum_n", 129), ("maximum_p", 33), ("maximum_combined_CPU_seconds", 301),
                           ("maximum_CPU_seconds", 295), ("maximum_wall_seconds", 1801), ("cores", True),
                           ("maximum_CPU_seconds", float("inf"))):
            with self.subTest(key=key):
                grant = copy.deepcopy(self.grant); grant[key] = value
                with self.assertRaises(r.EvidenceError): a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)

    def test_expired_not_issued_and_insufficient_calendar_rejected(self):
        for now in (19., 4000.):
            with self.assertRaises(r.EvidenceError): a.validate_grant(self.grant, self.pool, self.policy, now=now, metadata_reader=self.reader)
        grant = copy.deepcopy(self.grant); grant["expires_UTC"] = dt.datetime.fromtimestamp(100, dt.timezone.utc).isoformat()
        with self.assertRaises(r.EvidenceError): a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)

    def test_paid_failed_history_cannot_disappear_or_refund(self):
        grant = copy.deepcopy(self.grant); grant["paid_history_pins"] = grant["paid_history_pins"][:2]
        with self.assertRaisesRegex(r.EvidenceError, "paid history"): a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)
        grant = copy.deepcopy(self.grant); grant["old_costs_refunded"] = True
        with self.assertRaises(r.EvidenceError): a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)

    def test_root_review_hash_binds_whole_new_policy(self):
        policy = copy.deepcopy(self.policy); policy["output_dir"] += "_changed"
        with self.assertRaisesRegex(r.EvidenceError, "root source review"): a.validate_policy(policy, now=21., metadata_reader=self.reader)
        self.records["authorization"]["policy_draft_sha256"] = "self-approved"
        with self.assertRaises(r.EvidenceError): self.validate()

    def owner(self):
        grant_pin, pool_pin, policy_pin = ({"path": x, "sha256": x} for x in ("grant", "pool", "policy"))
        value = dict(schema="r164_distinct_study_owner_admission_v1", status="ROOT_ADMITTED_EXACT_NEW_STUDY_OWNER",
            study_id=self.policy["study_id"], scope_id=self.grant["scope_id"], stage_grant=grant_pin,
            global_contract=pool_pin, resource_policy=policy_pin, lock=self.policy["lock"], science_cpus=[30],
            physical_guard_cpus=[30, 62], max_workers=1, old_clock_renewed=False, authorizes_production_fits=False,
            started_epoch=20., expires_epoch=3800.)
        return value, grant_pin, pool_pin, policy_pin

    def test_acyclic_owner_binds_actual_grant_and_new_policy(self):
        owner, g, p, policy = self.owner()
        a.validate_owner_admission(owner, self.grant, g, p, self.policy, policy, now=21.)
        owner["stage_grant"] = dict(path="wrong", sha256="wrong")
        with self.assertRaisesRegex(r.EvidenceError, "actual grant"): a.validate_owner_admission(owner, self.grant, g, p, self.policy, policy, now=21.)
        owner, g, p, policy = self.owner(); self.grant["owner_admission_pin"] = {"circular": True}
        with self.assertRaisesRegex(r.EvidenceError, "circular"): a.validate_owner_admission(owner, self.grant, g, p, self.policy, policy, now=21.)

    def test_old_owner_protocol_cannot_be_reused(self):
        owner, g, p, policy = self.owner(); self.grant["owner_handoff"] = {"old": "expired"}
        with self.assertRaises(r.EvidenceError): a.validate_owner_admission(owner, self.grant, g, p, self.policy, policy, now=21.)

    def test_new_grant_and_owner_cannot_predate_prospective_policy(self):
        grant = dict(self.grant, created_epoch=19.)
        with self.assertRaisesRegex(r.EvidenceError, "prospectively issued"):
            a.validate_grant(grant, self.pool, self.policy, now=21., metadata_reader=self.reader)
        owner, g, p, policy = self.owner(); owner["started_epoch"] = 19.
        with self.assertRaisesRegex(r.EvidenceError, "clock differs"):
            a.validate_owner_admission(owner, self.grant, g, p, self.policy, policy, now=21.)

    def test_original_lock_device_inode_proof_required(self):
        original = dict(device=10, inode=20)
        native = types.SimpleNamespace(legacy=types.SimpleNamespace(verify_held_flock=lambda fd: dict(device=10, inode=20, fd=fd)))
        self.assertEqual(a.held_lock(17, original, native)["fd"], 17)
        with self.assertRaises(r.EvidenceError): a.held_lock(17, dict(device=10, inode=21), native)

    def test_claim_file_create_only_blocks_second_attempt(self):
        path = Path(self.tmp.name) / "one_claim.json"
        a.atomic_json(path, {"attempt": 1})
        with self.assertRaises(FileExistsError): a.atomic_json(path, {"attempt": 2})
        self.assertEqual(a.read(a.pin(path)), {"attempt": 1})

    def test_fresh_original_priority_success_required(self):
        records = dict(proof=dict(status="EE_LV_SUCCESS_AND_PHYSICAL_DRAIN_VERIFIED", observed_epoch=20.,
            EE_exit={"path": "EE"}, LV_exit={"path": "LV"}, no_live_owned_numerical_lifetimes=True,
            no_pending_refill=True, shared_permit_physically_free=True),
            EE=dict(status="COMPLETE_INITIAL_PREFIX"), LV=dict(status="COMPLETE_DIAGNOSTIC"))
        reader = lambda pin: records[pin["path"]]
        a.priority_ready({"path": "proof"}, now=21., metadata_reader=reader)
        with self.assertRaisesRegex(r.EvidenceError, "fresh"): a.priority_ready({"path": "proof"}, now=81., metadata_reader=reader)
        records["LV"]["status"] = "FAILED"
        with self.assertRaisesRegex(r.EvidenceError, "exit failed"): a.priority_ready({"path": "proof"}, now=21., metadata_reader=reader)

    def test_new_metadata_capture_plan_does_not_extend_old_pool(self):
        records = dict(self.records)
        records["newpolicy.json"] = self.policy
        records["newscope.json"] = dict(maximum_CPU_seconds=20, maximum_wall_seconds=60, admin_cpu=31,
            new_numerical_calls=0, issued_epoch=20., expires_epoch=300.)
        plan = dict(schema="r164_priority_drain_observation_plan_v1", status="ROOT_ADMITTED_METADATA_PRIORITY_DRAIN_CAPTURE_ONLY",
            maximum_combined_CPU_seconds=20, maximum_wall_seconds=60, affinity=[31], actual_target_inputs=False,
            optimizer_invocations=0, old_scope_renewed=False, resource_policy={"path": "newpolicy.json"},
            study_id=self.policy["study_id"], original_lock_identity=self.policy["lock"],
            old_global_contract=self.policy["prior_global_contract"], administrative_scope={"path": "newscope.json"},
            expires_UTC=dt.datetime.fromtimestamp(200, dt.timezone.utc).isoformat())
        reader = lambda pin: records[pin["path"]]
        self.assertEqual(a.validate_priority_plan(plan, now=21., metadata_reader=reader), self.policy)
        self.assertEqual(records["oldpool"]["expires_epoch"], 10.)
        plan["schema"] = "r157_priority_drain_observation_plan_v1"
        with self.assertRaises(r.EvidenceError): a.validate_priority_plan(plan, now=21., metadata_reader=reader)

    def test_json_reader_denies_payload_before_open(self):
        with patch.object(a, "verify", side_effect=AssertionError("payload was opened")):
            with self.assertRaisesRegex(r.EvidenceError, "JSON"):
                a.read(dict(path=str(Path(self.tmp.name) / "model.rds"), sha256="payload"))

    def test_standalone_finalizer_retains_original_grant_checks(self):
        core_pin, grant_pin, guard_pin = (dict(path=name + ".json", sha256=name) for name in ("core", "grant", "guard"))
        runtime = dict(path="runtime.json", sha256="runtime")
        grant = dict(self.grant, actual_R_runtime_binding=runtime)
        values = {"core.json": {}, "grant.json": grant, "guard.json": {}, "runtime.json": {}}
        for key, bad in (("status", "DRAFT"), ("authorizes_toy_optimizer", False), ("maximum_optimizer_invocations", 7)):
            with self.subTest(key=key):
                values["grant.json"] = dict(grant, **{key: bad})
                with patch.object(a, "read", lambda value: values[value["path"]]), self.assertRaisesRegex(r.EvidenceError, "synthetic new-protocol"):
                    a.finalize(core_pin, grant_pin, guard_pin, None, Path(self.tmp.name) / "never.json")

    def test_atomic_claim_failure_does_not_replace_original(self):
        path = Path(self.tmp.name) / "claim.json"
        first = a.atomic_json(path, dict(attempt=1))
        with self.assertRaises(FileExistsError): a.atomic_json(path, dict(attempt=2))
        self.assertEqual(a.read(first), dict(attempt=1))
        self.assertFalse(list(Path(self.tmp.name).glob(".*pending*")))


if __name__ == "__main__":
    unittest.main()
