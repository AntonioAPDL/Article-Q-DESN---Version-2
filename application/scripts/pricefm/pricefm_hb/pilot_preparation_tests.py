"""Adversarial metadata and real CLI tests; no scientific values are evaluated."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

import pilot_preparation as p


def controller():
    return dict(commit="2" * 40, branch="work/pricefm-future-pilot",
                files={"application/scripts/pricefm/pricefm_hb/future_owner.py": "3" * 64})


def bridge():
    return dict(
        schema="r190_eventual_bridge_binding_metadata_v1", accepted_job_id="999001",
        scientific_source=dict(kind="UNCHANGED_MATH_FUTURE_REVIEWED_BRIDGE",
                               head="1" * 40, branch="work/pricefm-future-bridge"),
        scientific_files=copy.deepcopy(p.SCIENCE_HASHES), stock_body_sha256=p.STOCK_BODY_SHA,
        original_manifest_sha256=p.ORIGINAL_MANIFEST_SHA, target=p.TARGET,
        posterior_target_sha256="4" * 64, units=p.CASE["units"],
        prior=copy.deepcopy(p.CASE["prior"]),
        data_references={k: dict(path="/old/input/" + k + ".bin",
                                 sha256=p.DELIVERY_HASHES["design/" + k + ".bin"],
                                 bytes=p.DELIVERY_BYTES["design/" + k + ".bin"]) for k in ("X", "y")},
        original_failed_bindings=[dict(path="/original/fit/terminal.json", sha256="5" * 64)],
        proof_pins={k: dict(path="/future/accepted/" + k + ".json", sha256="6" * 64)
                    for k in p.BRIDGE_PROOF_NAMES},
        acceptance_chain_independently_verified=False,
    )


def aliases(b=None):
    b = bridge() if b is None else b
    return {k: dict(logical_path=b["data_references"][k]["path"],
                    physical_path="/new/input/" + k + ".bin",
                    sha256=b["data_references"][k]["sha256"],
                    bytes=b["data_references"][k]["bytes"]) for k in ("X", "y")}


def inventory(count=300):
    names = set(p.PILOT_CORE) | set(p.PILOT_PROOFS)
    for number in range(1, count + 1):
        names |= p.checkpoint_names(number)
    return [dict(relative=name, sha256="7" * 64,
                 bytes=3_000_000 if name.endswith(".rds") else 1000)
            for name in sorted(names)]


def envelope():
    return dict(remote_file_bytes=16 * 1024**2, remote_total_bytes=2 * 1024**3,
                next_write_reserve_bytes=16 * 1024**2,
                reserved_filesystem_bytes=3 * 1024**3,
                main_file_bytes=16 * 1024**2, main_total_bytes=64 * 1024**2)


class PreparationTests(unittest.TestCase):
    def test_unbound_preparation_is_useful_but_never_admitted(self):
        value = p.prepare(controller())
        self.assertFalse(value["pilot_launch_ready"])
        self.assertFalse(value["authorizes_optimizer"])
        self.assertIsNone(value["eventual_bridge_binding"])
        self.assertIsNone(value["compute_import_verification_interface"])
        self.assertEqual(value["case"]["max_iter"], 300)
        self.assertEqual(value["case"]["maximum_pilot_attempts"], 1)
        self.assertEqual(value["case"]["limits"], p.LIMITS)

    def test_actual_eventual_scientific_object_stays_separate(self):
        b = bridge()
        snapshot = copy.deepcopy(b)
        value = p.prepare(controller(), b, aliases(b))
        self.assertNotEqual(value["controller_source"]["commit"],
                            value["eventual_bridge_binding"]["scientific_source"]["head"])
        self.assertEqual(value["eventual_bridge_binding"], snapshot)
        self.assertEqual(b, snapshot)
        self.assertFalse(value["pilot_launch_ready"])
        value["case"]["prior"]["sigma_a"] = 2
        self.assertEqual(p.CASE["prior"]["sigma_a"], 1)

    def test_historical_bridge_head_is_not_forced_or_relabelled(self):
        b = bridge()
        b["scientific_source"]["head"] = "a" * 40
        value = p.prepare(controller(), b, aliases(b))
        self.assertEqual(value["eventual_bridge_binding"]["scientific_source"]["head"], "a" * 40)

    def test_missing_or_extra_acceptance_chain_member_rejected(self):
        for action in ("missing", "extra"):
            b = bridge()
            if action == "missing":
                del b["proof_pins"]["outer_accept_guard"]
            else:
                b["proof_pins"]["fabricated"] = dict(path="/extra.json", sha256="1" * 64)
            with self.assertRaises(ValueError):
                p.validate_bridge_binding(b)

    def test_metadata_cannot_claim_accepted_proof(self):
        b = bridge()
        b["acceptance_chain_independently_verified"] = True
        with self.assertRaises(ValueError):
            p.validate_bridge_binding(b)

    def test_science_source_hash_tamper_rejected(self):
        b = bridge()
        b["scientific_files"][next(iter(p.SCIENCE_HASHES))] = "0" * 64
        with self.assertRaises(ValueError):
            p.validate_bridge_binding(b)

    def test_target_units_stock_manifest_and_prior_tampering_rejected(self):
        for key, value in [
            ("target", "AT"), ("units", "standardized"),
            ("stock_body_sha256", "0" * 64), ("original_manifest_sha256", "0" * 64),
        ]:
            b = bridge()
            b[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.validate_bridge_binding(b)
        for key, val in [("sigma_a", True), ("freeze_tau_iters", False),
                         ("shrink_intercept", 0), ("center", "initializer")]:
            b = bridge()
            b["prior"][key] = val
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.validate_bridge_binding(b)

    def test_controller_closure_cannot_add_external_or_unsafe_files(self):
        for name in ("../owner.py", "/owner.py", "docs/owner.py", "application/./owner.py"):
            c = controller()
            c["files"] = {name: "3" * 64}
            with self.subTest(name=name), self.assertRaises(ValueError):
                p.controller_source(c)

    def test_source_identity_closure_and_commit_validity(self):
        for head in (True, "HEAD", "1" * 39, "G" * 40):
            b = bridge()
            b["scientific_source"]["head"] = head
            with self.subTest(head=head), self.assertRaises(ValueError):
                p.validate_bridge_binding(b)
        b = bridge()
        b["scientific_source"]["unknown"] = True
        with self.assertRaises(ValueError):
            p.validate_bridge_binding(b)

    def test_data_references_reject_hash_size_and_same_alias(self):
        for key, value in [("sha256", "0" * 64), ("bytes", True), ("bytes", 1)]:
            b = bridge()
            b["data_references"]["X"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                p.validate_bridge_binding(b)
        b = bridge()
        b["data_references"]["y"]["path"] = b["data_references"]["X"]["path"]
        with self.assertRaises(ValueError):
            p.validate_bridge_binding(b)

    def test_relocation_is_closed_one_to_one_and_byte_equivalent(self):
        b = bridge()
        for key, value in [("logical_path", "/wrong/X.bin"),
                           ("physical_path", "/new/../X.bin"),
                           ("sha256", "0" * 64), ("bytes", True)]:
            a = aliases(b)
            a["X"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.relocation_aliases(b, a)
        a = aliases(b)
        a["X"]["physical_path"] = a["y"]["physical_path"]
        with self.assertRaises(ValueError):
            p.relocation_aliases(b, a)
        a = aliases(b)
        a["other"] = copy.deepcopy(a["X"])
        with self.assertRaises(ValueError):
            p.relocation_aliases(b, a)

    def test_same_path_alias_allowed_without_mutation(self):
        b = bridge()
        a = aliases(b)
        for name in a:
            a[name]["physical_path"] = a[name]["logical_path"]
        self.assertEqual(p.relocation_aliases(b, a), a)

    def test_import_interface_keeps_real_compute_gates_pending(self):
        interface = p.import_verification_interface(bridge(), aliases())
        self.assertEqual(interface["exact_required_checks"], list(p.IMPORT_CHECKS))
        self.assertTrue(interface["runtime_implementation_and_proof_pending"])
        self.assertFalse(interface["byte_or_RDS_values_verified"])
        self.assertFalse(interface["grants_import_or_optimizer_authority"])
        self.assertIn("AFTER_NATIVE_TSYNC_AND_PARENT_ACK", interface["execution_location"])
        self.assertEqual(interface["position"], "BEFORE_FROZEN_FACTOR_IMPORT_AND_OPTIMIZER")

    def test_alias_without_bridge_or_bridge_without_alias_rejected(self):
        with self.assertRaises(ValueError):
            p.prepare(controller(), aliases=aliases())
        with self.assertRaises(ValueError):
            p.prepare(controller(), bridge=bridge())


class RetentionTests(unittest.TestCase):
    def test_all300_retained_with_three_count_only_selected(self):
        value = p.retention_plan(inventory(), 300, envelope())
        self.assertEqual(value["selected_checkpoint_sweeps"], [1, 150, 300])
        self.assertEqual(len(value["remote_retained"]), 613)
        self.assertEqual(len(value["main_return"]), 19)
        self.assertTrue(value["original_checkpoint_index_returned"])
        self.assertFalse(value["actual_RDS_sizes_or_storage_price_measured"])
        self.assertFalse(value["grants_execution_or_retention_authority"])

    def test_selection_all_counts_has_no_outcome_input(self):
        for count in range(1, 301):
            selected = p.selected_checkpoints(count)
            self.assertEqual(selected, sorted({1, (count + 1) // 2, count}))
            self.assertTrue(all(1 <= i <= count for i in selected))

    def test_small_counts_remove_duplicate_selected_checkpoints(self):
        for count, selected in [(1, [1]), (2, [1, 2]), (3, [1, 2, 3])]:
            value = p.retention_plan(inventory(count), count, envelope())
            self.assertEqual(value["selected_checkpoint_sweeps"], selected)

    def test_missing_middle_duplicate_extra_or_missing_proof_rejected(self):
        source = inventory()
        cases = [
            source[:-1],
            source + [copy.deepcopy(source[0])],
            source + [dict(relative="official_test_loss.json", sha256="8" * 64, bytes=12)],
            [r for r in source if r["relative"] != "checkpoints/sweep_0150/full_state.rds"],
            [r for r in source if r["relative"] != "proof/COMPUTE_IMPORT_PROVENANCE.json"],
        ]
        for rows in cases:
            with self.subTest(count=len(rows)), self.assertRaises(ValueError):
                p.retention_plan(rows, 300, envelope())

    def test_boolean_nonfinite_negative_and_oversized_lengths_rejected(self):
        for size in (True, -1, 0, 17 * 1024**2, float("nan"), float("inf")):
            rows = inventory(1)
            rows[0]["bytes"] = size
            with self.subTest(size=size), self.assertRaises(ValueError):
                p.retention_plan(rows, 1, envelope())

    def test_count_caps_and_boolean_counts_rejected(self):
        for count in (True, 0, 301, 1.0):
            with self.subTest(count=count), self.assertRaises(ValueError):
                p.selected_checkpoints(count)

    def test_remote_total_and_prewrite_reserve_enforced(self):
        for key, value in [
            ("remote_total_bytes", 1000), ("next_write_reserve_bytes", 1),
            ("reserved_filesystem_bytes", 2 * 1024**3),
        ]:
            e = envelope()
            e[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.retention_plan(inventory(), 300, e)

    def test_useful_return_cannot_raise_immutable_caps(self):
        for key, value in [
            ("main_total_bytes", p.MAX_RETURN_TOTAL + 1),
            ("main_file_bytes", p.MAX_RETURN_FILE + 1),
            ("main_total_bytes", 1000), ("main_file_bytes", 1000),
        ]:
            e = envelope()
            e[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.retention_plan(inventory(1), 1, e)

    def test_no_outcome_field_or_unsafe_relative_path(self):
        for key, value in [("score", 1.0), ("relative", "../final_state.rds"),
                           ("relative", "/final_state.rds")]:
            rows = inventory(1)
            rows[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                p.retention_plan(rows, 1, envelope())

    def test_inputs_not_mutated(self):
        rows = inventory(3)
        before = copy.deepcopy(rows)
        e = envelope()
        p.retention_plan(rows, 3, e)
        self.assertEqual(rows, before)
        self.assertEqual(e, envelope())


class MetadataIOTests(unittest.TestCase):
    def test_actual_isolated_cli_invocation(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "input.json"
            output = Path(folder) / "output.json"
            source.write_text(json.dumps(dict(controller=controller(), bridge=None,
                                              aliases=None, retention=None)))
            command = [sys.executable, "-I", "-B", str(Path(p.__file__).resolve()),
                       "--input", str(source), "--output", str(output)]
            actual = subprocess.run(command, capture_output=True, text=True, timeout=10,
                                    env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
            self.assertEqual(actual.returncode, 0, actual.stderr)
            self.assertFalse(json.loads(output.read_text())["pilot_launch_ready"])
            self.assertFalse(json.loads(actual.stdout)["pilot_launch_ready"])

    def test_binary_extension_rejected_before_any_open(self):
        with patch.object(p.os, "open", side_effect=AssertionError("must not open")) as opened:
            with self.assertRaises(ValueError):
                p.read_metadata_json("/tmp/scientific.rds")
            opened.assert_not_called()

    def test_json_duplicate_nonfinite_and_hardlink_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / "input.json"
            for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}'):
                file.write_text(raw)
                with self.subTest(raw=raw), self.assertRaises(ValueError):
                    p.read_metadata_json(str(file))
            file.write_text("{}")
            link = Path(folder) / "hardlink.json"
            os.link(file, link)
            with self.assertRaises(ValueError):
                p.read_metadata_json(str(file))

    def test_symlink_and_large_metadata_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / "input.json"
            file.write_text("{}")
            link = Path(folder) / "symlink.json"
            link.symlink_to(file)
            with self.assertRaises(ValueError):
                p.read_metadata_json(str(link))
            link.unlink()
            file.write_bytes(b" " * (4 * 1024**2 + 1))
            with self.assertRaises(ValueError):
                p.read_metadata_json(str(file))

    def test_actual_cli_writes_only_unadmitted_package_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "input.json"
            output = root / "output.json"
            source.write_text(json.dumps(dict(controller=controller(), bridge=None,
                                              aliases=None, retention=None)))
            argv = ["pilot_preparation.py", "--input", str(source), "--output", str(output)]
            with patch("sys.argv", argv), contextlib.redirect_stdout(io.StringIO()):
                p.main()
            result = json.loads(output.read_text())
            self.assertEqual(result["status"], "PREPARED_METADATA_CONTRACTS_PILOT_UNADMITTED")
            self.assertFalse(result["pilot_launch_ready"])
            old = output.read_bytes()
            with patch("sys.argv", argv), self.assertRaises(FileExistsError):
                p.main()
            self.assertEqual(output.read_bytes(), old)


if __name__ == "__main__":
    unittest.main()

