"""Small synthetic SQLite/output fixtures; never opens the live ledger or models."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("glofas_collection", ROOT/"scripts/collect_glofas_same_family_producers.py")
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)
C = G.load_controller(ROOT)


class CollectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="glofas_synthetic_collection_")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ledger = self.root/"ledger.sqlite"
        self.complete = self.root/"COMPLETE.json"
        self.accepted = {}
        self.tasks = {}
        with sqlite3.connect(self.ledger) as db:
            db.execute("CREATE TABLE tasks(task_id TEXT PRIMARY KEY,spec TEXT)")
            db.execute("CREATE TABLE attempts(task_id TEXT,state TEXT,ticket TEXT,output_manifest_sha TEXT,"
                       "nonce TEXT,routing_id TEXT,terminal_receipt TEXT)")
            for task_id in G.TASKS:
                task = dict(G.IDENTITY, task_id=task_id, rng_namespace=task_id,
                            routing_id="route-"+task_id, workflow="glofas_family_transition")
                self.tasks[task_id] = task
                output = self.root/task_id
                output.mkdir()
                artifacts = []
                for name in sorted(G.ARTIFACTS):
                    p = output/name
                    p.write_bytes(b"synthetic fixture bytes: not a model or real data\n")
                    artifacts.append({"relative_path": name, "bytes": p.stat().st_size, "sha256": G.sha(p)})
                manifest = {key: task[key] for key in C.IDENTITY_FIELDS}
                manifest.update(routing_id=task["routing_id"], claim_nonce="nonce-"+task_id,
                                numerical_gates_pass=True, shards=artifacts)
                Path(str(output)+".output_manifest.json").write_text(json.dumps(manifest))
                digest = C.object_sha256(manifest)
                self.accepted[task_id] = digest
                terminal = dict(task_id=task_id, routing_id=task["routing_id"],
                    identity={key: task[key] for key in C.IDENTITY_FIELDS}, claim_nonce="nonce-"+task_id,
                    exit_code=0, accounting_complete=True, owner_terminated=True,
                    worker_terminated=True, timed_out=False)
                db.execute("INSERT INTO tasks VALUES(?,?)", (task_id, json.dumps(task)))
                db.execute("INSERT INTO attempts VALUES(?,?,?,?,?,?,?)", (task_id,"accepted",
                    json.dumps({"output_root":str(output)}),digest,"nonce-"+task_id,
                    task["routing_id"],json.dumps(terminal)))
        self.complete.write_text(json.dumps({"status":"COHORT_COMPLETE_NOT_ARTICLE_PROMOTION",
            "master_sha256":"e"*64, "accepted":self.accepted}))
        self.contract = {"schema_version":"glofas_same_family_collection_contract_v1",
            "allow_ledger_mutation":False,"allow_refit":False,"allow_truth":False,
            "expected_identity":dict(G.IDENTITY), "master_sha256":"e"*64,
            "read_budget":{"max_artifact_bytes":1024**2,"max_total_artifact_bytes":32*1024**2},
            "ledger_snapshot":self.pin(self.ledger),"complete":self.pin(self.complete)}

    @staticmethod
    def pin(p):
        return {"path":str(p),"size_bytes":p.stat().st_size,"sha256":G.sha(p)}

    def mutate(self, sql, args=()):
        with sqlite3.connect(self.ledger) as db:
            db.execute(sql,args)
        self.contract["ledger_snapshot"] = self.pin(self.ledger)

    def collect(self):
        return G.collect(self.contract,C)

    def rejects(self, pattern):
        return self.assertRaisesRegex((ValueError,C.GateError),pattern)

    def test_sixteen_readonly_and_retains_historical_identity(self):
        before = self.pin(self.ledger)
        result = self.collect()
        self.assertEqual(len(result["producers"]),16)
        self.assertEqual(result["ledger_mutations"],0)
        self.assertEqual(result["fit_objects_loaded"],0)
        self.assertFalse(result["future_truth_read"])
        self.assertEqual(before,self.pin(self.ledger))
        self.assertEqual(result["artifact_hash_read_bytes"],sum(
            a["size_bytes"] for p in result["producers"] for a in p["artifacts"]))
        for p in result["producers"]:
            self.assertEqual(p["identity"]["source_commit"],G.IDENTITY["source_commit"])
            self.assertEqual(p["identity"]["rng_namespace"],p["task_id"])
            self.assertEqual({a["relative_path"] for a in p["artifacts"]},G.ARTIFACTS)

    def test_incomplete_active_failed_or_retried_producer_rejected(self):
        for state in ("intent","submitted","failed","reconciled"):
            with self.subTest(state=state):
                self.mutate("UPDATE attempts SET state=? WHERE task_id=?",(state,G.TASKS[0]))
                with self.rejects("all sixteen centrally accepted"):
                    self.collect()
        self.mutate("UPDATE attempts SET state='accepted' WHERE task_id=?",(G.TASKS[0],))
        self.mutate("INSERT INTO attempts SELECT * FROM attempts WHERE task_id=?",(G.TASKS[0],))
        with self.rejects("all sixteen centrally accepted"):
            self.collect()

    def test_missing_or_mixed_task_rejected(self):
        self.mutate("DELETE FROM tasks WHERE task_id=?",(G.TASKS[0],))
        with self.rejects("exact task set"):
            self.collect()

    def test_source_target_and_workflow_rejected(self):
        for key,value in (("source_commit","wrong"),("posterior_target_sha256","0"*64),
                          ("workflow","legacy_gaussian_path"),("rng_namespace","wrong")):
            task = dict(self.tasks[G.TASKS[0]],**{key:value})
            self.mutate("UPDATE tasks SET spec=? WHERE task_id=?",(json.dumps(task),G.TASKS[0]))
            with self.rejects("producer target/source identity"):
                self.collect()

    def test_closed_terminal_identity_required(self):
        with sqlite3.connect(self.ledger) as db:
            original = json.loads(db.execute("SELECT terminal_receipt FROM attempts LIMIT 1").fetchone()[0])
        for key,value in (("exit_code",1),("accounting_complete",False),("worker_terminated",False),
                          ("owner_terminated",False),("timed_out",True),("task_id","other"),
                          ("routing_id","other"),("identity",{}),("claim_nonce","other")):
            terminal = dict(original,**{key:value})
            self.mutate("UPDATE attempts SET terminal_receipt=? WHERE task_id=?",(json.dumps(terminal),G.TASKS[0]))
            with self.rejects("terminal accounting"):
                self.collect()

    def test_complete_status_and_canonical_digest(self):
        d = json.loads(self.complete.read_text());d["accepted"][G.TASKS[0]] = "0"*64
        self.complete.write_text(json.dumps(d));self.contract["complete"] = self.pin(self.complete)
        with self.rejects("complete-map"):
            self.collect()
        d["status"] = "PARTIAL";self.complete.write_text(json.dumps(d));self.contract["complete"] = self.pin(self.complete)
        with self.rejects("complete sixteen-fit"):
            self.collect()

    def test_payload_or_sidecar_tamper_rejected(self):
        p = self.root/G.TASKS[0]/"fit.rds";p.write_bytes(b"not the accepted bytes")
        with self.rejects("accepted prerequisite artifact changed"):
            self.collect()

    def test_unknown_artifact_rejected_before_any_fit_hash(self):
        sidecar = Path(str(self.root/G.TASKS[0])+".output_manifest.json")
        m = json.loads(sidecar.read_text());m["shards"][0]["relative_path"] = "future_truth.csv"
        sidecar.write_text(json.dumps(m))
        with self.rejects("exact six producer artifacts"):
            self.collect()

    def test_nonempty_wal_is_never_ignored_or_checkpointed(self):
        wal = Path(str(self.ledger)+"-wal");wal.write_bytes(b"unbound WAL")
        with self.rejects("nonempty WAL rejected"):
            self.collect()
        self.assertEqual(wal.read_bytes(),b"unbound WAL")

    def test_finite_read_budget_and_fixed_identity(self):
        self.contract["read_budget"]["max_artifact_bytes"] = 1
        with self.rejects("per-artifact read ceiling"):
            self.collect()
        self.contract["read_budget"]["max_artifact_bytes"] = 1024**2
        self.contract["read_budget"]["max_total_artifact_bytes"] = 1
        with self.rejects("total artifact-hash read ceiling"):
            self.collect()
        self.contract["expected_identity"]["source_tree"] = "0"*40
        with self.rejects("frozen producer source and target"):
            self.collect()

    def test_compiled_read_ceiling_allows_source_admitted_mq_but_is_not_renewable(self):
        self.contract["read_budget"] = {"max_artifact_bytes":8*1024**3,
                                        "max_total_artifact_bytes":44*1024**3}
        self.assertEqual(len(self.collect()["producers"]),16)
        self.contract["read_budget"]["max_artifact_bytes"] = 9*1024**3
        with self.rejects("finite artifact-hash read budget"):
            self.collect()

    def test_snapshot_pin_and_symlink_rejected(self):
        self.contract["ledger_snapshot"]["sha256"] = "0"*64
        with self.rejects("input bytes changed"):
            self.collect()
        link = self.root/"alias.sqlite";link.symlink_to(self.ledger)
        self.contract["ledger_snapshot"] = self.pin(link)
        with self.rejects("nonsymlink"):
            self.collect()

    def test_scope_cannot_enable_mutation_fit_or_truth(self):
        for key in ("allow_ledger_mutation","allow_refit","allow_truth"):
            with self.subTest(key=key):
                original = self.contract[key];self.contract[key] = True
                with self.rejects("read-only exact collection scope"):
                    self.collect()
                self.contract[key] = original


if __name__ == "__main__":
    unittest.main()
