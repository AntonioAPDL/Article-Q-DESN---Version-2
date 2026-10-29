"""Adversarial metadata-only witnesses for R164 repair readiness."""
import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

from . import repair_readiness as r


def fixture():
    target = "1" * 64 + ":tau=0.5:tau0=0.001"
    contract = dict(family="al", max_iter=300, certificate_limits=dict(r.LIMITS),
                    prior_center_from_initializer=False, test_opened=False, seed=19,
                    tau=.5, tau0=.001, posterior_target_sha256=target)
    certificate = dict(certified=False, limits=dict(r.LIMITS), initialization_changes_prior=False,
                       checks={k: k != "elbo_relative" for k in r.LIMITS},
                       measures={k: v * (2 if k == "elbo_relative" else .5) for k, v in r.LIMITS.items()},
                       rhs_reconstruction=dict(unit_converged=True, dispersed_converged=True))
    terminal = dict(family="al", prior_center_from_initializer=False, test_opened=False, rhs_freeze_iters=0,
                    tau=.5, tau0=.001, posterior_target_sha256=target, n=1024, p=32, finite_core=True,
                    formal_converged=False, independent_fixedpoint_certified=False,
                    computationally_certified=False, iterations=300, termination="iteration_cap_uncertified",
                    status="completed_r137_certified_al_fit", exact_optimizer_resumption_supported=False,
                    full_fit_object_retained=False, initialization_only=True)
    return terminal, certificate, contract


class CertificateWitnesses(unittest.TestCase):
    def test_positive_status_does_not_accept_false_certificate(self):
        state = r.certificate_state(*fixture())
        self.assertEqual(state["state"], "SAVED_FAILED_ORIGINAL")
        self.assertEqual(state["failed_checks"], ["elbo_relative"])
        self.assertFalse(state["exact_optimizer_resumption_supported"])

    def test_formal_or_independent_with_finite_and(self):
        t, c, k = fixture()
        t.update(formal_converged=True, computationally_certified=True)
        self.assertEqual(r.certificate_state(t, c, k)["state"], "SAVED_ACCEPTED_ORIGINAL")
        t.update(finite_core=False, computationally_certified=False)
        self.assertEqual(r.certificate_state(t, c, k)["state"], "SAVED_FAILED_ORIGINAL")

    def test_independent_requires_both_rhs_starts(self):
        t, c, k = fixture()
        c["checks"] = {key: True for key in r.LIMITS}
        c["measures"] = {key: value / 2 for key, value in r.LIMITS.items()}
        c["rhs_reconstruction"]["dispersed_converged"] = False
        self.assertFalse(r.certificate_state(t, c, k)["independent_fixedpoint_certified"])
        c["certified"] = True
        t["independent_fixedpoint_certified"] = True
        t["computationally_certified"] = True
        with self.assertRaisesRegex(r.EvidenceError, "booleans disagree"):
            r.certificate_state(t, c, k)

    def test_caps_limits_seed_prior_and_target_cannot_weaken(self):
        for owner, key, value in ((2, "max_iter", 301), (2, "max_iter", True),
                                  (2, "seed", True), (2, "prior_center_from_initializer", True),
                                  (0, "posterior_target_sha256", "different"), (0, "rhs_freeze_iters", 1),
                                  (0, "test_opened", True), (0, "iterations", 301)):
            with self.subTest(key=key, value=value):
                values = list(fixture()); values[owner][key] = value
                with self.assertRaises(r.EvidenceError):
                    r.certificate_state(*values)
        t, c, k = fixture(); k["certificate_limits"]["elbo_relative"] *= 10
        with self.assertRaises(r.EvidenceError):
            r.certificate_state(t, c, k)

    def test_measure_check_disagreement_and_nonfinite_rejected(self):
        for value in (0.0, -1.0, float("nan"), float("inf"), True):
            t, c, k = fixture(); c["measures"]["elbo_relative"] = value
            with self.subTest(value=value), self.assertRaises(r.EvidenceError):
                r.certificate_state(t, c, k)

    def test_missing_gate_or_nonboolean_flag_rejected(self):
        t, c, k = fixture(); del c["checks"]["rhs_start_log_precision"]
        with self.assertRaises(r.EvidenceError): r.certificate_state(t, c, k)
        t, c, k = fixture(); t["computationally_certified"] = 0
        with self.assertRaises(r.EvidenceError): r.certificate_state(t, c, k)


