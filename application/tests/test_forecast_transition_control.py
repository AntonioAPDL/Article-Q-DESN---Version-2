#!/usr/bin/env python3.11
"""Temporary SQLite/files and mock submission only; never SSH, Slurm or model work."""

from __future__ import annotations

import contextlib
import copy
import csv
import datetime as dt
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("forecast_transition_control",
    ROOT / "application/scripts/forecast_transition_control.py")
control = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(control)
GIB = 1024 ** 3
NOW = dt.datetime(2030, 1, 1, tzinfo=dt.timezone.utc)
EXPIRES = "2031-01-01T00:00:00Z"
HASH = "a" * 64
COMMIT = "b" * 40
TREE = "c" * 40
ARGV = ["/mock/Rscript", "/mock/source/worker.R", "--mode", "run", "--request", "/mock/request.json",
        "--authorization", "/mock/auth.json", "--authorization-sha256", HASH,
        "--claim-ticket", "/mock/ticket.json", "--claim-ticket-sha256", HASH,
        "--ledger", "/mock/ledger.sqlite", "--source-manifest", "/mock/source.csv"]


def task(task_id="task-1", prerequisites=None):
    keys = ["draw1/origin1/h1/p050", "draw1/origin1/h2/p050"]
    result = {"schema_version": "forecast_transition_task_v1", "task_id": task_id,
            "routing_id": "route-" + task_id, "routing_revision": 1,
            "source_commit": COMMIT, "source_tree": TREE,
            "source_manifest_sha256": HASH, "posterior_target_sha256": HASH,
            "input_manifest_sha256": HASH, "task_manifest_sha256": HASH,
            "rng_namespace": "scientific-source/model/chain1/draw1/origin1",
            "workflow": "integrated_quantile_forecast", "expected_output_keys": keys,
            "expected_output_keys_sha256": control.object_sha256(sorted(keys)),
            "dispatch_argv_sha256": control.argv_spec_sha256(ARGV),
            "prerequisites": prerequisites or []}
    result["request_spec_sha256"] = control.request_spec_sha256(request_for(result))
    return result


def request_for(spec):
    return {"schema_version": "integrated_quantile_forecast_request_v1",
            **{name: spec[name] for name in control.IDENTITY_FIELDS},
            "host": "muscat", "routing_id": spec["routing_id"], "authorization_sha256": HASH,
            "draw_ids": ["chain1/draw1"], "origin_ids": ["origin1"], "inner_paths": 4,
            "probabilities": [0.5], "resource_budget": {"max_threads": 1,
                "max_memory_mb": 1024, "max_wall_seconds": 10, "max_output_bytes": 1024 ** 2}}


def configuration():
    config = control.read_json(ROOT / "application/config/forecast_transition_multihost_v1.json")
    config["launch_authorized"] = True
    config["production_budget"] = {"max_submissions": 10, "max_cpu_seconds": 10000,
                                   "max_wall_seconds": 1000, "max_output_bytes": GIB,
                                   "max_metadata_bytes": 64 * 1024 ** 2}
    for host, site in config["hosts"].items():
        site["qualified"] = False
        site["qualification_receipt_sha256"] = None
        site["core_grants"] = ["test-new-scope-" + host]
        site["python_bin"] = "/usr/bin/python3.11"
        site["rscript"] = "/mock/Rscript"
        if "ssh_profile" in site:
            site["ssh_profile"].update(identity_file=None, known_hosts_file=None, known_hosts_sha256=None)
    return config


def resource(host="muscat"):
    result = {"host": host, "expires_utc": EXPIRES, "available_memory_bytes": 500 * GIB,
              "free_disk_bytes": 500 * GIB, "measured_peak_worker_rss_bytes": GIB,
              "cpu_topology": [{"cpu": cpu, "socket": 0, "core": cpu % 32} for cpu in range(64)],
              "reserved_logical_cpus": []}
    if host == "hummingbird":
        result.update(compute_node_runtime_proof=True, cpu_boundary_proof=True,
                      closed_accounting_receipt=True, account_cpu_limit=72, qos_cpu_limit=92,
                      partition_cpu_limit=96, group_cpu_limit=72, other_allocated_cpus=0,
                      partition="128x24", account="testaccount", qos="normal",
                      wall_time_limit_seconds=3600, quota_verified=True)
    return result


def grant(host="muscat"):
    return {"host": host, "scope": "forecast_transition", "pricefm_grant": False,
            "grant_id": "test-new-scope-" + host, "expires_utc": EXPIRES,
            "logical_cpus": list(range(16)) + list(range(24, 30)),
            "max_workers": 72 if host == "hummingbird" else 8,
            "max_cpus": 72 if host == "hummingbird" else 8,
            "max_memory_bytes": 100 * GIB, "max_output_bytes": GIB,
            "max_artifact_bytes": GIB, "max_log_bytes": GIB, "max_metadata_bytes": 64 * 1024 ** 2}


def budget(cpu=0, cpus=1):
    return {"workers": 1, "cpus": cpus, "memory_bytes": GIB, "cpu_seconds": cpus * 10,
            "wall_seconds": 10, "output_bytes": 1024 ** 2, "log_bytes": 1024 ** 2,
            "metadata_bytes": 1024 ** 2, "total_output_bytes": 3 * 1024 ** 2, "logical_cpus": [cpu]}


