"""Closed-EE semantics, real private flock inspection and successor negatives."""
import copy
import fcntl
import os
from pathlib import Path
import unittest
from unittest import mock
from . import handoff as h, policy as p, registry as r
from .policy_tests import PolicyFixture


class HandoffTests(PolicyFixture):
    def setUp(self):
        super().setUp()
        self.identities = {
            "guardian.json": {"pid": 2147000000, "start_ticks": 100, "boot_id": "fixture-boot",
                              "cmdline_sha256": "a" * 64},
            "payload_identity.json": {"pid": 2147000001, "start_ticks": 200, "boot_id": "fixture-boot",
                                      "cmdline_sha256": "b" * 64}}
        package = "r134_5c42f007409acfb3"
        self.names = ["EE_{}_s{}_S_seed{}".format(pkg, split, seed)
                      for pkg in ("C0", package) for seed in (1, 2) for split in (1, 2, 3)]
        unit = {"Id": "fixture-EE.service", "InvocationID": "c" * 32,
                "Result": "success", "ExecMainStatus": "0", "MainPID": "0",
                "SubState": "exited", "RemainAfterExit": "yes", "Restart": "no", "NRestarts": "0"}
        assessment = {"required_task_names": self.names,
                      "qualified_from_unchanged_initial_S0": [package],
                      "status": "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT_NOT_PROMOTED",
                      "AL_proposal_admitted": False, "automatic_followon": False,
                      "new_fits": 0, "official_origins": 0,
                      "all_new_components_independently_revalidated": True}
        ap = self.write("assessment.json", assessment)
        values = {
            "assessment.json": assessment,
            "assessment_seal.json": {"assessment": ap},
            "exit_receipt.json": {"status": "COMPLETE_MATCHED_THREE_SEED_DEVELOPMENT",
                                   "process": self.identities["payload_identity.json"],
                                   "supervisor": self.identities["guardian.json"], "epoch": self.now - 1000},
            "supervisor_exit_receipt.json": {"status": "PAYLOAD_EXITED", "child_exit_code": 0,
                                              "payload": self.identities["payload_identity.json"],
                                              "parent": self.identities["guardian.json"], "epoch": self.now - 999},
            "claim.json": {"required_tasks": self.names, "permit_id": "muscat_cpu30", "unit": unit},
            "full_matched_set.json": {"components": 12, "required_task_names": self.names}}
        records = {name: {"pin": self.write(name, value), "value": value} for name, value in values.items()}
        self.raw = {"status": "READ_ONLY_SOURCE_BOUND_MATCHED_SEED_OBSERVATION",
                    "complete_components": 12, "required_components": 12, "remaining_components": 0,
                    "new_fits": 0, "new_forecasts": 0, "runtime_writes": 0, "signals": 0,
                    "epoch": self.now, "actual_unit": unit, "records": records,
                    "same_original_flock_free": True, "scientifically_complete_and_physically_drained": True,
                    "processes": [{"role": key, "recorded": value, "live_exact_lifetime": False}
                                  for key, value in self.identities.items()],
                    "source": {"branch": "fixture-EE", "head": "d" * 40},
                    "authority": self.write("original-authority.json", {"purpose": "fixture"})}
        history = dict(self.raw, epoch=self.now - 600)
        self.history = self.write("historical_EE.json", history)
        self.draft = dict(self.draft, historical_EE_release=self.history)
        self.packet = self.admit(self.draft)
        self.policy_pin = self.write("policy.json", self.packet)
        self.raw_pin = self.write("fresh_EE.json", self.raw)
        self.delivery = self.write("delivered_report.json", {"status": "delivered"})

    def build(self, raw_pin=None, owner_pin=None):
        return h.build_handoff_receipt(raw_pin or self.raw_pin, self.history, self.delivery,
                                       self.policy_pin, owner_pin, now=self.now)

    def successor(self):
        admission, admission_pin = self.owner_admission()
        identity = {"pid": 123456, "start_ticks": 999, "boot_id": "fixture-current-boot",
                    "cmdline_sha256": "e" * 64, "argv": ["python", self.source_pin["path"]],
                    "state": "R", "executable": "/usr/bin/python3.11",
                    "executable_device": 1, "executable_inode": 777}
        value = {"schema": h.OWNER_RECEIPT_SCHEMA, "status": "LIVE_EXACT_LOCAL_PERMIT_OWNER",
                 "host": p.OWNER, "observed_epoch": self.now, "scope_id": admission["scope_id"],
                 "cross_host_policy": self.policy_pin, "owner_admission": admission_pin,
                 "permit_lock": self.packet["local_permit"]["lock"], "held_fd": 7,
                 "process": identity, "CPU_accounting_complete_so_far": True, "unowned_helpers": [],
                 "phase": "SCIENCE"}
        return identity, value, self.write("owner_live.json", value)

    def successor_context(self, identity):
        def process(pid):
            return identity if pid == identity["pid"] else None
        return mock.patch.object(h, "process_identity", side_effect=process)

    def test_actual_private_lock_free_build_passes(self):
        result = self.build()
        self.assertEqual(result["status"], h.STATUS)
        self.assertEqual(result["current_permit"]["status"], "FREE")
        self.assertEqual(result["raw_source529_lock_free"], True)
        h.validate_handoff_receipt(result, self.packet, now=self.now, check_live=True)

    def test_old_observer_false_is_retained_not_relabelled_free(self):
        raw = dict(self.raw, same_original_flock_free=False,
                   scientifically_complete_and_physically_drained=False)
        result = self.build(self.write("raw_false.json", raw))
        self.assertIs(result["raw_source529_lock_free"], False)
        self.assertIs(result["raw_source529_global_drained"], False)
        self.assertIs(result["current_permit"]["actual_original_lock_free"], True)
        self.assertEqual(result["status"], h.STATUS)

    def test_live_approved_successor_allows_truthful_parallel_handoff(self):
        identity, _, op = self.successor()
        raw = dict(self.raw, same_original_flock_free=False,
                   scientifically_complete_and_physically_drained=False)
        with mock.patch.object(h, "probe_lock", return_value=False), self.successor_context(identity), \
                mock.patch.object(h, "_held_fd", return_value={"holder_pid": identity["pid"], "fdinfo": "proved"}):
            result = self.build(self.write("raw_owned.json", raw), op)
            h.validate_handoff_receipt(result, self.packet, now=self.now, check_live=True)
        self.assertEqual(result["current_permit"]["status"], "APPROVED_SUCCESSOR")
        self.assertIs(result["current_permit"]["actual_original_lock_free"], False)
        self.assertIs(result["raw_source529_lock_free"], False)

    def test_real_occupied_unknown_private_lock_blocks_without_signals(self):
        with self.lock.open("r+") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(h.HandoffError):
                self.build()
        self.assertTrue(h.probe_lock(self.packet["local_permit"]["lock"]))

    def test_real_kernel_fdinfo_proves_exact_acquiring_owner(self):
        with self.lock.open("r+") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            proof = h._held_fd(os.getpid(), f.fileno(), self.packet["local_permit"]["lock"])
            self.assertEqual(proof["holder_pid"], os.getpid())
            with self.assertRaises(h.HandoffError):
                h._held_fd(os.getpid(), f.fileno(), dict(self.packet["local_permit"]["lock"], inode=1))

    def test_unlocked_descriptor_is_not_accepted_as_ownership(self):
        with self.lock.open("r+") as f, self.assertRaises(h.HandoffError):
            h._held_fd(os.getpid(), f.fileno(), self.packet["local_permit"]["lock"])

    def test_reused_successor_pid_and_different_source_argv_block(self):
        identity, _, op = self.successor()
        for replacement in (dict(identity, start_ticks=1000),
                            dict(identity, boot_id="different-boot"),
                            dict(identity, executable_inode=778),
                            dict(identity, argv=["python", "some-other-entry.py"])):
            with mock.patch.object(h, "probe_lock", return_value=False), self.successor_context(replacement), \
                    mock.patch.object(h, "_held_fd"), self.assertRaises(h.HandoffError):
                self.build(owner_pin=op)

    def test_old_EE_exact_lifetime_still_live_blocks_even_if_lock_free(self):
        old = self.identities["guardian.json"]
        with mock.patch.object(h, "process_identity", return_value=old), self.assertRaises(h.HandoffError):
            self.build()

    def test_original_process_reexec_does_not_make_its_kernel_lifetime_dead(self):
        old = dict(self.identities["guardian.json"], cmdline_sha256="f" * 64)
        with mock.patch.object(h, "process_identity", return_value=old), self.assertRaises(h.HandoffError):
            self.build()

    def test_stale_source529_or_future_observation_blocks(self):
        for epoch in (self.now - 301, self.now + 1):
            with self.assertRaises(h.HandoffError):
                self.build(self.write("raw_" + str(epoch) + ".json", dict(self.raw, epoch=epoch)))

    def test_occupied_owner_receipt_requires_fresh_complete_accounting(self):
        identity, value, _ = self.successor()
        for changes in ({"observed_epoch": self.now - 61},
                        {"CPU_accounting_complete_so_far": False}, {"unowned_helpers": [999]},
                        {"host": "jerez.be.ucsc.edu"}, {"cross_host_policy": self.history}):
            op = self.write("owner_" + r.identity(changes) + ".json", dict(value, **changes))
            with mock.patch.object(h, "probe_lock", return_value=False), self.successor_context(identity), \
                    self.assertRaises(h.HandoffError):
                self.build(owner_pin=op)

    def test_owner_expired_stage_and_noncanonical_admission_block(self):
        identity, value, _ = self.successor()
        admission = r.read(value["owner_admission"]["path"])
        for name, updated in (("wrong_location", admission),
                              ("expired", dict(admission, expires_epoch=self.now))):
            ap = self.write(name + ".json", updated)
            op = self.write(name + "_owner.json", dict(value, owner_admission=ap))
            with mock.patch.object(h, "probe_lock", return_value=False), self.successor_context(identity), \
                    self.assertRaises((h.HandoffError, p.PolicyError)):
                self.build(owner_pin=op)

    def test_raw_snapshot_cannot_claim_different_pinned_assessment(self):
        raw = copy.deepcopy(self.raw)
        raw["records"]["assessment.json"]["value"]["AL_proposal_admitted"] = True
        with self.assertRaises(h.HandoffError):
            self.build(self.write("raw_mutated.json", raw))

    def test_failed_or_changed_original_systemd_invocation_blocks(self):
        for fields in ({"InvocationID": "f" * 32}, {"Result": "failed"}, {"NRestarts": "1"},
                       {"MainPID": "123"}, {"SubState": "running"}):
            raw = copy.deepcopy(self.raw)
            raw["actual_unit"].update(fields)
            with self.assertRaises(h.HandoffError):
                self.build(self.write("raw_unit_" + r.identity(fields) + ".json", raw))

    def test_historical_free_anchor_is_exact_policy_bound(self):
        history = self.write("unapproved_release.json", self.raw)
        with self.assertRaises(h.HandoffError):
            h.build_handoff_receipt(self.raw_pin, history, self.delivery, self.policy_pin, now=self.now)

    def test_new_model_or_incomplete_component_observation_blocks(self):
        for changes in ({"complete_components": 11}, {"remaining_components": 1},
                        {"new_forecasts": 1}, {"signals": 1}):
            with self.assertRaises(h.HandoffError):
                self.build(self.write("bad_counts_" + r.identity(changes) + ".json", dict(self.raw, **changes)))

    def test_remote_pure_validation_never_touches_Muscat_proc_or_paths(self):
        result = self.build()
        with mock.patch.object(h, "process_identity", side_effect=AssertionError("foreign /proc")), \
                mock.patch.object(h, "probe_lock", side_effect=AssertionError("foreign lock")), \
                mock.patch.object(r, "digest", side_effect=AssertionError("foreign path")):
            h.validate_handoff_receipt(result, self.packet, now=self.now)

    def test_remote_receipt_cannot_extend_freshness_or_change_policy(self):
        result = self.build()
        for changes in ({"observed_epoch": self.now - 301}, {"policy_identity_sha256": "0" * 64},
                        {"old_EE_exact_lifetimes_live": [1]}, {"new_forecasts": 1}):
            with self.assertRaises(h.HandoffError):
                h.validate_handoff_receipt(dict(result, **changes), self.packet, now=self.now)

    def test_lock_replacement_is_detected_without_creation_or_repair(self):
        self.lock.rename(self.root / "original-retained.lock")
        self.lock.write_text("different inode")
        with self.assertRaises(p.PolicyError):
            self.build()

    def test_build_cannot_run_on_a_numerical_core(self):
        with mock.patch.object(os, "sched_getaffinity", return_value={30}), self.assertRaises(h.HandoffError):
            self.build()


if __name__ == "__main__":
    unittest.main()