class DAGWitnesses(unittest.TestCase):
    @staticmethod
    def graph():
        return {name: dict(name=name, depends=deps) for name, deps in
                (("a", []), ("b", []), ("c", ["a"]), ("d", ["a", "b"]),
                 ("e", ["c", "d"]), ("new", ["e"]))}

    def test_transitive_overlap_and_new_descendant(self):
        g = self.graph(); value = r.descendant_closure(g, ["a", "b"])
        self.assertEqual(value["union"], ["c", "d", "e", "new"])
        self.assertEqual(value["per_parent_sum"], 7)
        self.assertEqual(value["union_count"], 4)
        self.assertIn("new", value["per_parent"]["b"])

    def test_failed_parent_can_also_be_descendant(self):
        value = r.descendant_closure(self.graph(), ["a", "c"])
        self.assertEqual(value["repair_anchors_also_descendants"], ["c"])
        self.assertEqual(value["remaining_nonanchor_descendants"], ["d", "e", "new"])

    def test_dangling_dependency_requires_explicit_unproved_annotation(self):
        g = self.graph(); g["a"]["depends"] = ["outside"]
        with self.assertRaisesRegex(r.EvidenceError, "undeclared missing"):
            r.descendant_closure(g, ["a"])
        value = r.descendant_closure(g, ["a"], ["outside"])
        self.assertEqual(value["external_prerequisites_unproved"], ["outside"])
        self.assertEqual(value["union_count"], 4)

    def test_cycle_duplicate_dependency_and_alias_rejected(self):
        for variant in ("cycle", "duplicate", "alias", "unused_external"):
            g = self.graph()
            if variant == "cycle": g["a"]["depends"] = ["new"]
            if variant == "duplicate": g["c"]["depends"] = ["a", "a"]
            if variant == "alias": g["a"]["name"] = "b"
            with self.subTest(variant=variant), self.assertRaises(r.EvidenceError):
                r.validate_dag(g, ["unused"] if variant == "unused_external" else [])

    def test_unknown_and_duplicate_repair_anchor_rejected(self):
        for anchors in (["unregistered"], ["a", "a"]):
            with self.assertRaises(r.EvidenceError): r.descendant_closure(self.graph(), anchors)

    def test_no4_known_set_has_four_original_and_two_new(self):
        self.assertEqual(len(set(r.NO4_ORIGINAL + r.NO4_NEW)), 6)
        self.assertTrue(all("s3_al0.50" not in name for name in r.NO4_NEW))
        self.assertEqual(r.GATES[-1]["allowed_now"], "NOT_ADMITTED")