def authority(config=None, task_ids=None):
    config = copy.deepcopy(config or configuration())
    auth = {"schema_version": "forecast_transition_authorization_v1", "allow_launch": True,
            "approved_by": "unit-test-only", "expires_utc": EXPIRES,
            "config_sha256": control.object_sha256(config), "source_commit": COMMIT,
            "source_tree": TREE, "source_manifest_sha256": HASH,
            "posterior_target_sha256": HASH, "input_manifest_sha256": HASH,
            "task_manifest_sha256": HASH, "allowed_task_ids": task_ids or ["task-1", "task-2", "task-3"],
            "allowed_task_sha256": {name: control.object_sha256(task(name)) for name in
                                    (task_ids or ["task-1", "task-2", "task-3"])},
            "allowed_hosts": ["muscat", "jerez", "hummingbird"],
            "allowed_operations": ["claim", "dispatch", "record_terminal", "accept", "reassign", "cancel",
                                   "abandon_preintent", "adopt_ambiguous"],
            "budget": copy.deepcopy(config["production_budget"]),
            "resource_receipt_sha256": {host: control.object_sha256(resource(host)) for host in config["hosts"]},
            "resource_grants": {grant(host)["grant_id"]: control.object_sha256(grant(host)) for host in config["hosts"]},
            "qualified_hosts": {host: {"source_commit": COMMIT,
                "source_manifest_sha256": HASH, "runtime_parity": True, "accuracy_pass": True,
                "compute_to_coordinator_verified": True,
                "runtime_receipt_sha256": HASH, "accuracy_receipt_sha256": HASH, "resource_receipt_sha256": HASH,
                "coordinator_connectivity_receipt_sha256": HASH,
                "cpu_boundary_receipt_sha256": HASH, "accounting_receipt_sha256": HASH,
                "output_root": "/tmp/forecast-transition-test-results",
                "metadata_root": "/tmp/forecast-transition-test-metadata",
                "python_bin": config["hosts"][host]["python_bin"], "rscript": config["hosts"][host]["rscript"],
                "numerical_backend": {"backend": "bundled_rblas", "library_path": "/mock/libRblas.so", "library_sha256": HASH},
                "expires_utc": EXPIRES} for host in config["hosts"]}}
    for receipt in auth["qualified_hosts"].values():
        receipt["receipt_sha256"] = control.object_sha256(receipt)
    return control.Authority(config, control.object_sha256(config), auth, HASH,
                             (COMMIT, TREE, True), now=lambda: NOW)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="forecast-transition-unit-")
        self.root = Path(self.temporary.name)
        self.auth = authority()
        for host, receipt in self.auth.authorization["qualified_hosts"].items():
            output = self.root / ("qualified-output-" + host); output.mkdir()
            receipt["output_root"] = str(output)
            metadata_root = self.root / ("qualified-meta-" + host); metadata_root.mkdir()
            receipt["metadata_root"] = str(metadata_root)
            receipt["receipt_sha256"] = control.object_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        self.ledger = control.Ledger(self.root / "ledger.sqlite", self.auth, coordinator_hostname="muscat")

    def tearDown(self):
        self.ledger.close()
        self.temporary.cleanup()

    def claim(self, spec=None, host="muscat", cpu=0):
        return self.ledger.claim(spec or task(), host, "test-owner", resource(host), grant(host), budget(cpu))

    def dispatch(self, ticket):
        self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV,
            [{"role": "supervision", "sha256": HASH}])
        return self.ledger.dispatch(ticket["claim_nonce"], lambda intent: {
            "host": ticket["host"], "claim_nonce": ticket["claim_nonce"], "job_id": "mock-job-" + ticket["task_id"]})

    def metadata(self, ticket, root, argv=ARGV):
        records = []
        for role in ("request", "claim_ticket", "authorization", "supervision"):
            path = self.root / (ticket["claim_nonce"] + "." + role + ".json")
            path.write_text(json.dumps(self.auth.authorization) if role == "authorization" else '{"unit":true}')
            records.append({"role": role, "local_path": str(path), "remote_path": str(Path(root) / path.name),
                            "sha256": control.file_sha256(path)})
        return records

    def finish(self, ticket, exit_code=0):
        self.ledger.terminal(ticket["claim_nonce"], {"host": ticket["host"],
            "claim_nonce": ticket["claim_nonce"], "job_id": "mock-job-" + ticket["task_id"],
            "exit_code": exit_code, "owner_terminated": True, "accounting_complete": True})

    def outputs(self, ticket, spec=None):
        spec = spec or task()
        out = Path(ticket["output_root"])
        out.mkdir(parents=True)
        shards = []
        for index, key in enumerate(spec["expected_output_keys"]):
            path = out / f"shard{index}.csv"
            path.write_text("score\n0.25\n", encoding="utf-8")
            shards.append({"key": key, "relative_path": path.name,
                "sha256": control.file_sha256(path), "bytes": path.stat().st_size,
                "posterior_target_sha256": spec["posterior_target_sha256"]})
        manifest = {"schema_version": "forecast_transition_output_v1", "claim_nonce": ticket["claim_nonce"],
                    "routing_id": ticket["routing_id"], "shards": shards, "numerical_gates_pass": True,
                    "expected_output_keys_sha256": spec["expected_output_keys_sha256"],
                    **{name: spec[name] for name in control.IDENTITY_FIELDS}}
        return manifest, out

    def ready_output(self):
        ticket = self.claim()
        self.dispatch(ticket)
        self.finish(ticket)
        manifest, out = self.outputs(ticket)
        return ticket, manifest, out

    def test_shipped_no_launch_and_readonly_plan(self):
        shipped = control.read_json(ROOT / "application/config/forecast_transition_multihost_v1.json")
        self.assertFalse(shipped["launch_authorized"])
        self.assertTrue(all(not value["qualified"] and not value["core_grants"] for value in shipped["hosts"].values()))
        self.assertTrue(all(value == 0 for value in shipped["production_budget"].values()))
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(control.main(["plan"]), 0)
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt["production_actions"], 0)
        self.assertFalse(receipt["ledger_created"])
        self.assertEqual(set(receipt["hosts"]), {"muscat", "jerez", "hummingbird"})
        with self.assertRaisesRegex(control.GateError, "NO_LAUNCH_NOW"):
            authority(shipped).check("claim", task(), "muscat")

    def test_one_coordinator_only(self):
        with self.assertRaisesRegex(control.GateError, "Muscat coordinator"):
            control.Ledger(self.root / "remote.sqlite", self.auth, coordinator_hostname="jerez")
        self.assertFalse((self.root / "remote.sqlite").exists())

    def test_one_owner_across_connections(self):
        self.claim()
        other = control.Ledger(self.root / "ledger.sqlite", self.auth, coordinator_hostname="muscat")
        try:
            with self.assertRaisesRegex(control.GateError, "active owner"):
                other.claim(task(), "jerez", "other", resource("jerez"), grant("jerez"), budget())
        finally:
            other.close()

    def test_task_identity_cannot_mutate(self):
        self.claim()
        altered = task(); altered["rng_namespace"] += "/changed"
        with self.assertRaisesRegex(control.GateError, "complete task record hash"):
            self.claim(altered)

    def test_host_readiness_is_incremental(self):
        self.auth.authorization["qualified_hosts"].pop("hummingbird")
        self.assertTrue(self.claim())
        with self.assertRaisesRegex(control.GateError, "qualification receipt"):
            self.ledger.claim(task("task-2"), "hummingbird", "owner", resource("hummingbird"), grant("hummingbird"), budget())

    def test_postcommit_qualification_has_no_source_hash_fixed_point(self):
        frozen_config_hash = control.object_sha256(self.auth.config)
        self.assertTrue(self.auth.config["launch_authorized"])
        self.assertTrue(all(not site["qualified"] and site["qualification_receipt_sha256"] is None
                            for site in self.auth.config["hosts"].values()))
        receipt = self.auth.authorization["qualified_hosts"]["muscat"]
        body = {key: value for key, value in receipt.items() if key != "receipt_sha256"}
        self.assertEqual(receipt["receipt_sha256"], control.object_sha256(body))
        self.assertEqual(body["source_commit"], COMMIT)
        self.auth.check("claim", task(), "muscat")
        self.assertEqual(frozen_config_hash, control.object_sha256(self.auth.config))
        receipt["runtime_parity"] = False
        receipt["receipt_sha256"] = control.object_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        with self.assertRaisesRegex(control.GateError, "qualification evidence"):
            self.auth.check("claim", task(), "muscat")

    def test_authority_mutations(self):
        cases = [("allow_launch", False), ("source_commit", "d" * 40),
                 ("source_tree", "d" * 40), ("source_manifest_sha256", "d" * 64),
                 ("posterior_target_sha256", "d" * 64), ("input_manifest_sha256", "d" * 64),
                 ("task_manifest_sha256", "d" * 64), ("config_sha256", "d" * 64),
                 ("expires_utc", "2020-01-01T00:00:00Z"), ("allowed_hosts", ["jerez"]),
                 ("allowed_task_ids", ["other"]), ("allowed_operations", [])]
        for name, value in cases:
            with self.subTest(field=name):
                candidate = authority(); candidate.authorization[name] = value
                with self.assertRaises(control.GateError):
                    candidate.check("claim", task(), "muscat")
        self.auth.source = (COMMIT, TREE, False)
        with self.assertRaisesRegex(control.GateError, "clean source"):
            self.claim()

    def test_stale_qualification_is_not_a_grant(self):
        self.auth.authorization["qualified_hosts"]["muscat"]["receipt_sha256"] = "d" * 64
        with self.assertRaisesRegex(control.GateError, "qualification"):
            self.claim()

    def test_old_pricefm_and_expired_grants_rejected(self):
        for change in ({"pricefm_grant": True}, {"scope": "pricefm"},
                       {"expires_utc": "2020-01-01T00:00:00Z"}, {"grant_id": "old-pricefm-grant"}):
            candidate = grant(); candidate.update(change)
            with self.subTest(change=change), self.assertRaises(control.GateError):
                self.ledger.claim(task(), "muscat", "owner", resource(), candidate, budget())

    def test_siblings_and_reserved_physical_cores_rejected(self):
        site = self.auth.config["hosts"]["muscat"]
        candidate = grant(); candidate["logical_cpus"] = list(range(64))
        for cpus in ([0, 32], [16], [48], [23], [55]):
            with self.subTest(cpus=cpus), self.assertRaises(control.GateError):
                control.physical_allocation(site, resource(), candidate, cpus)
        control.physical_allocation(site, resource(), candidate, [0, 1, 24])

    def test_resource_safety_gates(self):
        cases = [{"available_memory_bytes": 180 * GIB}, {"free_disk_bytes": 80 * GIB},
                 {"measured_peak_worker_rss_bytes": 2 * GIB}, {"cpu_topology": []},
                 {"expires_utc": "2020-01-01T00:00:00Z"}]
        for change in cases:
            candidate = resource(); candidate.update(change)
            with self.subTest(change=change), self.assertRaises(control.GateError):
                self.ledger.claim(task(), "muscat", "owner", candidate, grant(), budget())

    def test_aggregate_cpu_ownership(self):
        self.claim(task(), cpu=0)
        with self.assertRaisesRegex(control.GateError, "already claimed"):
            self.claim(task("task-2"), cpu=0)
        self.assertTrue(self.claim(task("task-2"), cpu=1))

    def test_active_different_tasks_cannot_take_sibling_core(self):
        released = grant(); released["logical_cpus"] = list(range(64))
        self.auth.authorization["resource_grants"][released["grant_id"]] = control.object_sha256(released)
        self.ledger.claim(task(), "muscat", "owner1", resource(), released, budget(0))
        with self.assertRaisesRegex(control.GateError, "SMT siblings"):
            self.ledger.claim(task("task-2"), "muscat", "owner2", resource(), released, budget(32))

    def test_active_ram_and_disk_reservations_are_aggregate(self):
        self.claim()
        memory = resource(); memory["available_memory_bytes"] = 181 * GIB + GIB // 2
        self.auth.authorization["resource_receipt_sha256"]["muscat"] = control.object_sha256(memory)
        with self.assertRaisesRegex(control.GateError, "aggregate active/ambiguous RAM"):
            self.ledger.claim(task("task-2"), "muscat", "owner", memory, grant(), budget(1))
        disk = resource(); disk["free_disk_bytes"] = 80 * GIB + 3 * 1024 ** 2
        self.auth.authorization["resource_receipt_sha256"]["muscat"] = control.object_sha256(disk)
        with self.assertRaisesRegex(control.GateError, "aggregate active/ambiguous output"):
            self.ledger.claim(task("task-2"), "muscat", "owner", disk, grant(), budget(1))

    def test_hummingbird_strictest_limit_and_cpu_proof(self):
        candidate = resource("hummingbird")
        current = budget(cpus=24)
        candidate["group_cpu_limit"] = 20
        with self.assertRaisesRegex(control.GateError, "strictest aggregate"):
            control.resource_admission(self.auth.config, "hummingbird", candidate, grant("hummingbird"), current, NOW)
        candidate = resource("hummingbird"); candidate["cpu_boundary_proof"] = False
        with self.assertRaisesRegex(control.GateError, "CPU/accounting"):
            control.resource_admission(self.auth.config, "hummingbird", candidate, grant("hummingbird"), current, NOW)
        candidate = resource("hummingbird"); candidate["other_allocated_cpus"] = 60
        with self.assertRaisesRegex(control.GateError, "strictest aggregate"):
            control.resource_admission(self.auth.config, "hummingbird", candidate, grant("hummingbird"), current, NOW)

    def test_slurm_aggregate_claims(self):
        for index in range(3):
            self.ledger.claim(task("task-" + str(index + 1)), "hummingbird", "owner",
                              resource("hummingbird"), grant("hummingbird"), budget(cpus=24))
        self.auth.authorization["allowed_task_ids"].append("task-4")
        self.auth.authorization["allowed_task_sha256"]["task-4"] = control.object_sha256(task("task-4"))
        with self.assertRaisesRegex(control.GateError, "CPU budget"):
            self.ledger.claim(task("task-4"), "hummingbird", "owner",
                              resource("hummingbird"), grant("hummingbird"), budget(cpus=1))

    def test_durable_intent_before_submission(self):
        ticket = self.claim()
        intent_path = self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)
        self.assertTrue(intent_path.is_file())
        calls = []
        def submit(intent):
            calls.append(intent)
            self.assertEqual(self.ledger.row(ticket["claim_nonce"])["state"], "submission_ambiguous")
            self.assertEqual(control.file_sha256(intent_path), self.ledger.row(ticket["claim_nonce"])["intent_sha"])
            return {"host": "muscat", "claim_nonce": ticket["claim_nonce"], "job_id": "mock"}
        with mock.patch.object(control.os, "fsync", wraps=control.os.fsync) as fsync:
            other = self.claim(task("task-2"), cpu=1)
            self.ledger.prepare_intent(other["claim_nonce"], self.root, ARGV)
            self.assertGreaterEqual(fsync.call_count, 2)
        self.ledger.dispatch(ticket["claim_nonce"], submit)
        self.assertEqual(len(calls), 1)

    def test_wrong_dispatch_argv_rejected(self):
        ticket = self.claim()
        with self.assertRaisesRegex(control.GateError, "dispatch argv"):
            self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ["arbitrary-command"])

    def test_intent_is_nonoverwriteable(self):
        ticket = self.claim()
        self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)
        with self.assertRaisesRegex(control.GateError, "exactly once"):
            self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)

    def test_intent_tamper_rejected_before_side_effect(self):
        ticket = self.claim()
        path = self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)
        path.write_text("{}")
        submit = mock.Mock()
        with self.assertRaisesRegex(control.GateError, "intent changed"):
            self.ledger.dispatch(ticket["claim_nonce"], submit)
        submit.assert_not_called()

    def test_budget_nonrefundable_after_ambiguous_submission(self):
        self.auth.config["production_budget"]["max_submissions"] = 1
        self.auth.config_sha256 = self.auth.authorization["config_sha256"] = control.object_sha256(self.auth.config)
        first = self.claim()
        self.ledger.prepare_intent(first["claim_nonce"], self.root, ARGV)
        with self.assertRaisesRegex(control.GateError, "SUBMISSION_AMBIGUOUS"):
            self.ledger.dispatch(first["claim_nonce"], mock.Mock(side_effect=TimeoutError("reply lost")))
        with self.assertRaisesRegex(control.GateError, "not retryable"):
            self.ledger.dispatch(first["claim_nonce"], mock.Mock())
        second = self.claim(task("task-2"), cpu=1)
        with self.assertRaisesRegex(control.GateError, "cumulative submissions"):
            self.ledger.prepare_intent(second["claim_nonce"], self.root, ARGV)

    def test_two_B_artifact_and_merged_log_charge_is_explicit(self):
        self.auth.config["production_budget"]["max_output_bytes"] = 3 * 1024 ** 2
        self.auth.authorization["budget"]["max_output_bytes"] = 3 * 1024 ** 2
        self.auth.config_sha256 = self.auth.authorization["config_sha256"] = control.object_sha256(self.auth.config)
        ticket = self.claim()
        path = self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)
        charge = control.read_json(path)["charge"]
        self.assertEqual(charge["artifact_bytes"], 1024 ** 2)
        self.assertEqual(charge["log_bytes"], 1024 ** 2)
        self.assertEqual(charge["output_bytes"], 2 * 1024 ** 2)
        second = self.claim(task("task-2"), cpu=1)
        with self.assertRaisesRegex(control.GateError, "cumulative output_bytes"):
            self.ledger.prepare_intent(second["claim_nonce"], self.root, ARGV)

    def test_explicit_reconciliation_and_fenced_reassignment(self):
        ticket = self.claim()
        self.ledger.prepare_intent(ticket["claim_nonce"], self.root, ARGV)
        with self.assertRaises(control.GateError):
            self.ledger.dispatch(ticket["claim_nonce"], mock.Mock(side_effect=TimeoutError()))
        receipt = {"claim_nonce": ticket["claim_nonce"], "host": ticket["host"], "owner_terminated": True,
                   "accounting_complete": True, "no_orphans": True, "evidence_sha256": HASH}
        bad = dict(receipt, owner_terminated=False)
        with self.assertRaisesRegex(control.GateError, "termination"):
            self.ledger.reconcile_reassign(ticket["claim_nonce"], bad, "new-route", "jerez", 2)
        self.ledger.reconcile_reassign(ticket["claim_nonce"], receipt, "new-route", "jerez", 2)
        replacement = self.claim(host="jerez")
        self.assertNotEqual(replacement["claim_nonce"], ticket["claim_nonce"])
        self.assertEqual(replacement["routing_id"], "new-route")
        events = [row[0] for row in self.ledger.db.execute("SELECT kind FROM events")]
        self.assertIn("submission_ambiguous", events)
        self.assertIn("reconciled_reassignment", events)
        with self.assertRaisesRegex(control.GateError, "successful terminal"):
            self.ledger.accept(ticket["claim_nonce"], {}, self.root)

    def test_failure_evidence_retained_and_no_automatic_retry(self):
        ticket = self.claim(); self.dispatch(ticket); self.finish(ticket, exit_code=2)
        with self.assertRaisesRegex(control.GateError, "reconciliation"):
            self.claim()
        self.assertEqual(self.ledger.row(ticket["claim_nonce"])["state"], "failed")
        receipt = json.loads(self.ledger.row(ticket["claim_nonce"])["terminal_receipt"])
        self.assertEqual(receipt["exit_code"], 2)

    def test_accept_exact_outputs_and_prevent_duplicate_acceptance(self):
        ticket, manifest, out = self.ready_output()
        self.assertEqual(self.ledger.accept(ticket["claim_nonce"], manifest, out), control.object_sha256(manifest))
        with self.assertRaisesRegex(control.GateError, "successful terminal"):
            self.ledger.accept(ticket["claim_nonce"], manifest, out)

    def test_output_manifest_mutations(self):
        ticket, manifest, out = self.ready_output()
        variants = []
        altered = copy.deepcopy(manifest); altered["shards"] = altered["shards"][:1]; variants.append(altered)
        altered = copy.deepcopy(manifest); altered["shards"].append(altered["shards"][0]); variants.append(altered)
        for name in (*control.IDENTITY_FIELDS, "routing_id", "claim_nonce", "expected_output_keys_sha256"):
            altered = copy.deepcopy(manifest); altered[name] = "unapproved"; variants.append(altered)
        altered = copy.deepcopy(manifest); altered["numerical_gates_pass"] = False; variants.append(altered)
        for name, value in (("posterior_target_sha256", "d" * 64), ("sha256", "d" * 64),
                            ("bytes", 1000), ("relative_path", "../outside")):
            altered = copy.deepcopy(manifest); altered["shards"][0][name] = value; variants.append(altered)
        for index, altered in enumerate(variants):
            with self.subTest(mutation=index), self.assertRaises(control.GateError):
                self.ledger.accept(ticket["claim_nonce"], altered, out)

    def test_unmanifested_outputs_and_symlinks_rejected(self):
        ticket, manifest, out = self.ready_output()
        extra = out / "unapproved.csv"; extra.write_text("test")
        with self.assertRaisesRegex(control.GateError, "artifact membership"):
            self.ledger.accept(ticket["claim_nonce"], manifest, out)
        extra.unlink()
        source = out / manifest["shards"][0]["relative_path"]
        backup = self.root / "backup.csv"; source.rename(backup); source.symlink_to(backup)
        with self.assertRaisesRegex(control.GateError, "symlink"):
            self.ledger.accept(ticket["claim_nonce"], manifest, out)

    def test_prerequisites_require_accepted_exact_targets(self):
        prerequisite = {"task_id": "task-1", "task_manifest_sha256": HASH, "posterior_target_sha256": HASH}
        next_task = task("task-2", [prerequisite])
        self.auth.authorization["allowed_task_sha256"]["task-2"] = control.object_sha256(next_task)
        with self.assertRaisesRegex(control.GateError, "missing exact prerequisite"):
            self.claim(next_task, cpu=1)
        ticket = self.claim()
        with self.assertRaisesRegex(control.GateError, "accepted output"):
            self.claim(next_task, cpu=1)
        self.dispatch(ticket); self.finish(ticket)
        manifest, out = self.outputs(ticket); self.ledger.accept(ticket["claim_nonce"], manifest, out)
        self.assertTrue(self.claim(next_task, cpu=1))

    def test_readonly_claim_verification_fences_fabrication(self):
        ticket = self.claim(); self.dispatch(ticket)
        request = request_for(task())
        request["output_root"] = ticket["output_root"]
        count = self.ledger.db.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        result = control.verify_claim_readonly(self.ledger.path, ticket, request, self.auth, coordinator_hostname="muscat")
        self.assertTrue(result["verified"])
        self.assertEqual(count, self.ledger.db.execute("SELECT COUNT(*) FROM events").fetchone()[0])
        for field in ("claim_nonce", "host", "task_sha256", "ticket_sha256"):
            altered = dict(ticket); altered[field] = "fabricated"
            with self.subTest(field=field), self.assertRaises(control.GateError):
                control.verify_claim_readonly(self.ledger.path, altered, request, self.auth, coordinator_hostname="muscat")
        for name, value in (("inner_paths", 10000), ("draw_ids", ["unauthorized-draw"]),
                            ("origin_ids", ["other-origin"]), ("probabilities", [0.1])):
            altered = copy.deepcopy(request); altered[name] = value
            with self.subTest(bound=name), self.assertRaisesRegex(control.GateError, "request/bounds"):
                control.verify_claim_readonly(self.ledger.path, ticket, altered, self.auth, coordinator_hostname="muscat")
        altered = copy.deepcopy(request); altered["resource_budget"]["max_wall_seconds"] = 10000
        with self.assertRaises(control.GateError):
            control.verify_claim_readonly(self.ledger.path, ticket, altered, self.auth, coordinator_hostname="muscat")
        self.finish(ticket)
        with self.assertRaisesRegex(control.GateError, "active central owner"):
            control.verify_claim_readonly(self.ledger.path, ticket, request, self.auth, coordinator_hostname="muscat")

    def test_ticket_fences_output_redirection(self):
        ticket = self.claim(); self.dispatch(ticket)
        request = request_for(task()); request["output_root"] = str(self.root / "unrelated-lane")
        with self.assertRaisesRegex(control.GateError, "output path differs"):
            control.verify_claim_readonly(self.ledger.path, ticket, request, self.auth, coordinator_hostname="muscat")
        self.finish(ticket)
        manifest, output = self.outputs(ticket)
        unrelated = self.root / "unrelated-lane"; unrelated.mkdir()
        with self.assertRaisesRegex(control.GateError, "ticket-bound"):
            self.ledger.accept(ticket["claim_nonce"], manifest, unrelated)
        self.assertEqual(self.ledger.accept(ticket["claim_nonce"], manifest, output), control.object_sha256(manifest))

    def test_slurm_render_is_batch_only(self):
        ticket = self.claim(host="hummingbird")
        script = control.slurm_script(task(), ticket, budget(cpus=2), resource("hummingbird"),
                                     "application/scripts/run_integrated_quantile_forecast.R", "/input/request.json",
                                     "/source", "/opt/R/4.6.0/bin/Rscript")
        self.assertIn("#SBATCH --cpus-per-task=2", script)
        self.assertIn("#SBATCH --time=00:00:10", script)
        self.assertLess(script.index("#SBATCH"), script.index("set -euo"))
        self.assertIn("exec srun --exclusive", script)
        self.assertIn("SLURM_JOB_ID", script)
        self.assertNotIn("python", script)
        self.assertNotIn("ssh", script)
        self.assertNotIn("sbatch ", script)

    def test_worker_commands_are_workflow_typed(self):
        config = self.auth.config
        ticket_path = self.root / "ticket.json"; ticket_path.write_text("{}")
        request = request_for(task())
        for workflow, expected in (("integrated_quantile_forecast", "run"),
                                   ("integrated_quantile_score", "score"), ("glofas_family_transition", None)):
            spec = task(); spec["workflow"] = workflow
            argv = control.worker_argv(config, "muscat", spec, request, self.root / "request.json", ticket_path,
                self.root / "auth.json", self.ledger.path, self.root / "source.csv", ROOT)
            self.assertEqual(argv[1], str(ROOT / config["worker_scripts"][workflow]))
            if expected:
                self.assertEqual(argv[argv.index("--mode") + 1], expected)
            else:
                self.assertNotIn("--mode", argv)

    def test_metadata_transfer_is_allowlisted_createonly_and_mocked(self):
        spec = task(); ticket = self.claim(host="jerez")
        nonce = ticket["claim_nonce"]
        self.auth.authorization["qualified_hosts"]["jerez"]["metadata_root"] = "/qualified/meta"
        receipt = self.auth.authorization["qualified_hosts"]["jerez"]
        receipt["receipt_sha256"] = control.object_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        metadata = []
        for role in ("request", "claim_ticket", "authorization", "supervision"):
            local = self.root / (role + ".json")
            local.write_text(json.dumps(self.auth.authorization) if role == "authorization" else '{"unit":true}\n')
            metadata.append({"role": role, "local_path": str(local),
                "remote_path": "/qualified/meta/" + nonce + "." + role + ".json", "sha256": control.file_sha256(local)})
        submit = control.qualified_submitter("jerez", ARGV, Path("/qualified/source"), budget(), resource("jerez"),
            Path("/qualified/meta"), spec, ticket, self.auth.config, self.auth, metadata)
        with mock.patch.object(control.subprocess, "run", side_effect=[mock.Mock(stdout=""), mock.Mock(stdout="12345 abc-0123 99\n")]) as run:
            self.assertTrue(submit({"argv": ARGV, "ticket": ticket, "metadata": metadata})["job_id"])
        self.assertEqual(run.call_count, 2)
        script = run.call_args_list[0].kwargs["input"]
        self.assertIn("set -o noclobber", script)
        self.assertIn("sha256sum", script)
        self.assertNotIn("scp", script)
        altered = copy.deepcopy(metadata); altered[0]["remote_path"] = "/home/.ssh/secret"
        submit = control.qualified_submitter("jerez", ARGV, Path("/qualified/source"), budget(), resource("jerez"),
            Path("/qualified/meta"), spec, ticket, self.auth.config, self.auth, altered)
        with mock.patch.object(control.subprocess, "run") as run, self.assertRaises(control.GateError):
            submit({"argv": ARGV, "ticket": ticket, "metadata": altered})
        run.assert_not_called()

    def test_real_local_adapter_is_bounded_and_mocked(self):
        spec = task(); ticket = self.claim()
        metadata = self.metadata(ticket, self.root)
        submit = control.qualified_submitter("muscat", ARGV, self.root, budget(), resource(),
            self.root, spec, ticket, self.auth.config, self.auth, metadata)
        process = mock.Mock(pid=12345)
        identity = {"host": "muscat", "pid": 12345, "boot_id": "unit-boot", "start_ticks": 99}
        with mock.patch.object(control.subprocess, "Popen", return_value=process) as popen, \
             mock.patch.object(control, "process_identity", return_value=identity):
            result = submit({"argv": ARGV, "ticket": ticket, "metadata": metadata})
        self.assertEqual(result["job_id"], "pid:12345:unit-boot:99")
        argv = popen.call_args.args[0]
        self.assertEqual(argv[0], "/usr/bin/python3.11")
        self.assertEqual(argv[2], "supervise")
        self.assertIn("--ticket", argv); self.assertIn("--ticket-sha256", argv)
        self.assertNotIn("--claim-ticket", argv)
        self.assertTrue(popen.call_args.kwargs["start_new_session"])
        self.assertEqual(popen.call_args.kwargs["env"]["OPENBLAS_NUM_THREADS"], "1")
        self.assertTrue(callable(popen.call_args.kwargs["preexec_fn"]))
        with mock.patch.object(control.os, "sched_setaffinity"), \
             mock.patch.object(control.posix_resource, "setrlimit") as limits:
            popen.call_args.kwargs["preexec_fn"]()
        self.assertIn(mock.call(control.posix_resource.RLIMIT_FSIZE, (65536, 1024 ** 2)), limits.call_args_list)

    def test_real_jerez_adapter_is_ssh_shell_only_and_mocked(self):
        spec = task(); ticket = self.claim(host="jerez")
        metadata = self.metadata(ticket, "/qualified/logs")
        submit = control.qualified_submitter("jerez", ARGV, Path("/qualified/source"), budget(), resource("jerez"),
            Path("/qualified/logs"), spec, ticket, self.auth.config, self.auth, metadata)
        self.auth.authorization["qualified_hosts"]["jerez"]["metadata_root"] = "/qualified/logs"
        receipt = self.auth.authorization["qualified_hosts"]["jerez"]
        receipt["receipt_sha256"] = control.object_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        answer = mock.Mock(stdout="12345 abcdef-0123 99\n")
        with mock.patch.object(control.subprocess, "run", return_value=answer) as run:
            result = submit({"argv": ARGV, "ticket": ticket, "metadata": metadata})
        self.assertEqual(result["job_id"], "pid:12345:abcdef-0123:99")
        self.assertEqual(run.call_args.args[0][-2:], ["jaguir26@jerez.be.ucsc.edu", "bash -s"])
        script = run.call_args.kwargs["input"]
        self.assertIn("ulimit -v", script)
        self.assertIn("ulimit -t", script)
        self.assertIn("ulimit -f 1024", script)
        self.assertIn("ulimit -S -f 64", script)
        self.assertIn("/usr/bin/taskset --cpu-list 0", script)
        self.assertIn(COMMIT, script)
        self.assertIn(TREE, script)

    def test_real_hummingbird_adapter_submits_batch_only_mocked(self):
        spec = task(); ticket = self.claim(host="hummingbird")
        root = Path("/qualified/source")
        script_path = str(root / self.auth.config["worker_scripts"][spec["workflow"]])
        argv = list(ARGV); argv[0] = "/qualified/Rscript"; argv[1] = script_path
        metadata = self.metadata(ticket, "/qualified/logs", argv)
        self.auth.authorization["qualified_hosts"]["hummingbird"]["metadata_root"] = "/qualified/logs"
        receipt = self.auth.authorization["qualified_hosts"]["hummingbird"]
        receipt["receipt_sha256"] = control.object_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        submit = control.qualified_submitter("hummingbird", argv, root, budget(), resource("hummingbird"),
            Path("/qualified/logs"), spec, ticket, self.auth.config, self.auth, metadata)
        with mock.patch.object(control.subprocess, "run", return_value=mock.Mock(stdout="123456;unitcluster\n")) as run:
            result = submit({"argv": argv, "ticket": ticket, "metadata": metadata})
        self.assertEqual(result["job_id"], "123456")
        self.assertEqual(run.call_args.args[0][-2:], ["jaguir26@hb.ucsc.edu", "sbatch --parsable"])
        script = run.call_args.kwargs["input"]
        self.assertIn("forecast_transition_control.py supervise", script)
        self.assertIn("#SBATCH --mem=1024M", script)
        self.assertIn("ulimit -f 1024", script)
        self.assertIn("ulimit -S -f 64", script)
        self.assertIn("srun --exclusive /usr/bin/python3.11", script)
        self.assertNotIn("Rscript --mode", script)

    def test_remote_verifier_requires_qualified_compute_callback_mocked(self):
        request = request_for(task()); request["host"] = "hummingbird"
        for name in ("source_root", "request_path", "ticket_path", "authorization_path", "source_manifest_path", "ledger_path"):
            request["coordinator_" + name] = "/qualified/" + name
        args = mock.Mock(ledger=Path(request["coordinator_ledger_path"]), ticket_sha256=HASH,
                         authorization_sha256=HASH)
        observed = {"verified": True, "task_id": "task-1", "host": "hummingbird"}
        with mock.patch.dict(control.os.environ, {"SLURM_JOB_ID": "123", "SLURM_JOB_NODELIST": "compute1"}), \
             mock.patch.object(control.socket, "gethostname", return_value="compute1"), \
             mock.patch.object(control.subprocess, "run", return_value=mock.Mock(stdout=json.dumps(observed))) as run:
            self.assertTrue(control.verify_claim_remote(args, request, self.auth)["verified"])
        self.assertEqual(run.call_args.args[0][-2], "jaguir26@muscat.be.ucsc.edu")
        self.assertIn("verify-claim", run.call_args.args[0][-1])
        with mock.patch.dict(control.os.environ, {}, clear=True), self.assertRaisesRegex(control.GateError, "compute allocation"):
            control.verify_claim_remote(args, request, self.auth)

    def test_dispatch_argv_operational_hashes_have_no_cycle(self):
        first = list(ARGV); second = list(ARGV)
        first[first.index("--claim-ticket-sha256")+1] = "a" * 64
        second[second.index("--claim-ticket-sha256")+1] = "c" * 64
        first[first.index("--authorization-sha256")+1] = "b" * 64
        second[second.index("--authorization-sha256")+1] = "d" * 64
        self.assertEqual(control.argv_spec_sha256(first), control.argv_spec_sha256(second))
        second[0] = "/unapproved/executable"
        self.assertNotEqual(control.argv_spec_sha256(first), control.argv_spec_sha256(second))

    def test_production_config_rejects_external_or_uncommitted_overlay(self):
        relative = "application/config/forecast_transition_multihost_v1.json"
        source = self.root / "source"; path = source / relative
        path.parent.mkdir(parents=True); path.write_text(json.dumps(self.auth.config))
        row = {"path": relative, "role": "new_workflow", "mode": "100644",
               "sha256": control.file_sha256(path), "blob": "e" * 40}
        tree = "100644 blob " + "e" * 40 + "\t" + relative + "\n"
        with mock.patch.object(control.subprocess, "check_output", return_value=tree):
            control.verify_production_config(path, source, [row], row["sha256"])
            external = self.root / "override.json"; external.write_bytes(path.read_bytes())
            with self.assertRaisesRegex(control.GateError, "exact regular source-root"):
                control.verify_production_config(external, source, [row], row["sha256"])
            for key, value in (("role", "unreviewed"), ("mode", "100755"),
                               ("sha256", "d" * 64), ("blob", "f" * 40)):
                altered = dict(row); altered[key] = value
                with self.subTest(field=key), self.assertRaises(control.GateError):
                    control.verify_production_config(path, source, [altered], row["sha256"])

    def test_transfer_metadata_rejects_credentials_without_printing_values(self):
        for payload in ({"password": "FAKE_UNIT_ONLY"}, {"nested": {"access-token": "FAKE_UNIT_ONLY"}},
                        {"private_key_path": "/fake/key"}, {"cookie": "FAKE_UNIT_ONLY"},
                        {"credential_helper": "FAKE_UNIT_ONLY"}, {"value": "olp_UNIT_TEST_NOT_REAL"},
                        {"value": "ghp_UNIT_TEST_NOT_REAL"}, {"value": "-----BEGIN PRIVATE KEY-----"}):
            with self.subTest(kind=list(payload)), self.assertRaises(control.GateError) as raised:
                control.metadata_without_secrets(payload)
            self.assertNotIn("FAKE_UNIT_ONLY", str(raised.exception))
            self.assertNotIn("UNIT_TEST_NOT_REAL", str(raised.exception))
        control.metadata_without_secrets({"claim_nonce": "opaque-unit-nonce", "claim_ticket_sha256": HASH})
        with self.assertRaisesRegex(control.GateError, "unknown external authorization"):
            control.metadata_without_secrets(dict(self.auth.authorization, unknown_extra="unit"), authorization=True)

    def test_actual_r_producer_envelope_cross_language(self):
        rscript = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
        if not rscript.is_file():
            self.skipTest("pinned R 4.6.0 absent; no alternate runtime claimed")
        ticket = self.claim(); self.dispatch(ticket); self.finish(ticket)
        request = dict(task(), expected_output_keys=task()["expected_output_keys"])
        claim = {"verified": True, "task_id": request["task_id"], "routing_id": request["routing_id"],
                 "claim_nonce": ticket["claim_nonce"]}
        payload = self.root / "r-producer-input.json"
        payload.write_text(json.dumps({"request": request, "claim": claim}))
        out = Path(ticket["output_root"]); out.mkdir(parents=True)
        envelope = self.root / "actual-r-envelope.json"
        # Invoke the real R sealing helper only: tiny synthetic artifacts, no
        # inference, forecast simulation, cache discovery or remote process.
        code = r'''
          args <- commandArgs(TRUE)
          source(file.path(args[1], "application/R/integrated_quantile_forecast.R"))
          x <- jsonlite::read_json(args[2], simplifyVector=FALSE)
          keys <- unlist(x$request$expected_output_keys)
          paths <- file.path(args[3], paste0("synthetic_",seq_along(keys),".rds"))
          for (path in paths) saveRDS(list(synthetic=TRUE,quantile=0.25),path)
          tab <- data.frame(relative_path=basename(paths),size_bytes=as.numeric(file.info(paths)$size),
            sha256=unname(tools::sha256sum(paths)),artifact_key=keys,
            integration_status="PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE")
          utils::write.csv(tab,file.path(args[3],"output_manifest.csv"),row.names=FALSE)
          sealed <- app_iqf_output_envelope(x$request,x$claim,tab,args[3])
          jsonlite::write_json(sealed,args[4],auto_unbox=TRUE,pretty=TRUE,digits=17)
        '''
        subprocess = control.subprocess
        subprocess.run([str(rscript), "-e", code, str(ROOT), str(payload), str(out), str(envelope)],
                       text=True, capture_output=True, check=True, timeout=30)
        sealed = control.read_json(envelope)
        csv_path = out / "output_manifest.csv"; original = csv_path.read_bytes()
        for status in ("PASS_PREDECLARED_SPLIT_STREAM_GATE", "REVIEW_INNER_INTEGRATION_RESOLUTION"):
            csv_path.write_text(original.decode().replace("PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE", status))
            altered = copy.deepcopy(sealed)
            record = next(item for item in altered["artifacts"] if item["relative_path"] == "output_manifest.csv")
            record.update(sha256=control.file_sha256(csv_path), bytes=csv_path.stat().st_size)
            with self.subTest(status=status), self.assertRaisesRegex(control.GateError, "integration REVIEW/FAIL"):
                self.ledger.accept(ticket["claim_nonce"], altered, out)
        csv_path.write_bytes(original)
        self.assertEqual(self.ledger.accept(ticket["claim_nonce"], sealed, out), control.object_sha256(sealed))

    def test_exact_identity_cancellation_is_dryrun(self):
        identity = {"host": "muscat", "boot_id": "boot-unit", "pid": 12345,
                    "start_ticks": 2000, "uid": 1000, "cwd": "/owned/source",
                    "cmdline": ["Rscript", "owned.R"], "runtime_root": "/owned/runtime",
                    "task_id": "task-1", "admission_stopped": True}
        result = control.cancellation_proof(identity, copy.deepcopy(identity), self.auth, task())
        self.assertTrue(result["dry_run"])
        self.assertEqual(result["signals_sent"], 0)
        for name in control.PROCESS_IDENTITY_FIELDS:
            observed = copy.deepcopy(identity); observed[name] = "wrong"
            with self.subTest(field=name), self.assertRaises(control.GateError):
                control.cancellation_proof(identity, observed, self.auth, task())
        observed = dict(identity, admission_stopped=False)
        with self.assertRaisesRegex(control.GateError, "stop admission"):
            control.cancellation_proof(identity, observed, self.auth, task())

    def supervisor_fixture(self):
        nonce = "unit-supervised-nonce"
        library = self.root / "lib-unit.so"; library.write_bytes(b"synthetic-not-a-loaded-library")
        backend = {"backend": "bundled_rblas", "library_path": str(library),
                   "library_sha256": control.file_sha256(library)}
        spec = {"schema_version": "forecast_transition_supervision_v1", "claim_nonce": nonce,
                "task_id": "task-1", "routing_id": "route-task-1", "host": "muscat",
                "worker_argv": ARGV, "budget": budget(), "source_root": str(self.root),
                "identity": {name: task()[name] for name in control.IDENTITY_FIELDS},
                "numerical_backend": backend}
        spec["budget"].update(wall_seconds=90, cpu_seconds=90)
        for field, suffix in (("started_path", "started.json"), ("terminal_path", "terminal.json"), ("log_path", "stdout.log")):
            spec[field] = str(self.root / (nonce + "." + suffix))
        verified = {"verified": True, **{name: spec[name] for name in
                    ("claim_nonce", "task_id", "routing_id", "host", "numerical_backend")},
                    "resource_budget": copy.deepcopy(spec["budget"]), "worker_argv_sha256": control.object_sha256(ARGV),
                    "metadata_root": str(self.root)}
        created = control.utc_now()
        verified.update(dispatch_created_utc=control.timestamp(created),
                        deadline_utc=control.timestamp(created+dt.timedelta(seconds=90)))
        def identity(pid, root):
            return {"host": "muscat", "hostname": "muscat", "pid": pid, "boot_id": "unit-boot",
                    "start_ticks": 1000 + pid, "cwd": str(root), "uid": 1000}
        child = mock.Mock(pid=12345); child.wait.return_value = 0
        return spec, verified, identity, child

    def test_supervisor_normal_exit_has_durable_started_and_terminal_receipts(self):
        spec, verified, identity, child = self.supervisor_fixture()
        runner = mock.Mock(return_value=child)
        with mock.patch.object(control.os, "killpg") as signals:
            result = control.supervised_child(spec, verified, runner=runner, identity=identity)
        self.assertEqual(result["exit_code"], 0)
        self.assertTrue(result["worker_terminated"])
        self.assertTrue(result["supervisor_exit_pending"])
        self.assertEqual(control.read_json(spec["terminal_path"]), result)
        self.assertEqual(control.read_json(spec["started_path"])["phase"], "started")
        self.assertTrue(0 < child.wait.call_args.kwargs["timeout"] <= 60)
        self.assertLessEqual(result["dispatch_elapsed_seconds"], spec["budget"]["wall_seconds"])
        self.assertNotIn("LD_PRELOAD", runner.call_args.kwargs["env"])
        self.assertEqual(runner.call_args.kwargs["env"]["OMP_NUM_THREADS"], "1")
        with mock.patch.object(control.os, "sched_setaffinity"), mock.patch.object(control.posix_resource, "setrlimit") as limits:
            runner.call_args.kwargs["preexec_fn"]()
        self.assertIn(mock.call(control.posix_resource.RLIMIT_FSIZE, (1024 ** 2, 1024 ** 2)), limits.call_args_list)
        signals.assert_not_called()
        with self.assertRaisesRegex(control.GateError, "overwritten"):
            control.durable_json(Path(spec["terminal_path"]), result)

    def test_supervisor_failed_exit_is_retained_not_retried(self):
        spec, verified, identity, child = self.supervisor_fixture()
        child.wait.return_value = 7
        runner = mock.Mock(return_value=child)
        result = control.supervised_child(spec, verified, runner=runner, identity=identity)
        self.assertEqual(result["exit_code"], 7); self.assertEqual(runner.call_count, 1)
        self.assertTrue(Path(spec["terminal_path"]).is_file())

    def test_supervisor_timeout_signals_only_exact_owned_child_mock(self):
        spec, verified, identity, child = self.supervisor_fixture()
        child.wait.side_effect = [control.subprocess.TimeoutExpired(ARGV, 10), 0]
        with mock.patch.object(control.os, "getpgid", return_value=child.pid), mock.patch.object(control.os, "killpg") as signals:
            result = control.supervised_child(spec, verified, runner=mock.Mock(return_value=child), identity=identity)
        self.assertEqual(result["exit_code"], 124); self.assertTrue(result["timed_out"])
        signals.assert_called_once_with(child.pid, 15)

    def test_supervisor_refuses_changed_host_budget_command_or_log_namespace(self):
        for name, value, pattern in (("host", "jerez", "claim/routing"),
                                     ("worker_argv", ARGV + ["unbound"], "command/budget"),
                                     ("log_path", str(self.root.parent / "escape.log"), "namespace")):
            spec, verified, identity, child = self.supervisor_fixture()
            spec[name] = value; runner = mock.Mock(return_value=child)
            with self.subTest(field=name), self.assertRaisesRegex(control.GateError, pattern):
                control.supervised_child(spec, verified, runner=runner, identity=identity)
            runner.assert_not_called()

    def test_supervisor_rejects_tiny_or_expired_complete_wall_budget(self):
        spec, verified, identity, child = self.supervisor_fixture()
        spec["budget"].update(wall_seconds=10,cpu_seconds=10)
        verified["resource_budget"] = copy.deepcopy(spec["budget"])
        with self.assertRaisesRegex(control.GateError, "at least60"):
            control.supervised_child(spec, verified, runner=mock.Mock(return_value=child), identity=identity)
        spec, verified, identity, child = self.supervisor_fixture()
        verified["dispatch_created_utc"] = control.timestamp(control.utc_now()-dt.timedelta(seconds=80))
        verified["deadline_utc"] = control.timestamp(control.parse_utc(verified["dispatch_created_utc"])+dt.timedelta(seconds=90))
        with self.assertRaisesRegex(control.GateError, "no bounded"):
            control.supervised_child(spec, verified, runner=mock.Mock(return_value=child), identity=identity)

    def test_backend_environment_is_explicit_clean_and_library_bound(self):
        library = self.root / "unit-library.so"; library.write_bytes(b"not-a-loaded-library")
        backend = {"backend": "bundled_rblas", "library_path": str(library), "library_sha256": control.file_sha256(library)}
        inherited = {"LD_PRELOAD": "/unapproved.so", "LD_LIBRARY_PATH": "/unapproved", "R_PROFILE_USER": "/bad.R",
                     "PYTHONPATH": "/bad", "OPENBLAS_NUM_THREADS": "64", "QDESN_BLAS_LIBRARY_PATH": "/old.so"}
        with mock.patch.dict(control.os.environ, inherited):
            env = control.numerical_backend_environment(backend)
        self.assertNotIn("LD_PRELOAD", env); self.assertNotIn("LD_LIBRARY_PATH", env)
        self.assertNotIn("QDESN_BLAS_LIBRARY_PATH", env); self.assertNotIn("PYTHONPATH", env)
        self.assertEqual(env["R_PROFILE_USER"], "/dev/null"); self.assertEqual(env["OPENBLAS_NUM_THREADS"], "1")
        env = control.numerical_backend_environment(dict(backend, backend="openblas_pthread"))
        self.assertEqual(env["LD_PRELOAD"], str(library)); self.assertEqual(env["QDESN_BLAS_LIBRARY_SHA256"], backend["library_sha256"])
        with self.assertRaisesRegex(control.GateError, "library identity"):
            control.numerical_backend_environment(dict(backend, library_sha256="0" * 64))
        link = self.root / "link.so"; link.symlink_to(library)
        with self.assertRaisesRegex(control.GateError, "library identity"):
            control.numerical_backend_environment(dict(backend, library_path=str(link)))

    def test_transport_profile_is_strict_and_source_owned(self):
        profile = copy.deepcopy(self.auth.config["hosts"]["jerez"]["ssh_profile"])
        argv = control.ssh_argv(profile, "hostname -s")
        self.assertIn("jaguir26@jerez.be.ucsc.edu", argv)
        self.assertIn("ForwardAgent=no", argv); self.assertIn("IdentityAgent=none", argv)
        with self.assertRaisesRegex(control.GateError, "approved SSH endpoint"):
            control.ssh_argv(dict(profile, endpoint="unapproved.example"), "hostname -s")
        with self.assertRaisesRegex(control.GateError, "exact SSH"):
            control.ssh_argv(dict(profile, extra_option="ProxyCommand=unreviewed"), "hostname -s")
        known = self.root / "known-hosts"; known.write_text("unit-public-host-record")
        with self.assertRaisesRegex(control.GateError, "snapshot"):
            control.ssh_argv(dict(profile, known_hosts_file=str(known), known_hosts_sha256=HASH), "hostname -s")

    def test_preintent_abandonment_is_exact_bounded_and_not_a_retry(self):
        ticket = self.claim(); nonce = ticket["claim_nonce"]
        proof = {"claim_nonce": nonce, "host": "muscat", "no_submission": True, "evidence_sha256": HASH}
        self.ledger.abandon_preintent(nonce, proof)
        self.assertEqual(self.ledger.row(nonce)["state"], "abandoned_preintent")
        with self.assertRaisesRegex(control.GateError, "reconciliation"):
            self.claim()
        ticket2 = self.claim(task("task-2"), cpu=1)
        self.ledger.prepare_intent(ticket2["claim_nonce"], self.root, ARGV)
        with self.assertRaisesRegex(control.GateError, "no durable intent"):
            self.ledger.abandon_preintent(ticket2["claim_nonce"], dict(proof, claim_nonce=ticket2["claim_nonce"]))

    def test_abandoned_claim_metadata_reservation_is_not_refunded(self):
        ceiling = 2 * budget()["metadata_bytes"]
        self.auth.config["production_budget"]["max_metadata_bytes"] = ceiling
        self.auth.config_sha256 = control.object_sha256(self.auth.config)
        self.auth.authorization["config_sha256"] = self.auth.config_sha256
        self.auth.authorization["budget"]["max_metadata_bytes"] = ceiling
        for index in (1, 2):
            ticket = self.claim(task("task-" + str(index)), cpu=index)
            self.ledger.abandon_preintent(ticket["claim_nonce"], {"claim_nonce": ticket["claim_nonce"],
                "host": "muscat", "no_submission": True, "evidence_sha256": HASH})
        with self.assertRaisesRegex(control.GateError, "metadata_bytes budget at claim"):
            self.claim(task("task-3"), cpu=3)

    def test_supervised_closeout_requires_independent_owner_and_accounting_proof(self):
        ticket = self.claim(); self.dispatch(ticket); nonce = ticket["claim_nonce"]
        body = {"schema_version": "forecast_transition_supervisor_receipt_v1", "phase": "terminal",
                "claim_nonce": nonce, "host": "muscat", "routing_id": ticket["routing_id"],
                "worker_terminated": True, "job_id": "mock-job-task-1", "exit_code": 0,
                "identity": {name: task()[name] for name in control.IDENTITY_FIELDS}, "worker_argv_sha256": control.object_sha256(ARGV)}
        intent = control.read_json(self.ledger.row(nonce)["intent_path"])
        body.update(dispatch_created_utc=intent["created_utc"],deadline_utc=intent["deadline_utc"],
                    dispatch_elapsed_seconds=5,utc=intent["created_utc"])
        proof = {"claim_nonce": nonce, "host": "muscat", "job_id": body["job_id"],
                 "owner_terminated": True, "accounting_complete": True, "no_orphans": True,
                 "supervisor_receipt_sha256": control.object_sha256(body), "evidence_sha256": HASH}
        with self.assertRaisesRegex(control.GateError, "independent terminal"):
            self.ledger.close_supervised(nonce, body, dict(proof, no_orphans=False))
        self.assertEqual(self.ledger.row(nonce)["state"], "submitted")
        late = dict(body,dispatch_elapsed_seconds=11)
        late_proof = dict(proof,supervisor_receipt_sha256=control.object_sha256(late))
        with self.assertRaisesRegex(control.GateError, "charged wall deadline"):
            self.ledger.close_supervised(nonce, late, late_proof)
        self.ledger.close_supervised(nonce, body, proof)
        self.assertEqual(self.ledger.row(nonce)["state"], "succeeded")

    def test_ambiguous_success_can_only_adopt_the_same_fenced_nonce(self):
        ticket = self.claim(); nonce = ticket["claim_nonce"]
        self.ledger.prepare_intent(nonce, self.root, ARGV)
        with self.assertRaises(control.GateError):
            self.ledger.dispatch(nonce, mock.Mock(side_effect=RuntimeError("mock-transport-loss")))
        terminal = {"claim_nonce": nonce, "host": "muscat", "job_id": "one-exact-job", "exit_code": 0,
                    "owner_terminated": True, "accounting_complete": True,
                    "identity": {name: task()[name] for name in control.IDENTITY_FIELDS}, "worker_argv_sha256": control.object_sha256(ARGV)}
        proof = {"claim_nonce": nonce, "host": "muscat", "job_id": "one-exact-job", "matching_jobs": 1,
                 "owner_terminated": True, "accounting_complete": True, "no_orphans": True,
                 "evidence_sha256": HASH, "terminal_receipt_sha256": control.object_sha256(terminal)}
        with self.assertRaisesRegex(control.GateError, "one exact"):
            self.ledger.adopt_ambiguous(nonce, dict(proof, matching_jobs=2), terminal)
        self.ledger.adopt_ambiguous(nonce, proof, terminal)
        self.assertEqual(self.ledger.row(nonce)["state"], "succeeded")
        self.assertEqual(len(self.ledger.db.execute("SELECT nonce FROM attempts").fetchall()), 1)
        with self.assertRaisesRegex(control.GateError, "active owner|reconciliation"):
            self.claim()

    def test_closeout_cli_requires_explicit_authority_and_does_not_create_a_ledger(self):
        missing = self.root / "must-not-create.sqlite"
        for command in ("close-supervised", "abandon-preintent", "accept", "reassign"):
            with self.subTest(command=command), self.assertRaisesRegex(control.GateError, "--execute"):
                control.main([command, "--ledger", str(missing), "--nonce", "unit"])
        self.assertFalse(missing.exists())

    def test_real_supervisor_argv_is_accepted_by_controller_parser(self):
        command = control.supervision_argv(self.auth.config, "muscat", ROOT, ARGV,
            {"remote_path": "/missing/spec.json", "sha256": HASH})
        # Reaches the fail-closed file/authority check rather than argparse's
        # unknown-option SystemExit; no subprocess or model work occurs.
        with self.assertRaisesRegex(control.GateError, "claim ticket file/hash"):
            control.main(command[2:])

    def test_accepted_dependency_is_rehashed_not_a_status_marker(self):
        ticket, manifest, out = self.ready_output()
        Path(str(out) + ".output_manifest.json").write_text(json.dumps(manifest))
        self.ledger.accept(ticket["claim_nonce"], manifest, out)
        verified = self.ledger.accepted_output("task-1")
        self.assertEqual(verified["claim_nonce"], ticket["claim_nonce"])
        self.assertEqual(len(verified["artifacts"]), 2)
        (out / manifest["shards"][0]["relative_path"]).write_text("tampered")
        with self.assertRaisesRegex(control.GateError, "prerequisite artifact changed"):
            self.ledger.accepted_output("task-1")

    def test_readonly_claim_receipt_authenticates_exact_accepted_prerequisite_artifacts(self):
        parent, manifest, out = self.ready_output()
        Path(str(out)+".output_manifest.json").write_text(json.dumps(manifest))
        self.ledger.accept(parent["claim_nonce"],manifest,out)
        child = task("task-2",[{"task_id":"task-1","task_manifest_sha256":HASH,"posterior_target_sha256":HASH}])
        self.auth.authorization["allowed_task_sha256"]["task-2"] = control.object_sha256(child)
        ticket = self.claim(child,cpu=1);self.dispatch(ticket)
        request = dict(request_for(child),output_root=ticket["output_root"])
        receipt = control.verify_claim_readonly(self.ledger.path,ticket,request,self.auth,coordinator_hostname="muscat")
        proof = receipt["accepted_prerequisites"][0]
        self.assertEqual(proof["output_manifest_sha256"],control.object_sha256(manifest))
        self.assertEqual(proof["identity"],{name:manifest[name] for name in control.IDENTITY_FIELDS})
        self.assertTrue(all(set(row)=={"relative_path","sha256","bytes"} for row in proof["artifacts"]))
        (out/manifest["shards"][0]["relative_path"]).write_text("tampered")
        with self.assertRaisesRegex(control.GateError,"prerequisite artifact changed"):
            control.verify_claim_readonly(self.ledger.path,ticket,request,self.auth,coordinator_hostname="muscat")

    def test_typed_master_derivation_roundtrip_and_scope_mutations(self):
        module_spec = importlib.util.spec_from_file_location("campaign_fixture",ROOT/"application/tests/test_glofas_transition_campaign.py")
        fixture = importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(fixture)
        master,prepared,state = fixture.make_fixture(self.root/"master-fixture")
        G = fixture.G
        with mock.patch.object(G.C,"git_identity",return_value=(master["source_commit"],master["source_tree"],True)):
            templates = G.validate(master,prepared)
        state.mkdir()
        grant_record = G.C.read_json(master["resource_grant_path"])
        paths,auth = G.freeze("gft-al-p050",templates,{},master,state,24,{"host":"muscat"},grant_record)
        loaded,digest = control.load_authorization(paths["authorization"],control.file_sha256(paths["authorization"]),ROOT)
        self.assertEqual(loaded,auth);self.assertEqual(digest,control.file_sha256(paths["authorization"]))
        for name,change in (("task",lambda x:x.update(allowed_task_ids=["gft-al-p035"])),
                            ("budget",lambda x:x["budget"].update(max_cpu_seconds=10**12)),
                            ("host",lambda x:x.update(allowed_hosts=["jerez"])),
                            ("operation",lambda x:x["allowed_operations"].append("reassign")),
                            ("untyped",lambda x:x.pop("master_grant_sha256"))):
            bad=copy.deepcopy(auth);change(bad);paths["authorization"].write_text(json.dumps(bad))
            with self.subTest(mutation=name),self.assertRaises(control.GateError):
                control.load_authorization(paths["authorization"],control.file_sha256(paths["authorization"]),ROOT)
        paths["authorization"].write_text(json.dumps(auth))
        master_file=Path(master["master_grant_path"]);master_file.write_text(master_file.read_text()+" ")
        with self.assertRaisesRegex(control.GateError,"master/template/grant digest"):
            control.load_authorization(paths["authorization"],control.file_sha256(paths["authorization"]),ROOT)

    def test_actual_r_blocked_producer_many_members_one_artifact(self):
        rscript = Path("/data/jaguir26/local/opt/R/4.6.0/bin/Rscript")
        if not rscript.is_file():
            self.skipTest("pinned R 4.6.0 absent")
        spec = task(); spec["expected_output_keys"] = ["draw:d1|origin:o1", "draw:d2|origin:o1"]
        spec["expected_output_keys_sha256"] = control.object_sha256(sorted(spec["expected_output_keys"]))
        self.auth.authorization["allowed_task_sha256"]["task-1"] = control.object_sha256(spec)
        ticket = self.claim(spec); self.dispatch(ticket); self.finish(ticket)
        claim = {"verified": True, "task_id": spec["task_id"], "routing_id": spec["routing_id"], "claim_nonce": ticket["claim_nonce"]}
        payload = self.root / "block-input.json"; payload.write_text(json.dumps({"request": spec, "claim": claim}))
        out = Path(ticket["output_root"]); out.mkdir(parents=True)
        sidecar = Path(str(out) + ".output_manifest.json")
        code = r'''
          a<-commandArgs(TRUE);source(file.path(a[1],"application/R/integrated_quantile_forecast.R"))
          source(file.path(a[1],"scripts/integrated_quantile_blocks.R"));x<-jsonlite::read_json(a[2],simplifyVector=FALSE)
          fixture<-function(i)list(schema_version="integrated_quantile_forecast_shard_v1",draw_id=paste0("d",i),origin_id="o1",
            integration_status="PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE",quantiles=data.frame(model_id="m",draw_id=paste0("d",i),
            origin_id="o1",horizon=1L,probability=.5,quantile=i/10,functional="parameter_conditional_integrated_quantile"))
          b<-app_iqf_pack_block(lapply(1:2,fixture));path<-file.path(a[3],"block.rds");saveRDS(b,path)
          tab<-data.frame(relative_path="block.rds",member_index=1:2,size_bytes=file.info(path)$size,
            sha256=app_iqf_hash(path,TRUE),artifact_key=b$member_keys,integration_status="PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE")
          write.csv(tab,file.path(a[3],"output_manifest.csv"),row.names=FALSE)
          sealed<-app_iqf_block_envelope(x$request,x$claim,tab,a[3]);jsonlite::write_json(sealed,a[4],auto_unbox=TRUE,digits=17)
        '''
        control.subprocess.run([str(rscript), "-e", code, str(ROOT), str(payload), str(out), str(sidecar)],
                               capture_output=True, text=True, check=True, timeout=30)
        manifest = control.read_json(sidecar)
        self.assertEqual(len(manifest["shards"]), 2); self.assertEqual(len(manifest["artifacts"]), 2)
        self.assertEqual(len({row["relative_path"] for row in manifest["shards"]}), 1)
        for kind in ("missing", "duplicate", "hash"):
            bad = copy.deepcopy(manifest)
            if kind == "missing": bad["shards"].pop()
            elif kind == "duplicate": bad["shards"][1]["key"] = bad["shards"][0]["key"]
            else: bad["shards"][0]["sha256"] = "0" * 64
            with self.subTest(kind=kind), self.assertRaises(control.GateError):
                self.ledger.accept(ticket["claim_nonce"], bad, out)
        self.ledger.accept(ticket["claim_nonce"], manifest, out)
        self.assertEqual(len(self.ledger.accepted_output(spec["task_id"])["artifacts"]), 2)

    def test_manifest_and_external_authorization_checks(self):
        data = self.root / "input.csv"; data.write_text("value\n1\n")
        manifest = self.root / "input-manifest.csv"
        with manifest.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=["relative_path", "size_bytes", "sha256", "role"])
            writer.writeheader(); writer.writerow({"relative_path": data.name, "size_bytes": data.stat().st_size,
                "sha256": control.file_sha256(data), "role": "immutable_input"})
        self.assertEqual(len(control.verify_file_manifest(self.root, manifest, control.file_sha256(manifest))), 1)
        data.write_text("value\n2\n")
        with self.assertRaisesRegex(control.GateError, "payload hash"):
            control.verify_file_manifest(self.root, manifest, control.file_sha256(manifest))
        authorization_path = self.root / "authorization.json"
        authorization_path.write_text(json.dumps(self.auth.authorization))
        observed, digest = control.load_authorization(authorization_path, control.file_sha256(authorization_path), ROOT)
        self.assertEqual(observed["approved_by"], "unit-test-only")
        with self.assertRaisesRegex(control.GateError, "external"):
            control.load_authorization(authorization_path, control.file_sha256(authorization_path), self.root)
        with self.assertRaisesRegex(control.GateError, "digest"):
            control.load_authorization(authorization_path, "d" * 64, ROOT)

    def test_hash_and_rng_identity_stable_across_routes(self):
        original = task()
        other = task("task-2"); other["routing_id"] = "route-other-host"
        self.assertEqual(original["rng_namespace"], other["rng_namespace"])
        self.assertNotEqual(control.object_sha256(original), control.object_sha256(other))
        with self.assertRaises(ValueError):
            control.object_sha256({"value": float("nan")})


if __name__ == "__main__":
    unittest.main(verbosity=2)
