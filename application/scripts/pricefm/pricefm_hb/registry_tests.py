#!/usr/bin/env python3
"""Offline qualification-authority and exactly-once registry failure tests.

Only temporary metadata is written. No SSH, Slurm, scientific imports or arrays.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import copy
import datetime as dt
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pricefm_hb import registry as reg

NOW = 2_000_000_000.0
HOST = "muscat.be.ucsc.edu"
RELEASE = "a" * 64


def authority(scope="qualification-1", **overrides):
    value = {
        "schema": reg.SCHEMA,
        "purpose": "QUALIFICATION_ONLY",
        "controller": HOST,
        "scientific_screening_authorized": False,
        "official_origins": 0,
        "fits": 0,
        "scope_id": scope,
        "max_attempts": 3,
        "max_concurrent": 1,
        "max_reserved_CPU_seconds": 180,
        "expires_utc": dt.datetime.fromtimestamp(NOW + 3600, dt.timezone.utc).isoformat(),
        "jobs": {
            "environment": {"cpus": 1, "wall_seconds": 60, "memory_MiB": 2048,
                            "release_sha256": RELEASE,
                            "task_sha256": reg.identity(task())},
            "parity": {"cpus": 1, "wall_seconds": 60, "memory_MiB": 2048,
                       "release_sha256": RELEASE,
                       "task_sha256": reg.identity(task("parity-1", "parity"))},
        },
    }
    value.update(overrides)
    return value


def task(label="environment-1", kind="environment", namespace="TEST"):
    return {"kind": kind, "namespace": namespace, "label": label,
            "scientific_identity": "frozen-fixture", "execution_host": "hb.ucsc.edu"}


class AuthorityTests(unittest.TestCase):
    def validate(self, value):
        return reg.validate_authority(value, now=NOW, hostname=HOST)

    def test_only_qualification_authority_is_accepted(self):
        self.assertEqual(self.validate(authority())["purpose"], "QUALIFICATION_ONLY")
        for changed in ({"schema": "production"}, {"purpose": "FI_SCREENING"},
                        {"scientific_screening_authorized": True},
                        {"official_origins": 1}, {"fits": 1}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.validate(authority(**changed))

    def test_wrong_controller_host_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "canonical controller"):
            self.validate(authority(controller="hb.ucsc.edu"))

    def test_expiry_is_checked_at_boundary(self):
        expired = dt.datetime.fromtimestamp(NOW, dt.timezone.utc).isoformat()
        with self.assertRaisesRegex(ValueError, "expired"):
            self.validate(authority(expires_utc=expired))

    def test_expiry_requires_an_explicit_timezone(self):
        with self.assertRaises(ValueError):
            self.validate(authority(expires_utc="2040-01-01T00:00:00"))

    def test_nonfinite_zero_and_excess_cpu_scopes_reject(self):
        for amount in (0, -1, float("inf"), float("nan"), 3601, True):
            with self.subTest(amount=amount), self.assertRaises(ValueError):
                self.validate(authority(max_reserved_CPU_seconds=amount))

    def test_attempt_and_concurrency_limits_reject(self):
        for changed in ({"max_attempts": 0}, {"max_attempts": 4},
                        {"max_attempts": True}, {"max_concurrent": 2},
                        {"max_concurrent": True}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.validate(authority(**changed))

    def test_production_fi_job_class_cannot_be_added(self):
        value = authority()
        value["jobs"]["FI_SCREENING"] = value["jobs"]["environment"].copy()
        with self.assertRaisesRegex(ValueError, "job/resources"):
            self.validate(value)

    def test_admitted_release_and_task_pins_are_required(self):
        for field in ("release_sha256", "task_sha256"):
            for invalid in (None, "", "not-a-digest", "A" * 64):
                value = authority()
                value["jobs"]["environment"][field] = invalid
                with self.subTest(field=field, invalid=invalid), self.assertRaises(ValueError):
                    self.validate(value)

    def test_single_cpu_finite_wall_and_memory_are_required(self):
        for changed in ({"cpus": 2}, {"cpus": True}, {"wall_seconds": 0},
                        {"wall_seconds": 1801}, {"wall_seconds": True},
                        {"memory_MiB": 1023}, {"memory_MiB": 8193},
                        {"memory_MiB": 2048.0}):
            value = authority()
            value["jobs"]["environment"].update(changed)
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.validate(value)


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.registry = reg.Registry(self.root / "registry")
        self.addCleanup(mock.patch.stopall)
        self.clock = mock.patch.object(reg.time, "time", return_value=NOW).start()
        mock.patch.object(reg.socket, "getfqdn", return_value=HOST).start()
        self.grant = authority()

    def reserve(self, value=None, grant=None, release=RELEASE):
        return self.registry.reserve(grant or self.grant, value or task(), release)

    def submit(self, claim):
        key = claim["task_key"]
        for current, target in (("RESERVED", "STAGED"), ("STAGED", "SUBMISSION_INTENT"),
                                ("SUBMISSION_INTENT", "SUBMITTED")):
            self.registry.transition(key, current, target)
        return key

    def finish(self, claim, final="COLLECTED"):
        key = self.submit(claim)
        self.registry.transition(key, "SUBMITTED", final)
        return key

    def admitted_job(self, label, kind, wall):
        value = task(label, kind)
        grant = authority(label + "-scope", max_attempts=1, max_reserved_CPU_seconds=wall)
        grant["jobs"] = {kind: {"cpus": 1, "wall_seconds": wall, "memory_MiB": 2048,
                                "release_sha256": RELEASE, "task_sha256": reg.identity(value)}}
        return value, grant

    def recovery_document(self, leave_second_unresolved=False):
        for number in range(2):
            value, grant = self.admitted_job("failed-env-" + str(number), "environment", 1200)
            claim = self.reserve(value, grant)
            if number == 1 and leave_second_unresolved:
                self.submit(claim)
            else:
                self.finish(claim, "FAILED_RECONCILED")
        failure = self.root / "channel-failure.json"
        reg.write(failure, {"schema": "offline-synthetic-channel-failure", "terms_accepted": False,
                            "reason": "default channel unavailable; no bypass or acceptance"})
        state = self.registry.snapshot()
        return {"schema": "r156-budget-amendment-v1", "controller": HOST,
                "from": {"max_attempts": 3, "max_reserved_CPU_seconds": 3300},
                "to": {"max_attempts": 4, "max_reserved_CPU_seconds": 4500},
                "reason_code": "DEFAULT_CHANNEL_UNACCEPTED_USE_CONDA_FORGE",
                "failure_evidence": {"path": str(failure), "sha256": reg.digest(failure)},
                "carried_scope_ids": sorted(state["scopes"]),
                "carried_scopes_sha256": reg.identity(state["scopes"])}

    def reference_profile_document(self, leave_parity_unresolved=False):
        self.registry.amend_channel_recovery_budget(self.recovery_document())
        value, grant = self.admitted_job("env03", "environment", 1200)
        self.finish(self.reserve(value, grant))
        value, grant = self.admitted_job("strict-native-parity", "parity", 900)
        claim = self.reserve(value, grant)
        if leave_parity_unresolved:
            self.submit(claim)
        else:
            self.finish(claim, "FAILED_RECONCILED")
        failure = self.root / "strict-native-parity-failure.json"
        reference = self.root / "historical-reference-profile.json"
        reg.write(failure, {"schema": "offline-synthetic-strict-parity-failure", "comparison_changed": False,
                            "fixture": "fixed8461fixture-v1", "accepted": False})
        reg.write(reference, {"schema": "offline-synthetic-reference-profile", "profile": "Sandybridge_AVX_v1",
                              "AVX": True, "AVX2": False, "FMA": False, "matching_binaries": 7})
        state = self.registry.snapshot()
        return {"schema": "r156-budget-amendment-v1", "controller": HOST,
                "from": {"max_attempts": 4, "max_reserved_CPU_seconds": 4500},
                "to": {"max_attempts": 5, "max_reserved_CPU_seconds": 5400},
                "reason_code": "REFERENCE_CPU_PROFILE_SANDYBRIDGE", "numerical_profile": "Sandybridge_AVX_v1",
                "failure_evidence": {"path": str(failure), "sha256": reg.digest(failure)},
                "reference_profile_evidence": {"path": str(reference), "sha256": reg.digest(reference)},
                "carried_scope_ids": sorted(state["scopes"]),
                "carried_scopes_sha256": reg.identity(state["scopes"])}

    def test_reservation_is_durable_and_caller_mutation_does_not_change_it(self):
        value = task()
        claim = self.reserve(value)
        value["label"] = "changed"
        claim["task"]["namespace"] = "PRODUCTION"
        stored = self.registry.snapshot()["claims"][claim["task_key"]]
        self.assertEqual(stored["task"]["label"], "environment-1")
        self.assertEqual(stored["task"]["namespace"], "TEST")
        self.assertEqual(stored["release_sha256"], RELEASE)
        self.assertEqual(stored["reserved_CPU_seconds"], 60)

    def test_production_namespace_and_fi_kind_reject_before_claim(self):
        for value in (task(namespace="tasks_done"), task(namespace="PRODUCTION"),
                      task(kind="FI"), task(kind="screening")):
            with self.subTest(task=value), self.assertRaises(ValueError):
                self.reserve(value)
        self.assertEqual(self.registry.snapshot()["claims"], {})

    def test_invalid_authority_does_not_consume_a_claim(self):
        with self.assertRaises(ValueError):
            self.reserve(grant=authority(fits=1))
        self.assertEqual(self.registry.snapshot()["claims"], {})

    def test_same_task_is_spent_after_success_even_with_another_release_or_scope(self):
        claim = self.reserve()
        self.finish(claim)
        changed = authority("scope-2")
        changed["jobs"]["environment"]["release_sha256"] = "b" * 64
        for grant, release in ((self.grant, RELEASE), (changed, "b" * 64)):
            with self.subTest(scope=grant["scope_id"]), self.assertRaisesRegex(ValueError, "claimed/spent"):
                self.reserve(grant=grant, release=release)

    def test_failed_task_stays_spent_and_no_budget_is_refunded(self):
        claim = self.reserve()
        self.finish(claim, "FAILED_RECONCILED")
        state = self.registry.snapshot()
        self.assertEqual(state["scopes"][self.grant["scope_id"]]["attempts"], 1)
        self.assertEqual(state["scopes"][self.grant["scope_id"]]["reserved_CPU_seconds"], 60)
        with self.assertRaisesRegex(ValueError, "claimed/spent"):
            self.reserve()

    def test_unresolved_claim_blocks_a_different_scope(self):
        self.reserve()
        with self.assertRaisesRegex(ValueError, "unresolved"):
            self.reserve(task("parity-1", "parity"), authority("scope-2"))
        self.assertNotIn("scope-2", self.registry.snapshot()["scopes"])

    def test_ambiguous_claim_never_opens_an_automatic_retry(self):
        claim = self.reserve()
        self.registry.transition(claim["task_key"], "RESERVED", "AMBIGUOUS", reason="upload interrupted")
        with self.assertRaisesRegex(ValueError, "unresolved"):
            self.reserve(task("parity-1", "parity"), authority("scope-2"))
        with self.assertRaisesRegex(ValueError, "unreviewed"):
            self.registry.transition(claim["task_key"], "AMBIGUOUS", "RESERVED")

    def test_same_scope_authority_cannot_be_amended_in_place(self):
        self.finish(self.reserve())
        changed = authority(max_reserved_CPU_seconds=181)
        with self.assertRaisesRegex(ValueError, "authority changed"):
            self.reserve(task("parity-1", "parity"), changed)

    def test_reservations_increase_monotonically_across_success_and_failure(self):
        totals = []
        grant = authority(max_attempts=2)
        for value, final in ((task(), "COLLECTED"), (task("parity-1", "parity"), "FAILED_RECONCILED")):
            self.finish(self.reserve(value, grant), final)
            scope = self.registry.snapshot()["scopes"][self.grant["scope_id"]]
            totals.append((scope["attempts"], scope["reserved_CPU_seconds"]))
        self.assertEqual(totals, [(1, 60), (2, 120)])

    def test_attempt_ceiling_keeps_reserved_cpu_and_prevents_another_admitted_class(self):
        grant = authority(max_attempts=1)
        self.finish(self.reserve(grant=grant))
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "budget exhausted"):
            self.reserve(task("parity-1", "parity"), grant)
        self.assertEqual(self.registry.snapshot(), before)

    def test_cpu_reservation_exhaustion_rejects_without_increment(self):
        grant = authority(max_reserved_CPU_seconds=100)
        self.finish(self.reserve(grant=grant))
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "budget exhausted"):
            self.reserve(task("parity-1", "parity"), grant)
        self.assertEqual(self.registry.snapshot(), before)

    def test_new_scope_keeps_prior_spent_evidence(self):
        first = self.reserve()
        self.finish(first)
        second = self.reserve(task("parity-1", "parity"), authority("scope-2"))
        state = self.registry.snapshot()
        self.assertEqual(len(state["scopes"]), 2)
        self.assertEqual(state["claims"][first["task_key"]]["state"], "COLLECTED")
        self.assertEqual(state["claims"][second["task_key"]]["state"], "RESERVED")

    def test_release_and_task_pins_cannot_be_changed_before_claim(self):
        for value, release in ((task(), "b" * 64), (task("unadmitted-fixture"), RELEASE)):
            with self.subTest(task=value, release=release), self.assertRaisesRegex(ValueError, "immutable pins"):
                self.reserve(value, release=release)
        self.assertEqual(self.registry.snapshot()["claims"], {})

    def test_whole_job_and_cleanup_must_fit_remaining_calendar(self):
        self.clock.return_value = NOW + 3600 - 119
        with self.assertRaisesRegex(ValueError, "calendar"):
            self.reserve()
        self.assertEqual(self.registry.snapshot()["claims"], {})

    def test_distinct_scopes_cannot_reset_whole_preparation_attempt_limit(self):
        for number in range(3):
            value = task("replacement-" + str(number))
            grant = authority("scope-" + str(number))
            grant["jobs"]["environment"]["task_sha256"] = reg.identity(value)
            self.finish(self.reserve(value, grant), "FAILED_RECONCILED")
        value = task("replacement-3")
        grant = authority("scope-3")
        grant["jobs"]["environment"]["task_sha256"] = reg.identity(value)
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(value, grant)
        state = self.registry.snapshot()
        self.assertEqual(sum(s["attempts"] for s in state["scopes"].values()), 3)
        self.assertEqual(sum(s["reserved_CPU_seconds"] for s in state["scopes"].values()), 180)

    def test_distinct_scopes_cannot_reset_the_aggregate_cpu_reservation(self):
        first = authority("scope-1", max_reserved_CPU_seconds=1800)
        first["jobs"]["environment"]["wall_seconds"] = 1800
        self.finish(self.reserve(grant=first), "FAILED_RECONCILED")
        second = authority("scope-2", max_reserved_CPU_seconds=1600)
        second["jobs"]["parity"]["wall_seconds"] = 1600
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(task("parity-1", "parity"), second)
        self.assertEqual(self.registry.snapshot(), before)

    def test_recovery_amendment_preserves_every_claim_and_paid_scope_exactly(self):
        document = self.recovery_document()
        before = self.registry.snapshot()
        self.assertEqual(sum(s["reserved_CPU_seconds"] for s in before["scopes"].values()), 2400)
        self.assertEqual(self.registry.amend_channel_recovery_budget(document), document["to"])
        # A new handle must read the persisted amendment, not infer a new scope.
        after = reg.Registry(self.registry.root).snapshot()
        self.assertEqual(after["claims"], before["claims"])
        self.assertEqual(after["scopes"], before["scopes"])
        self.assertEqual(after["budget_policy"], {"max_attempts": 4, "max_reserved_CPU_seconds": 4500})
        self.assertEqual(len(after["budget_amendments"]), 1)
        self.assertEqual(after["budget_amendments"][0]["sha256"], reg.identity(document))
        self.assertEqual(after["budget_amendments"][0]["document"], document)

    def test_recovery_spending_retains_2400_then_3600_then_4500_without_refund(self):
        document = self.recovery_document()
        prior = self.registry.snapshot()
        self.registry.amend_channel_recovery_budget(document)
        for label, kind, wall, expected in (("env03", "environment", 1200, 3600),
                                            ("parity", "parity", 900, 4500)):
            value, grant = self.admitted_job(label, kind, wall)
            self.finish(self.reserve(value, grant))
            state = reg.Registry(self.registry.root).snapshot()
            self.assertEqual(sum(s["reserved_CPU_seconds"] for s in state["scopes"].values()), expected)
            self.assertEqual(state["budget_amendments"][0]["document"], document)
            for name, scope in prior["scopes"].items():
                self.assertEqual(state["scopes"][name], scope)
            for key, claim in prior["claims"].items():
                self.assertEqual(state["claims"][key], claim)
        value, grant = self.admitted_job("fifth", "environment", 1)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(value, grant)
        self.assertEqual(self.registry.snapshot(), before)
        self.assertEqual(sum(s["attempts"] for s in before["scopes"].values()), 4)

    def test_recovery_cpu_ceiling_cannot_be_exceeded_before_fourth_attempt(self):
        self.registry.amend_channel_recovery_budget(self.recovery_document())
        self.finish(self.reserve(*self.admitted_job("env03", "environment", 1200)))
        value, grant = self.admitted_job("oversized-parity", "parity", 1000)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(value, grant)
        self.assertEqual(self.registry.snapshot(), before)
        self.assertEqual(sum(s["attempts"] for s in before["scopes"].values()), 3)

    def test_recovery_amendment_requires_all_prior_claims_terminal(self):
        document = self.recovery_document(leave_second_unresolved=True)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "unresolved"):
            self.registry.amend_channel_recovery_budget(document)
        self.assertEqual(self.registry.snapshot(), before)

    def test_recovery_amendment_cannot_be_repeated(self):
        document = self.recovery_document()
        self.registry.amend_channel_recovery_budget(document)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "already spent"):
            self.registry.amend_channel_recovery_budget(document)
        self.assertEqual(self.registry.snapshot(), before)

    def test_recovery_amendment_rejects_tampered_failure_and_prior_scope_pins(self):
        document = self.recovery_document()
        before = self.registry.snapshot()
        bad_failure = copy.deepcopy(document)
        bad_failure["failure_evidence"]["sha256"] = "b" * 64
        bad_scope = dict(document, carried_scopes_sha256="b" * 64)
        bad_ids = dict(document, carried_scope_ids=document["carried_scope_ids"][:1])
        for changed in (bad_failure, bad_scope, bad_ids):
            with self.subTest(document=changed), self.assertRaises(ValueError):
                self.registry.amend_channel_recovery_budget(changed)
            self.assertEqual(self.registry.snapshot(), before)
        Path(document["failure_evidence"]["path"]).write_text("changed failure bytes")
        with self.assertRaisesRegex(ValueError, "evidence pin"):
            self.registry.amend_channel_recovery_budget(document)
        self.assertEqual(self.registry.snapshot(), before)

    def test_recovery_amendment_rejects_foreign_host_reason_and_oversized_policy(self):
        document = self.recovery_document()
        before = self.registry.snapshot()
        for changed in ({"controller": "hb.ucsc.edu"}, {"reason_code": "AUTOMATIC_RETRY"},
                        {"from": {"max_attempts": 3, "max_reserved_CPU_seconds": 0}},
                        {"to": {"max_attempts": 5, "max_reserved_CPU_seconds": 4500}},
                        {"to": {"max_attempts": 4, "max_reserved_CPU_seconds": 4501}}):
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, "unsupported finite"):
                self.registry.amend_channel_recovery_budget(dict(document, **changed))
            self.assertEqual(self.registry.snapshot(), before)

    def test_expanded_policy_without_a_recorded_amendment_cannot_authorize_spending(self):
        self.recovery_document()
        state = self.registry.snapshot()
        state["budget_policy"] = {"max_attempts": 4, "max_reserved_CPU_seconds": 4500}
        reg.write(self.registry.path, state)
        value, grant = self.admitted_job("env03", "environment", 1200)
        with self.assertRaises(ValueError):
            self.reserve(value, grant)
        self.assertEqual(reg.read(self.registry.path), state)

    def test_tampered_recorded_amendment_cannot_authorize_spending(self):
        document = self.recovery_document()
        self.registry.amend_channel_recovery_budget(document)
        state = self.registry.snapshot()
        state["budget_amendments"][0]["document"]["reason_code"] = "SILENT_RESET"
        reg.write(self.registry.path, state)
        value, grant = self.admitted_job("env03", "environment", 1200)
        with self.assertRaises(ValueError):
            self.reserve(value, grant)
        self.assertEqual(reg.read(self.registry.path), state)

    def test_carried_reservation_cannot_be_lowered_after_amendment(self):
        document = self.recovery_document()
        self.registry.amend_channel_recovery_budget(document)
        state = self.registry.snapshot()
        state["scopes"][document["carried_scope_ids"][0]]["reserved_CPU_seconds"] = 0
        reg.write(self.registry.path, state)
        value, grant = self.admitted_job("env03", "environment", 1200)
        with self.assertRaises(ValueError):
            self.reserve(value, grant)
        self.assertEqual(reg.read(self.registry.path), state)

    def test_changed_failure_bytes_after_amendment_block_new_spending(self):
        document = self.recovery_document()
        self.registry.amend_channel_recovery_budget(document)
        state = self.registry.snapshot()
        Path(document["failure_evidence"]["path"]).write_text("altered retained failure")
        value, grant = self.admitted_job("env03", "environment", 1200)
        with self.assertRaises(ValueError):
            self.reserve(value, grant)
        self.assertEqual(self.registry.snapshot(), state)

    def test_reference_profile_amendment_preserves_all_four_spent_claims_and_both_events(self):
        document = self.reference_profile_document()
        before = self.registry.snapshot()
        self.assertEqual(sum(s["attempts"] for s in before["scopes"].values()), 4)
        self.assertEqual(sum(s["reserved_CPU_seconds"] for s in before["scopes"].values()), 4500)
        self.assertEqual(self.registry.amend_reference_profile_budget(document), document["to"])
        after = reg.Registry(self.registry.root).snapshot()
        self.assertEqual(after["claims"], before["claims"])
        self.assertEqual(after["scopes"], before["scopes"])
        self.assertEqual(after["budget_amendments"][:1], before["budget_amendments"])
        self.assertEqual(len(after["budget_amendments"]), 2)
        self.assertEqual(after["budget_amendments"][1]["document"], document)
        self.assertEqual(after["budget_amendments"][1]["sha256"], reg.identity(document))
        self.assertEqual(reg.budget_policy(after), {"max_attempts": 5, "max_reserved_CPU_seconds": 5400})

    def test_reference_profile_allows_one_900_reservation_without_refunding_4500(self):
        document = self.reference_profile_document()
        self.registry.amend_reference_profile_budget(document)
        before = self.registry.snapshot()
        value, grant = self.admitted_job("historical-profile-parity", "parity", 900)
        self.finish(self.reserve(value, grant), "FAILED_RECONCILED")
        after = self.registry.snapshot()
        self.assertEqual(sum(s["attempts"] for s in after["scopes"].values()), 5)
        self.assertEqual(sum(s["reserved_CPU_seconds"] for s in after["scopes"].values()), 5400)
        self.assertEqual(after["budget_amendments"], before["budget_amendments"])
        for key, claim in before["claims"].items():
            self.assertEqual(after["claims"][key], claim)
        for key, scope in before["scopes"].items():
            self.assertEqual(after["scopes"][key], scope)
        value, grant = self.admitted_job("sixth-is-forbidden", "parity", 1)
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(value, grant)
        self.assertEqual(self.registry.snapshot(), after)

    def test_reference_profile_amendment_is_once_only(self):
        document = self.reference_profile_document()
        self.registry.amend_reference_profile_budget(document)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "already spent"):
            self.registry.amend_reference_profile_budget(document)
        self.assertEqual(self.registry.snapshot(), before)

    def test_reference_profile_amendment_requires_the_old_parity_claim_terminal(self):
        document = self.reference_profile_document(leave_parity_unresolved=True)
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "unresolved"):
            self.registry.amend_reference_profile_budget(document)
        self.assertEqual(self.registry.snapshot(), before)

    def test_reference_profile_amendment_rejects_wrong_profile_and_oversized_policy(self):
        document = self.reference_profile_document()
        before = self.registry.snapshot()
        for changed in ({"numerical_profile": "Haswell"}, {"controller": "hb.ucsc.edu"},
                        {"reason_code": "RELAX_NUMERICAL_TOLERANCE"},
                        {"to": {"max_attempts": 6, "max_reserved_CPU_seconds": 5400}},
                        {"to": {"max_attempts": 5, "max_reserved_CPU_seconds": 5401}}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.registry.amend_reference_profile_budget(dict(document, **changed))
            self.assertEqual(self.registry.snapshot(), before)

    def test_reference_profile_amendment_requires_both_evidence_pins_and_complete_carry(self):
        document = self.reference_profile_document()
        before = self.registry.snapshot()
        for field in ("failure_evidence", "reference_profile_evidence"):
            changed = copy.deepcopy(document)
            changed[field]["sha256"] = "b" * 64
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.registry.amend_reference_profile_budget(changed)
            self.assertEqual(self.registry.snapshot(), before)
        for changed in ({"carried_scope_ids": document["carried_scope_ids"][:-1]},
                        {"carried_scopes_sha256": "b" * 64}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.registry.amend_reference_profile_budget(dict(document, **changed))
            self.assertEqual(self.registry.snapshot(), before)

    def test_reference_profile_amendment_cannot_skip_the_channel_event(self):
        document = self.reference_profile_document()
        state = self.registry.snapshot()
        state["budget_amendments"] = []
        reg.write(self.registry.path, state)
        with self.assertRaises(ValueError):
            self.registry.amend_reference_profile_budget(document)
        self.assertEqual(reg.read(self.registry.path), state)

    def test_reference_profile_amendment_cannot_be_applied_before_four_attempts_and_4500_spent(self):
        first=self.recovery_document()
        self.registry.amend_channel_recovery_budget(first)
        reference=self.root/'premature-reference.json';reg.write(reference,{'profile':'Sandybridge_AVX_v1'})
        state=self.registry.snapshot()
        document={'schema':'r156-budget-amendment-v1','controller':HOST,
            'from':{'max_attempts':4,'max_reserved_CPU_seconds':4500},
            'to':{'max_attempts':5,'max_reserved_CPU_seconds':5400},
            'reason_code':'REFERENCE_CPU_PROFILE_SANDYBRIDGE','numerical_profile':'Sandybridge_AVX_v1',
            'failure_evidence':first['failure_evidence'],
            'reference_profile_evidence':{'path':str(reference),'sha256':reg.digest(reference)},
            'carried_scope_ids':sorted(state['scopes']),'carried_scopes_sha256':reg.identity(state['scopes'])}
        with self.assertRaises(ValueError):self.registry.amend_reference_profile_budget(document)
        self.assertEqual(self.registry.snapshot(),state)
        self.assertEqual(sum(s['reserved_CPU_seconds'] for s in state['scopes'].values()),2400)

    def test_reference_profile_policy_needs_both_exact_events_before_any_spending(self):
        document = self.reference_profile_document()
        self.registry.amend_reference_profile_budget(document)
        original = self.registry.snapshot()
        variants = []
        for records in ([], original["budget_amendments"][:1], original["budget_amendments"][1:],
                        list(reversed(original["budget_amendments"]))):
            changed = copy.deepcopy(original)
            changed["budget_amendments"] = records
            variants.append(changed)
        changed = copy.deepcopy(original)
        changed["budget_amendments"][1]["sha256"] = "b" * 64
        variants.append(changed)
        for number, changed in enumerate(variants):
            reg.write(self.registry.path, changed)
            value, grant = self.admitted_job("forbidden-profile-" + str(number), "parity", 900)
            with self.subTest(number=number), self.assertRaises(ValueError):
                self.reserve(value, grant)
            self.assertEqual(reg.read(self.registry.path), changed)

    def test_reference_profile_carried_fourth_charge_cannot_be_lowered(self):
        document = self.reference_profile_document()
        self.registry.amend_reference_profile_budget(document)
        state = self.registry.snapshot()
        state["scopes"]["strict-native-parity-scope"]["reserved_CPU_seconds"] = 0
        reg.write(self.registry.path, state)
        value, grant = self.admitted_job("forbidden-profile", "parity", 900)
        with self.assertRaisesRegex(ValueError, "scope charges"):
            self.reserve(value, grant)
        self.assertEqual(reg.read(self.registry.path), state)

    def test_reference_profile_changed_evidence_after_amendment_blocks_spending(self):
        document = self.reference_profile_document()
        self.registry.amend_reference_profile_budget(document)
        state = self.registry.snapshot()
        for field in ("failure_evidence", "reference_profile_evidence"):
            path = Path(document[field]["path"])
            old = path.read_bytes()
            path.write_text("changed retained evidence")
            value, grant = self.admitted_job("forbidden-profile", "parity", 900)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "evidence changed"):
                self.reserve(value, grant)
            self.assertEqual(self.registry.snapshot(), state)
            path.write_bytes(old)

    def test_reference_profile_aggregate_ceiling_rejects_901_without_consuming_the_probe(self):
        self.registry.amend_reference_profile_budget(self.reference_profile_document())
        before = self.registry.snapshot()
        value, grant = self.admitted_job("oversized-profile", "parity", 901)
        with self.assertRaisesRegex(ValueError, "whole-preparation budget"):
            self.reserve(value, grant)
        self.assertEqual(self.registry.snapshot(), before)
        value, grant = self.admitted_job("historical-profile", "parity", 900)
        claim = self.reserve(value, grant)
        self.assertEqual(claim["reserved_CPU_seconds"], 900)
        self.assertEqual(sum(s["reserved_CPU_seconds"] for s in self.registry.snapshot()["scopes"].values()), 5400)

    def test_transitions_bind_exact_expected_state_and_keep_history(self):
        claim = self.reserve()
        key = claim["task_key"]
        self.registry.transition(key, "RESERVED", "STAGED", remote_directory="/remote/TEST")
        before = self.registry.snapshot()
        with self.assertRaisesRegex(ValueError, "state changed"):
            self.registry.transition(key, "RESERVED", "STAGED")
        with self.assertRaisesRegex(ValueError, "unreviewed"):
            self.registry.transition(key, "STAGED", "COLLECTED")
        self.assertEqual(self.registry.snapshot(), before)
        self.assertEqual(before["claims"][key]["events"][0]["from"], "RESERVED")

    def test_transition_cannot_replace_any_immutable_identity_or_budget(self):
        claim = self.reserve()
        for field in ("task_key", "task", "scope_id", "authority_sha256", "release_sha256",
                      "reserved_CPU_seconds", "attempt_id", "created", "events", "state"):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "immutable"):
                self.registry.transition(claim["task_key"], "RESERVED", "STAGED", **{field: "replacement"})
        self.assertEqual(self.registry.snapshot()["claims"][claim["task_key"]]["state"], "RESERVED")

    def test_poll_is_for_submitted_work_and_has_a_three_hundred_second_floor(self):
        claim = self.reserve()
        key = claim["task_key"]
        with self.assertRaises(ValueError):
            self.registry.poll(key)
        self.submit(claim)
        self.registry.poll(key)
        self.clock.return_value = NOW + 299.999
        with self.assertRaises(ValueError):
            self.registry.poll(key)
        self.clock.return_value = NOW + 300
        self.registry.poll(key)
        self.registry.transition(key, "SUBMITTED", "COLLECTED")
        self.clock.return_value = NOW + 900
        with self.assertRaises(ValueError):
            self.registry.poll(key)

    def test_backward_clock_does_not_bypass_poll_throttle(self):
        claim = self.reserve()
        key = self.submit(claim)
        self.registry.poll(key)
        self.clock.return_value = NOW - 1
        with self.assertRaises(ValueError):
            self.registry.poll(key)

    def test_storage_failure_does_not_publish_a_partial_claim(self):
        with mock.patch.object(reg, "write", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.reserve()
        self.assertEqual(self.registry.snapshot()["claims"], {})

    def test_failure_after_atomic_publication_keeps_the_task_spent(self):
        # A directory fsync error occurs after os.replace. The caller must not
        # interpret its missing success receipt as permission to resubmit.
        with mock.patch.object(reg.os, "fsync", side_effect=[None, OSError("directory sync failed")]):
            with self.assertRaises(OSError):
                self.reserve()
        state = self.registry.snapshot()
        self.assertEqual(len(state["claims"]), 1)
        self.assertEqual(state["scopes"][self.grant["scope_id"]]["attempts"], 1)
        self.assertEqual(state["scopes"][self.grant["scope_id"]]["reserved_CPU_seconds"], 60)
        with self.assertRaisesRegex(ValueError, "claimed/spent"):
            self.reserve()

    def test_competing_controller_handles_publish_only_one_claim(self):
        second = reg.Registry(self.registry.root)

        def attempt(handle):
            try:
                return handle.reserve(self.grant, task(), RELEASE)["attempt_id"]
            except ValueError:
                return None

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, (self.registry, second)))
        self.assertEqual(sum(value is not None for value in results), 1)
        state = self.registry.snapshot()
        self.assertEqual(len(state["claims"]), 1)
        self.assertEqual(state["scopes"][self.grant["scope_id"]]["attempts"], 1)

    def test_registry_root_and_symlinked_parent_are_rejected(self):
        target = self.root / "target"
        target.mkdir()
        link = self.root / "link"
        link.symlink_to(target, target_is_directory=True)
        for path in (link, link / "child"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "symlink"):
                reg.Registry(path)

    def test_registry_snapshot_rejects_a_symlinked_state_file(self):
        target = self.root / "outside.json"
        target.write_bytes(reg.canonical({"schema": reg.SCHEMA, "scopes": {}, "claims": {}}))
        self.registry.path.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.registry.snapshot()

    def test_symlinked_lock_rejects_before_reservation(self):
        target = self.root / "outside.lock"
        target.touch()
        (self.registry.root / "registry.lock").symlink_to(target)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.reserve()
        self.assertFalse(self.registry.path.exists())

    def test_nonfinite_json_cannot_enter_authoritative_state(self):
        self.registry.path.write_text('{"schema":"x","scopes":{},"claims":{},"invalid":NaN}')
        with self.assertRaisesRegex(ValueError, "nonfinite"):
            self.registry.snapshot()

    def test_task_identity_is_canonical_and_nonfinite_task_is_rejected(self):
        self.assertEqual(reg.identity({"a": 1, "b": 2}), reg.identity({"b": 2, "a": 1}))
        invalid = task()
        invalid["metric"] = float("nan")
        with self.assertRaises(ValueError):
            self.reserve(invalid)
        self.assertEqual(self.registry.snapshot()["claims"], {})


if __name__ == "__main__":
    unittest.main()
