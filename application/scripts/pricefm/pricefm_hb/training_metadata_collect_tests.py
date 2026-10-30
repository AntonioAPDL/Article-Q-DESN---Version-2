"""Owned synthetic JSON/wire failure tests; no network or real campaign reads."""
import base64
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import resource
import signal
import tempfile
import time
import unittest

SOURCE = Path(__file__).with_name("training_metadata_collect.py")
SPEC = importlib.util.spec_from_file_location("tested_training_metadata_collect", SOURCE)
c = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(c)
BOOTSTRAP = Path(__file__).with_name("training_metadata_collect_bootstrap.py")
BOOTSTRAP_SPEC = importlib.util.spec_from_file_location("tested_training_collection_bootstrap", BOOTSTRAP)
b = importlib.util.module_from_spec(BOOTSTRAP_SPEC)
BOOTSTRAP_SPEC.loader.exec_module(b)

class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm_json_collection_")
        self.root = Path(self.temp.name) / "owned" / "fixtures"
        self.root.mkdir(parents=True)
        self.plan = {"schema": c.SCHEMA, "status": "ROOT_AUTHORIZED_PRICEFM_ONLY_JEREZ_COLLECTION",
                     "collection_id": "jerez-training-" + "a" * 32, "expires_epoch": time.time() + 300,
                     "data_root": c.DATA, "maximum_files": 5120, "maximum_source_JSON_bytes": 2097152,
                     "maximum_payload_bytes": 67108864, "maximum_encoded_pack_bytes": 100663296,
                     "maximum_compressed_bytes": 8388608, "collector_source_sha256": "b" * 64,
                     "local_transport_CPU": 6, "remote_CPU": 6, "local_transport_wall": 120, "remote_wall": 120,
                     "regions": [{"region": name, "root": c.DATA + "/campaigns/fixture__" + name,
                                  "preparation": c.DATA + "/launch_prep/fixture__" + name + "/preparation.json",
                                  "expected_source_head": "c" * 40} for name in sorted(c.REGIONS)],
                     "SI_scaler_supplements": [{"task_name": "iq_SI_fixture" + str(i) + "_design",
                        "original_path": c.DATA + "/campaigns/pricefm_stage_r141_recovery_rollout_20261019__SI/tasks_done/iq_SI_fixture" + str(i) + "_design/design/scaler.json",
                        "sha256": c.sha(b"{}")} for i in range(6)]}
        files = []
        refs = []
        for row in self.plan["SI_scaler_supplements"]:
            relative = "tasks_done/" + row["task_name"] + "/design/scaler.json"
            alias = "SI/" + relative
            files.append({"id": alias, "region": "SI", "relative": relative, "role": "BYTE_EXACT_ORIGINAL_JSON",
                          "original": {"path": row["original_path"], "sha256": row["sha256"], "fingerprint": [1, 2, 2, 3, 4, 384]},
                          "bytes": 2, "sha256": c.sha(b"{}"), "base64": base64.b64encode(b"{}").decode()})
            refs.append({"task_name": row["task_name"], "scaler": {"id": alias, "sha256": c.sha(b"{}")}})
        self.packet = {"schema": c.SCHEMA, "collection_id": self.plan["collection_id"],
                       "plan_sha256": c.sha(c.encoded(self.plan)), "collector_source_sha256": "b" * 64,
                       "source_self_verified_by_bootstrap": True,
                       "source_binding_method": "SHA256_OF_ACTUAL_TRANSMITTED_SOURCE_BEFORE_EXEC",
                       "regions": [{"region": name, "scores": [], "designs": []} for name in sorted(c.REGIONS)],
                       "SI_scaler_supplements": refs, "files": files, "payload_bytes": 12}

    def tearDown(self):
        self.temp.cleanup()

    def test_Python36_compatible_source_syntax_surface(self):
        import ast
        ast.parse(SOURCE.read_text(), feature_version=(3, 6))
        ast.parse(BOOTSTRAP.read_text(), feature_version=(3, 6))

    def test_exact_inventory_and_shape_plan(self):
        self.assertIs(c.validate_plan(self.plan), self.plan)

    def test_unknown_region_rejected(self):
        self.plan["regions"][0]["region"] = "ZZ"
        with self.assertRaises(ValueError):
            c.validate_plan(self.plan)

    def test_root_authorization_and_complete_window_required(self):
        for key, value in (("status", "TOPOLOGY_PREPARED"), ("expires_epoch", time.time() + 2)):
            plan = copy.deepcopy(self.plan)
            plan[key] = value
            with self.assertRaises(ValueError):
                c.validate_plan(plan)

    def test_metadata_shape_bound_cannot_be_raised(self):
        self.plan["maximum_files"] += 1
        with self.assertRaises(ValueError):
            c.validate_plan(self.plan)

    def test_wire_roundtrip_and_SI_original_pins(self):
        packet, files = c.unpack_wire(c.wire(self.packet, self.plan), self.plan)
        self.assertEqual(packet["payload_bytes"], 12)
        self.assertEqual(len(files), 6)

    def test_foreign_packet_identity_rejected(self):
        envelope = c.wire(self.packet, self.plan)
        envelope["collection_id"] = "jerez-training-" + "d" * 32
        with self.assertRaises(ValueError):
            c.unpack_wire(envelope, self.plan)

    def test_wire_compressed_hash_drift_rejected(self):
        envelope = c.wire(self.packet, self.plan)
        envelope["compressed_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            c.unpack_wire(envelope, self.plan)

    def test_wire_expanded_count_drift_rejected(self):
        envelope = c.wire(self.packet, self.plan)
        envelope["uncompressed_bytes"] += 1
        with self.assertRaises(ValueError):
            c.unpack_wire(envelope, self.plan)

    def test_payload_hash_drift_rejected(self):
        self.packet["files"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_duplicate_received_alias_rejected(self):
        self.packet["files"].append(self.packet["files"][0])
        self.packet["payload_bytes"] += 2
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_received_path_escape_rejected(self):
        self.packet["files"][0]["id"] = "../escape.json"
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_missing_SI_supplement_rejected(self):
        self.packet["SI_scaler_supplements"].pop()
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_foreign_SI_original_rejected(self):
        self.packet["files"][0]["original"]["path"] = c.DATA + "/another.json"
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_SI_reference_crosswire_rejected(self):
        self.packet["SI_scaler_supplements"][0]["scaler"] = self.packet["SI_scaler_supplements"][1]["scaler"]
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_owned_cache_materialization_is_create_only_and_exact(self):
        target = self.root / "cache"
        result = c.cache_materialize(target, {"BE/metadata.json": b"{}"})
        self.assertEqual(result["BE/metadata.json"]["sha256"], c.sha(b"{}"))
        with self.assertRaises(ValueError):
            c.cache_materialize(target, {"BE/metadata.json": b"{}"})

    def test_mixed_test_flags_and_types_rejected(self):
        for value in (True, 0):
            with self.assertRaises(ValueError):
                c.no_test({"test_opened": value})

    def test_duplicate_or_nonfinite_JSON_rejected(self):
        for value in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":1e999}', '{"x":-1e999}'):
            with self.assertRaises(ValueError):
                c.loads(value)

    def test_source_hash_echo_is_not_bootstrap_verification(self):
        self.packet["source_self_verified_by_bootstrap"] = False
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

    def test_actual_transmitted_source_hash_verified_before_exec(self):
        raw = b"raise RuntimeError('must not be executed by verification test')"
        digest = hashlib.sha256(raw).hexdigest()
        encoded_source = base64.b64encode(raw).decode()
        encoded_plan = base64.b64encode(json.dumps({"collector_source_sha256": digest}).encode()).decode()
        self.assertEqual(b.verified_payload(encoded_source, digest, encoded_plan), raw)
        with self.assertRaises(ValueError):
            b.verified_payload(base64.b64encode(raw + b"changed").decode(), digest, encoded_plan)

    def test_bootstrap_rejects_plan_source_crosswire_and_overflow(self):
        raw = b"pass"
        digest = hashlib.sha256(raw).hexdigest()
        encoded_source = base64.b64encode(raw).decode()
        for plan in ('{"collector_source_sha256":"' + "0" * 64 + '"}',
                     '{"collector_source_sha256":"' + digest + '","x":1e999}'):
            with self.assertRaises(ValueError):
                b.verified_payload(encoded_source, digest, base64.b64encode(plan.encode()).decode())

    def test_typed_actual_guard_bounds_and_flags(self):
        guard = {"returncode": 0, "command_returncode": 0, "CPU_limit": 6,
                 "aggregate_CPU_seconds": 0.5, "complete_lifecycle_wall_seconds": 2.0,
                 "independent_guardian": True, "all_owned_descendants_reaped": True,
                 "kernel_escape_filter": True, "cap_reason": None, "guardian_forced_monitor_stop": False}
        self.assertIs(c.validate_guard(guard, self.plan), guard)
        bad = [("returncode", False), ("command_returncode", False), ("CPU_limit", 6.0),
               ("aggregate_CPU_seconds", False), ("aggregate_CPU_seconds", -1),
               ("aggregate_CPU_seconds", 6), ("aggregate_CPU_seconds", float("nan")),
               ("complete_lifecycle_wall_seconds", False), ("complete_lifecycle_wall_seconds", -1),
               ("complete_lifecycle_wall_seconds", 121), ("complete_lifecycle_wall_seconds", float("inf")),
               ("independent_guardian", False), ("all_owned_descendants_reaped", 1),
               ("kernel_escape_filter", 1), ("cap_reason", "LIMIT"), ("guardian_forced_monitor_stop", True)]
        for field, value in bad:
            invalid = copy.deepcopy(guard)
            invalid[field] = value
            with self.assertRaises(ValueError, msg=str((field, value))):
                c.validate_guard(invalid, self.plan)

    def test_missing_guard_fields_or_mismatched_plan_cap_rejected(self):
        guard = {"returncode": 0, "command_returncode": 0, "CPU_limit": 6,
                 "aggregate_CPU_seconds": 0.5, "complete_lifecycle_wall_seconds": 2.0,
                 "independent_guardian": True, "all_owned_descendants_reaped": True,
                 "kernel_escape_filter": True, "cap_reason": None, "guardian_forced_monitor_stop": False}
        for field in ("cap_reason", "independent_guardian", "guardian_forced_monitor_stop"):
            invalid = copy.deepcopy(guard)
            del invalid[field]
            with self.assertRaises(ValueError):
                c.validate_guard(invalid, self.plan)
        self.plan["local_transport_CPU"] = 4
        with self.assertRaises(ValueError):
            c.validate_guard(guard, self.plan)

    def test_owned_regular_JSON_and_hardlink_boundary(self):
        path = self.root / "metadata.json"
        path.write_text("{}")
        self.assertEqual(c.read_json(path, 10, self.root)[1], {})
        os.link(path, self.root / "hardlink.json")
        with self.assertRaises(ValueError):
            c.read_json(path, 10, self.root)

    def test_symlink_and_source_byte_cap_rejected(self):
        path = self.root / "metadata.json"
        path.write_text('{"x":1}')
        symlink = self.root / "link.json"
        symlink.symlink_to(path)
        with self.assertRaises(ValueError):
            c.read_json(symlink, 100, self.root)
        with self.assertRaises(ValueError):
            c.read_json(path, 2, self.root)

    def test_snapshot_drift_before_publication_rejected(self):
        path = self.root / "metadata.json"
        path.write_text("{}")
        collector = c.Collector(self.plan)
        collector.original(path, self.root)
        path.write_text('{"changed":true}')
        with self.assertRaises(ValueError):
            collector.snapshot_stable()

    def test_context_projection_is_explicit_not_original_bytes(self):
        path = self.root / "preparation.json"
        path.write_text('{"source":{},"references":{"official_test_AQL":123}}')
        collector = c.Collector(self.plan)
        projection = {"source": {}, "metadata_role": "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY"}
        ref = collector.add("BE", "training_context.json", path, self.root,
                            role="DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY", projection=projection)
        row = collector.files[ref["id"]]
        self.assertNotEqual(row["sha256"], row["original"]["sha256"])
        self.assertNotIn("official_test_AQL", base64.b64decode(row["base64"]).decode())

    def test_illegal_context_extra_fields_rejected_locally(self):
        original = {"path": self.plan["regions"][0]["preparation"], "sha256": "0" * 64, "fingerprint": [1, 2, 3, 4, 5, 384]}
        value = {"source": {"head": "c" * 40}, "source_sha256": {}, "input_sha256": {}, "bank_sha256": {},
                 "test_used_for_selection": False, "official_development_test_seen_previously": True,
                 "metadata_role": "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY", "original_preparation": original,
                 "excluded_sections": [], "references": {"official_test_AQL": 123}}
        payload = c.encoded(value)
        self.packet["files"].append({"id": "BE/training_context.json", "region": "BE", "relative": "training_context.json",
            "role": "DERIVED_TRAINING_CONTEXT_NOT_ORIGINAL_BYTE_COPY", "original": original, "bytes": len(payload),
            "sha256": c.sha(payload), "base64": base64.b64encode(payload).decode()})
        self.packet["payload_bytes"] += len(payload)
        with self.assertRaises(ValueError):
            c.unpack_wire(c.wire(self.packet, self.plan), self.plan)

if __name__ == "__main__":
    resource.setrlimit(resource.RLIMIT_CPU, (3, 3))
    signal.alarm(45)
    if os.sched_getaffinity(0) != set((31,)):
        raise SystemExit("administrativeCPU31 required")
    stream = io.StringIO()
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CollectionTests))
    print(stream.getvalue())
    print(json.dumps({"status": "PASS" if result.wasSuccessful() else "FAIL", "tests": result.testsRun,
                      "failures": len(result.failures), "errors": len(result.errors),
                      "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
                      "network_models_campaign_reads": 0}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