class MetadataIOWitnesses(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.reader = r.Reader()
        self.canonical = patch.dict(r.CANONICAL_ROOTS, {"AT": str(self.root / "campaign")})
        self.canonical.start()

    def tearDown(self):
        self.canonical.stop()
        self.tmp.cleanup()

    def pin(self, path, value):
        raw = r.json_bytes(value); path.write_bytes(raw)
        return dict(path=str(path), sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw), value=value)

    def test_source_pin_and_parsed_value_are_both_checked(self):
        pin = self.pin(self.root / "source.json", {"flag": False})
        self.assertEqual(self.reader.read(pin), {"flag": False})
        pin["value"] = {"flag": True}
        with self.assertRaisesRegex(r.EvidenceError, "parsed metadata"):
            self.reader.read(pin)
        pin["sha256"] = "0" * 64
        with self.assertRaisesRegex(r.EvidenceError, "SHA256"):
            self.reader.read(pin)

    def test_symlink_fifo_and_binary_payload_denied(self):
        pin = self.pin(self.root / "source.json", {})
        link = self.root / "link.json"; link.symlink_to(self.root / "source.json")
        with self.assertRaises(r.EvidenceError): self.reader.read(dict(pin, path=str(link)))
        fifo = self.root / "fifo.json"; os.mkfifo(fifo)
        with self.assertRaisesRegex(r.EvidenceError, "regular file"):
            self.reader.read(dict(pin, path=str(fifo)))
        binary = self.root / "posterior.rds"; binary.write_bytes(b"private")
        with self.assertRaisesRegex(r.EvidenceError, "payloads"):
            self.reader.read(dict(path=str(binary), sha256=hashlib.sha256(b"private").hexdigest()), parsed=False)

    def test_duplicate_nonfinite_and_oversized_json_denied(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":1e999}', b' ' * (r.MAX_JSON_BYTES + 1)):
            with self.assertRaises(r.EvidenceError): r.decode_json(raw)

    def catalogue(self):
        root = self.root / "campaign"; (root / "tasks").mkdir(parents=True)
        task = dict(name="a", region="AT", kind="stats", depends=[])
        pin = self.pin(root / "tasks/a.json", task)
        listing = dict(directory=str(root / "tasks"), directory_exists=True, no_symlink=True,
                       count=1, rows=r._listing(root / "tasks"))
        return dict(root=str(root), registered_tasks_complete=True, listing_stable=True,
                    listing_before=copy.deepcopy(listing), listing_after=copy.deepcopy(listing), tasks={"a": pin})

    def test_complete_catalogue_rebound_and_changed_membership_rejected(self):
        capture = self.catalogue()
        self.assertEqual(set(r.bind_catalogue("AT", capture, self.reader)[0]), {"a"})
        self.pin(Path(capture["root"]) / "tasks/b.json", dict(name="b", region="AT"))
        with self.assertRaisesRegex(r.EvidenceError, "catalogue changed"):
            r.bind_catalogue("AT", capture, self.reader)

    def test_omitted_task_and_stale_listing_rejected(self):
        capture = self.catalogue(); capture["tasks"] = {}
        with self.assertRaisesRegex(r.EvidenceError, "omitted/extra"):
            r.bind_catalogue("AT", capture, self.reader)

    def test_wrong_campaign_path_and_task_alias_rejected(self):
        capture = self.catalogue(); capture["tasks"]["a"]["path"] = str(self.root / "other.json")
        with self.assertRaisesRegex(r.EvidenceError, "outside declared"):
            r.bind_catalogue("AT", capture, self.reader)

    def test_create_only_atomic_packet_and_no_replacement(self):
        output = self.root / "receipt"
        pin = r.write_new_packet(output, dict(status="PREPARED_NOT_ADMITTED"))
        self.assertEqual(self.reader.read(pin), dict(status="PREPARED_NOT_ADMITTED"))
        self.assertFalse((output / ".REPAIR_READINESS.pending").exists())
        with self.assertRaises(FileExistsError): r.write_new_packet(output, {})


class NativeSourceWitnesses(unittest.TestCase):
    def native(self, directory):
        bindings = [dict(path=str(Path(directory) / ("guard" + str(i) + ".py")), sha256="pin") for i in range(8)]
        freeze = dict(worktree=directory, source_bindings=bindings, native_proof_pin={"path": "proof"},
                      status="FROZEN_PENDING_ROOT_REVIEW_NEW_COMMIT_AND_PUBLICATION")
        records = dict(freeze=freeze,
            proof=dict(returncode=0, CPU_accounting_complete=True, drained=True,
                       optimizer_invocations=0, real_target_inputs=False, numerical_parity_proved=False,
                       source_file_pins={b["path"]: b["sha256"] for b in bindings[:4]},
                       scientific_filter_kernel_attestation=dict(flags="TSYNC", kernel_return=0),
                       postbootstrap_TSYNC_scientific_fork_denial=True,
                       all_newborns_kernel_traced_before_execution=True,
                       tracer_death_kernel_EXITKILL_enabled=True),
            config=dict(caps=dict(AL=300, Normal=2000), production_runtime_compatible=False,
                        production_pilot_admitted=False, global_contract={"path": "permit"}),
            permit=dict(expires_epoch=10, evidence=dict(resource_policy={"path": "policy"})),
            policy=dict(expires_epoch=10),
            failed=dict(status="FAILED_COST_RETAINED_NO_RETRY", old_costs_refunded=False,
                        error="historical unknown peer", whole_process_CPU_seconds=1))
        reader = types.SimpleNamespace(check=lambda: None, read=lambda pin, **kw: records.get(pin["path"], b"source"))
        spec = dict(worktree=directory, expected_head=r.NATIVE_HEAD, source_freeze={"path": "freeze"},
                    conditional_config={"path": "config"}, last_failed_toy={"path": "failed"})
        return spec, reader, records

    @staticmethod
    def git_result(command, **kw):
        return types.SimpleNamespace(stdout=(r.NATIVE_HEAD if "rev-parse" in command else "").encode())

    def test_current_clean_head_supersedes_dated_pending_label(self):
        with tempfile.TemporaryDirectory() as directory:
            spec, reader, records = self.native(directory)
            with patch.object(r.subprocess, "run", self.git_result):
                audit = r.audit_native(spec, reader, 20)
            self.assertEqual(audit["current_local_head"], r.NATIVE_HEAD)
            self.assertTrue(audit["old_global_permit"]["expired_at_audit"])
            self.assertTrue(audit["new_distinct_authority_required"])
            self.assertFalse(audit["numerical_parity_proved"])
            self.assertNotEqual(audit["remote_publication"], "UNPUBLISHED")
            self.assertEqual(records["permit"]["expires_epoch"], 10)

    def test_dirty_native_source_cannot_use_old_metadata_proof(self):
        with tempfile.TemporaryDirectory() as directory:
            spec, reader, _ = self.native(directory)
            def dirty(command, **kw):
                result = self.git_result(command)
                if "status" in command: result.stdout = b" M guard.py"
                return result
            with patch.object(r.subprocess, "run", dirty), self.assertRaisesRegex(r.EvidenceError, "dirty"):
                r.audit_native(spec, reader, 20)


class RemoteCaptureWitnesses(unittest.TestCase):
    def remote(self):
        spec = {key: dict(path=key + (".py" if key == "collector_source" else ".json"), sha256="pin")
                for key in ("collector_source", "snapshot", "run_receipt", "scope")}
        spec["collector_source"]["sha256"] = r.LEAN_NO3_COLLECTOR_SHA256
        values = {
            "collector_source.py": b"reviewed source",
            "snapshot.json": dict(capture_kind="SOURCE_BOUND_REMOTE_COLLECTOR_SNAPSHOT_NOT_LOCAL_READBACK",
                regions={"NO_3": {}}, mutations=0, numerical_payloads_read=0, observed_epoch=15., CPU_seconds=1., wall_seconds=1.),
            "run_receipt.json": dict(returncode=0, source_sha256=r.LEAN_NO3_COLLECTOR_SHA256, payloads_or_new_science=0, completed_epoch=16.),
            "scope.json": dict(source=spec["collector_source"], max_SSH=1, remote_CPU_hard=20, models_payloads_or_mutations=0,
                allpriorfailurescostsandclocksretained=True, issued_epoch=10., expires_epoch=20.)}
        reader = types.SimpleNamespace(read=lambda pin, **kw: values[pin["path"]], check=lambda: None, receipts={})
        return spec, values, reader

    def test_source_bound_remote_capture_is_never_local_readback(self):
        spec, _, reader = self.remote()
        capture, remote = r.bind_remote_no3(spec, reader)
        binding = dict(path="/remote/source.json", sha256="1" * 64, bytes=12, value={"flag": False})
        self.assertEqual(remote.read(binding), {"flag": False})
        self.assertIn("NOT_LOCAL_READBACK", reader.receipts[binding["path"]]["verification_mode"])
        self.assertEqual(capture["observed_epoch"], 15.)

    def test_failed_transport_wrong_source_or_reopened_capture_rejected(self):
        for mode in ("transport", "source", "clock", "payload"):
            spec, values, reader = self.remote()
            if mode == "transport": values["run_receipt.json"]["returncode"] = 255
            if mode == "source": spec["collector_source"]["sha256"] = "wrong"
            if mode == "clock": values["scope.json"]["expires_epoch"] = 14.
            if mode == "payload": values["snapshot.json"]["numerical_payloads_read"] = 1
            with self.subTest(mode=mode), self.assertRaises(r.EvidenceError): r.bind_remote_no3(spec, reader)


class ExternalLineageWitnesses(unittest.TestCase):
    def fixture(self, directory, certified=True):
        base = Path(directory); f = base / "fallback"
        one = base / "pricefm_stage_r141_recovery_rollout_20261019__AT"
        zero = base / "pricefm_stage_r140_frozen_all_region_rollout_20261018__AT"
        name = "AT_r134_7a422c0c3473f81f"
        def write(path, value):
            path.parent.mkdir(parents=True, exist_ok=True); raw = r.json_bytes(value); path.write_bytes(raw)
            return dict(path=str(path), sha256=hashlib.sha256(raw).hexdigest())
        task = dict(name=name, kind="ridge", region="AT", candidate_id="candidate", specification_sha256="spec")
        result = dict(candidate_id="candidate", region="AT", records=[dict(certified=True, driver="deterministic_Normal_location_broad_proxy")] * 3)
        spec = dict(ridge_task=write(one / "tasks" / (name + ".json"), task), ridge_result=write(one / "tasks_done" / name / "result.json", result))
        seal = dict(metadata=dict(certified=certified, source_head="oldhead", task_sha256=spec["ridge_task"]["sha256"]),
                    artifacts={"result.json": spec["ridge_result"]["sha256"]})
        spec["ridge_seal"] = write(one / "tasks_done" / name / "completed_evidence.json", seal)
        for role, value in (("task", task), ("result", result), ("seal", seal)):
            suffix = "tasks/" + name + ".json" if role == "task" else "tasks_done/" + name + "/" + ("completed_evidence.json" if role == "seal" else "result.json")
            spec["r140_ridge_" + role] = write(zero / suffix, value)
        imported = {name: dict(kind="ridge", source=str(zero / "tasks_done" / name),
                    task_sha256=spec["ridge_task"]["sha256"], completed_evidence_sha256=spec["ridge_seal"]["sha256"])}
        tasks, imports, consumers = {}, [], []
        for split in (1, 2, 3):
            child = "stats_" + name + "_s" + str(split)
            declaration = dict(name=child, kind="stats", depends=[name], specification_sha256="spec")
            task_pin = write(f / "tasks" / (child + ".json"), declaration); tasks[child] = declaration
            value = dict(metadata=dict(certified=True, task_sha256=task_pin["sha256"]))
            local = write(f / "tasks_done" / child / "completed_evidence.json", value)
            source = write(one / "tasks_done" / child / "completed_evidence.json", value)
            imported[child] = dict(task_sha256=task_pin["sha256"])
            imports.append(dict(name=child, source=str(one / "tasks_done" / child), destination=str(f / "tasks_done" / child),
                                source_evidence_sha256=local["sha256"], r141_import_record=imported[child]))
            consumers.append(dict(name=child, task=task_pin, seal=local, source_seal=source))
        origin = dict(status="R141_R140_PREREQUISITES_IMPORTED", region="AT", source_tag="pricefm_stage_r140_frozen_all_region_rollout_20261018",
                      source_head="oldhead", imported=imported)
        spec["r141_import"] = write(one / "recovery_import.json", origin)
        fallback = dict(status="R146_CERTIFIED_TRAIN_ONLY_PREREQUISITES_IMPORTED", test_opened=False,
                        al_fit_import_count=0, source_labels_preserved=True, imports=imports,
                        r141_recovery_import_sha256=spec["r141_import"]["sha256"])
        spec["r146_import"] = write(f / "prerequisite_import.json", fallback)
        spec["consumers"] = consumers
        return f, spec, tasks

    def test_certified_imported_ridge_binds_exact_three_stats_consumers(self):
        with tempfile.TemporaryDirectory() as directory:
            root, spec, tasks = self.fixture(directory)
            with patch.dict(r.CANONICAL_ROOTS, {"AT": str(root)}):
                result = r.bind_AT_external(spec, tasks, r.Reader())
            self.assertEqual(result["state"], "CERTIFIED_IMPORTED_UPSTREAM_RIDGE_LINEAGE_BOUND")
            self.assertFalse(result["global_future_graph_completeness_claimed"])
            self.assertEqual(len(result["consumers"]), 3)

    def test_uncertified_anchor_or_wrong_lineage_is_real_blocker(self):
        for mode in ("uncertified", "changed_spec", "wrong_source"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root, spec, tasks = self.fixture(directory, certified=mode != "uncertified")
                if mode == "changed_spec": next(iter(tasks.values()))["specification_sha256"] = "other"
                if mode == "wrong_source": spec["ridge_task"]["path"] += "wrong"
                with patch.dict(r.CANONICAL_ROOTS, {"AT": str(root)}), self.assertRaises(r.EvidenceError):
                    r.bind_AT_external(spec, tasks, r.Reader())


if __name__ == "__main__":
    unittest.main()
