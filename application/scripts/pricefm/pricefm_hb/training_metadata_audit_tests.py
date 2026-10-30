"""Adversarial saved-training-evidence tests; creates only private JSON fixtures."""
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

SOURCE = Path(__file__).with_name("training_metadata_audit.py")
SPEC = importlib.util.spec_from_file_location("tested_training_metadata_audit", SOURCE)
a = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(a)
HEAD = "b" * 40
SHA = "a" * 64

class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pricefm_training_audit_")
        self.owned = Path(self.temp.name) / "owned"
        self.root = self.owned / "evidence"
        self.root.mkdir(parents=True)
        self.inputs = a.Inputs([self.root])
        self.sequence = 0

    def tearDown(self):
        self.temp.cleanup()

    def doc(self, value, name=None):
        self.sequence += 1
        path = self.root / (name or ("%04d.json" % self.sequence))
        path.write_text(json.dumps(value, sort_keys=True) + "\n")
        return a.pin(path)

    def cert(self, *, failed=False, formal=False, finite=True):
        measures = {k: limit * 0.1 for k, limit in a.LIMITS.items()}
        if failed:
            measures["beta_posterior_sd_rms"] = a.LIMITS["beta_posterior_sd_rms"] * 2
        checks = {k: measures[k] <= limit for k, limit in a.LIMITS.items()}
        certificate = {"certified": not failed, "limits": dict(a.LIMITS), "measures": measures,
                       "checks": checks, "rhs_reconstruction": {"unit_converged": True, "dispersed_converged": True}}
        terminal = {"family": "al", "initialization_only": True, "iterations": 300,
                    "finite_core": finite, "formal_converged": formal,
                    "independent_fixedpoint_certified": not failed,
                    "computationally_certified": finite and (formal or not failed),
                    "test_opened": False}
        return certificate, terminal

    def score(self, split=1, tau0=0.1, AQL=2.0, head=HEAD):
        candidate = "r134_" + SHA[:16]
        task = {"kind": "internal_score", "region": "SI", "candidate_id": candidate,
                "tau0": tau0, "split": split, "specification_sha256": SHA,
                "spec": {"region": "SI", "readout": "pure_all_layers",
                         "feature_policy": "target_only", "calendar": "none"}, "al_names": {}}
        companions = []
        for tau in a.QUANTILES:
            name = "internal_q" + str(tau)
            task["al_names"][str(tau)] = name
            al = dict(task, kind="internal_al", tau=tau, name=name)
            alp = self.doc(al)
            cert, terminal = self.cert()
            terminal.update(tau=tau, tau0=tau0, fold=split)
            cp, tp = self.doc(cert), self.doc(terminal)
            seal = self.doc({"artifacts": {"fit/fixedpoint_certificate.json": cp["sha256"], "fit/terminal.json": tp["sha256"]},
                             "metadata": {"task_sha256": alp["sha256"], "source_head": head}})
            companions.append(dict(task=alp, certificate=cp, terminal=tp, seal=seal))
        taskpin = self.doc(task)
        result = {"candidate_id": candidate, "tau0": tau0, "split": split, "certified": True,
                  "AQL": AQL, "coverage_80": 0.75, "width_80": 3.0, "origin_clock_pairs": 48,
                  "clock_metrics": [{"exceedance": [0.9, 0.75, 0.55, 0.5, 0.45, 0.25, 0.1]}]}
        resultpin = self.doc(result)
        seal = self.doc({"artifacts": {"result.json": resultpin["sha256"]},
                         "metadata": {"task_sha256": taskpin["sha256"], "source_head": head, "certified": True}})
        return dict(task=taskpin, result=resultpin, seal=seal, certificates=companions)

    def config(self):
        authority = self.doc({"status": "PROSPECTIVE_PRICEFM_CONTINUATION_IMPLEMENTATION_SCOPE",
                              "expires_epoch": time.time() + 300, "allowed_metadata_output_root": str(self.owned)})
        inventory = self.doc({"schema": "pricefm_stdlib_metadata_census_v1", "records": [
            {"region": region, "host": "jerez"} for region in sorted(a.CANONICAL_REGIONS)]})
        rows, old = [], []
        for i in range(8):
            name = "NO4_failed_" + str(i)
            split, quantile = ((1, 0.5), (2, 0.5), (3, 0.45), (3, 0.55))[i % 4]
            task = {"name": name, "region": "NO_4", "kind": "internal_al", "tau": quantile,
                    "tau0": 0.01 if i < 4 else 0.1, "split": split, "candidate_id": "candidate"}
            cert, terminal = self.cert(failed=True)
            terminal.update(tau=quantile, tau0=task["tau0"], fold=task["split"])
            taskp, cp, tp = self.doc(task), self.doc(cert), self.doc(terminal)
            sp = self.doc({"artifacts": {"fit/fixedpoint_certificate.json": cp["sha256"], "fit/terminal.json": tp["sha256"]},
                           "metadata": {"task_sha256": taskp["sha256"], "source_head": HEAD}})
            rows.append(dict(task=taskp, certificate=cp, terminal=tp, seal=sp))
            old.append(dict(task=name, certificate=cp, terminal=tp))
        frozen = self.doc({"status": "COMPLETE_READONLY_HELD_AND_ACTIVE_FRONTIER_DIAGNOSIS",
                          "NO4_RHS_precision_exclusions_preserved_count": 144, "NO4_required_failed_targets": old})
        return {"schema": a.SCHEMA, "source": {"path": str(SOURCE.absolute()), "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest()},
                "expires_epoch": time.time() + 200, "authority": authority, "inventory": inventory,
                "output_root": str(self.root), "allowed_roots": [str(self.root)],
                "regions": [{"region": region, "host": "jerez", "availability": "REMOTE_NOT_OBSERVED"} for region in sorted(a.CANONICAL_REGIONS)],
                "NO4": {"frozen_diagnosis": frozen, "required_failures": rows, "RHS_precision_exclusion_count": 144}}

    def test_original_independent_and_finite_rule(self):
        cert, terminal = self.cert()
        self.assertTrue(a.validate_certificate(cert, terminal)["accepted_original_rule"])
        terminal["finite_core"] = False
        terminal["computationally_certified"] = False
        self.assertFalse(a.validate_certificate(cert, terminal)["accepted_original_rule"])

    def test_formal_or_independent_not_formal_and_independent(self):
        cert, terminal = self.cert(failed=True, formal=True)
        self.assertTrue(a.validate_certificate(cert, terminal)["accepted_original_rule"])
        self.assertFalse(a.validate_certificate(cert, terminal)["independent"])

    def test_wrong_original_limit_rejected(self):
        cert, terminal = self.cert()
        cert["limits"]["elbo_relative"] *= 2
        with self.assertRaises(a.AuditError):
            a.validate_certificate(cert, terminal)

    def test_missing_original_measure_rejected(self):
        cert, terminal = self.cert()
        del cert["measures"]["sigma_relative"]
        with self.assertRaises(a.AuditError):
            a.validate_certificate(cert, terminal)

    def test_false_certificate_flag_rejected(self):
        cert, terminal = self.cert(failed=True)
        cert["certified"] = True
        with self.assertRaises(a.AuditError):
            a.validate_certificate(cert, terminal)

    def test_missing_RHS_start_cannot_be_pass(self):
        cert, terminal = self.cert()
        cert["rhs_reconstruction"]["unit_converged"] = False
        with self.assertRaises(a.AuditError):
            a.validate_certificate(cert, terminal)

    def test_nonfinite_or_boolean_scalar_rejected(self):
        for value in (float("nan"), float("inf"), True):
            cert, terminal = self.cert()
            cert["measures"]["sigma_relative"] = value
            with self.assertRaises(a.AuditError):
                a.validate_certificate(cert, terminal)

    def test_duplicate_JSON_keys_rejected(self):
        with self.assertRaises(a.AuditError):
            a.loads('{"certified":true,"certified":false}')

    def test_nonfinite_JSON_literal_rejected(self):
        with self.assertRaises(a.AuditError):
            a.loads('{"AQL":NaN}')

    def test_source_pin_drift_rejected_before_audit(self):
        config = self.config()
        config["source"]["sha256"] = "0" * 64
        with self.assertRaises(a.AuditError):
            a.audit(config)

    def test_input_pin_drift_is_fatal_integrity_error(self):
        value = self.doc({"x": 1})
        Path(value["path"]).write_text('{"x":2}')
        with self.assertRaises(a.IntegrityError):
            self.inputs.read(value)

    def test_path_escape_and_logical_Jerez_identity_rejected(self):
        outside = self.owned / "elsewhere.json"
        outside.write_text("{}")
        with self.assertRaises(a.IntegrityError):
            self.inputs.read(a.pin(outside))

    def test_symlink_and_hardlink_inputs_rejected(self):
        original = Path(self.doc({})["path"])
        sym = self.root / "symlink.json"
        sym.symlink_to(original)
        with self.assertRaises(a.AuditError):
            a.pin(sym)
        hard = self.root / "hardlink.json"
        os.link(original, hard)
        with self.assertRaises(a.AuditError):
            a.pin(hard)

    def test_official_task_cannot_be_declared_training(self):
        row = self.score()
        task = a.loads(Path(row["task"]["path"]).read_bytes())
        task["kind"] = "forecast"
        row["task"] = self.doc(task)
        with self.assertRaises(a.AuditError):
            a.score_row(self.inputs, "SI", row, HEAD)

    def test_official_test_flag_and_boolean_confusion_rejected(self):
        for flag in (True, 0):
            task = {"test_opened": flag}
            with self.assertRaises(a.AuditError):
                a.no_test_flags(task)

    def test_foreign_source_head_rejected(self):
        row = self.score(head="c" * 40)
        with self.assertRaises(a.AuditError):
            a.score_row(self.inputs, "SI", row, HEAD)

    def test_valid_score_proves_seven_companions(self):
        row = a.score_row(self.inputs, "SI", self.score(), HEAD)
        self.assertTrue(row["eligible_original_rule"])
        self.assertTrue(row["all_both_RHS_starts"])
        self.assertEqual(row["AQL"], 2)

    def test_duplicate_quantile_companion_rejected(self):
        row = self.score()
        row["certificates"][-1] = row["certificates"][0]
        with self.assertRaises(a.AuditError):
            a.score_row(self.inputs, "SI", row, HEAD)

    def test_task_result_crosswire_rejected(self):
        row = self.score()
        result = a.loads(Path(row["result"]["path"]).read_bytes())
        result["split"] = 2
        row["result"] = self.doc(result)
        with self.assertRaises(a.AuditError):
            a.score_row(self.inputs, "SI", row, HEAD)

    def test_duplicate_split_rejected(self):
        row = a.score_row(self.inputs, "SI", self.score(), HEAD)
        with self.assertRaises(a.AuditError):
            a.reproduce_selection([row, row], None)

    def test_missing_split_ineligible(self):
        rows = [a.score_row(self.inputs, "SI", self.score(split=i), HEAD) for i in (1, 2)]
        output = a.reproduce_selection(rows, None)
        self.assertEqual(output["ranking"], [])
        self.assertEqual(len(output["excluded"]), 1)

    def test_equal_three_split_existing_selection(self):
        actual = [(0.00024929739307713865, (6.91847371042695, 5.37465215758361, 9.517834218291563)),
                  (0.000024929739307713866, (6.896847612863941, 5.38351661366175, 9.560145007525913))]
        rows = [a.score_row(self.inputs, "SI", self.score(split=i, tau0=tau, AQL=value), HEAD)
                for tau, scores in actual for i, value in enumerate(scores, 1)]
        frozen = {"candidate_id": "r134_" + SHA[:16], "tau0": actual[0][0], "selected_before_test": True,
                  "selected_on": "fold1_train_internal_only_seven_quantile_AL_AQL",
                  "ranking": [{"candidate_id": "r134_" + SHA[:16], "tau0": actual[0][0], "mean_AQL": 7.270320028767375}]}
        result = a.reproduce_selection(rows, frozen)
        self.assertTrue(result["frozen_winner_reproduced"])
        self.assertFalse(result["winner_mutated"])

    def test_wrong_saved_winner_cannot_be_replaced(self):
        rows = [a.score_row(self.inputs, "SI", self.score(split=i), HEAD) for i in (1, 2, 3)]
        frozen = {"candidate_id": "wrong", "tau0": 0.1, "selected_before_test": True,
                  "selected_on": "fold1_train_internal_only_seven_quantile_AL_AQL"}
        with self.assertRaises(a.AuditError):
            a.reproduce_selection(rows, frozen)

    def test_canonical_38_inventory_enforced(self):
        config = self.config()
        config["regions"][0]["region"] = "ZZ"
        with self.assertRaises(a.AuditError):
            a.audit(config)

    def test_wrong_parent_authority_rejected(self):
        config = self.config()
        config["authority"] = self.doc({"expires_epoch": time.time() + 300})
        with self.assertRaises(a.AuditError):
            a.audit(config)

    def test_output_root_bound_to_actual_parent(self):
        config = self.config()
        config["output_root"] = str(Path(self.temp.name) / "outside")
        with self.assertRaises(a.AuditError):
            a.audit(config)

    def test_NO4_failures_and_exclusions_remain_separate(self):
        config = self.config()
        result = a.audit(config)
        self.assertEqual(len(result["regions"]), 38)
        self.assertEqual(result["NO4"]["required_failed_count"], 8)
        self.assertEqual(result["NO4"]["RHS_precision_exclusions_preserved_separately"], 144)
        self.assertEqual(result["NO4"]["reruns_authorized"], 0)
        self.assertFalse(any(x["accepted_original_rule"] for x in result["NO4"]["required_failures"]))

    def test_NO4_foreign_failed_set_rejected(self):
        config = self.config()
        config["NO4"]["required_failures"] = config["NO4"]["required_failures"][:-1]
        with self.assertRaises(a.AuditError):
            a.audit(config)

    def test_NO4_exclusion_claim_bound_to_frozen_diagnosis(self):
        config = self.config()
        config["NO4"]["RHS_precision_exclusion_count"] = 143
        with self.assertRaises(a.AuditError):
            a.audit(config)

if __name__ == "__main__":
    resource.setrlimit(resource.RLIMIT_CPU, (12, 12))
    signal.alarm(90)
    if os.sched_getaffinity(0) != {31}:
        raise SystemExit("administrativeCPU31 required")
    stream = io.StringIO()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AuditTests)
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    print(stream.getvalue())
    print(json.dumps({"status": "PASS" if result.wasSuccessful() else "FAIL", "tests": result.testsRun,
                      "failures": len(result.failures), "errors": len(result.errors),
                      "self_CPU_seconds": sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
                      "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                      "fixture_scope": "owned synthetic JSON only; no models/arrays/network/jobs"}))
    raise SystemExit(0 if result.wasSuccessful() else 1)
