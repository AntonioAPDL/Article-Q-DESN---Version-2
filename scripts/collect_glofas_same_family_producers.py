#!/usr/bin/env python3
"""Read-only verification of a pinned, quiescent sixteen-producer ledger.

No live-ledger checkpoint, backup, mutation, model load or truth access occurs.
The coordinator must separately seal the SQLite snapshot after cohort closure.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sqlite3
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
TASKS = tuple("gft-" + f + "-p" + p for f in ("al", "exal")
              for p in ("005", "020", "035", "050", "065", "080", "095")) + ("gft-mq-al", "gft-mq-exal")
IDENTITY = {
    "source_commit": "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6",
    "source_tree": "0d0d1eefbc930b31c404a301ace28c8e190b8453",
    "source_manifest_sha256": "cd6684a6933de85f23d942a538c1efd241e66821b974467afb108379c068887b",
    "posterior_target_sha256": "72ef0550393106009b100636e1b11e8c21d4da31e77ed01a3dc2663439dbef03",
    "input_manifest_sha256": "f298dac4dd45479bd847528feab6d1104a8086f2c85116c8568acc53c871ae7f",
    "task_manifest_sha256": "af3281e0aa916ea1ff4a793752c221e051422f2d6705c9f88da471c1e58e5397"}
ARTIFACTS = {"fit.rds", "forecast_quantiles.csv", "raw_crossings.csv", "target_receipt.json",
             "progress.csv", "artifact_manifest.csv"}


def require(ok, message):
    if not ok:
        raise ValueError("GloFAS producer collection: " + message)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024**2), b""):
            h.update(block)
    return h.hexdigest()


def pin(value, max_bytes=32*1024**2):
    require(isinstance(value, dict) and set(value) == {"path", "size_bytes", "sha256"}, "exact file pin")
    p = Path(value["path"])
    require(p.is_absolute() and p.is_file() and p.resolve() == p and
            not any(x.is_symlink() for x in (p, *p.parents)), "regular nonsymlink path")
    require(type(value["size_bytes"]) is int and 0 < value["size_bytes"] <= max_bytes and
            p.stat().st_size == value["size_bytes"] and sha(p) == value["sha256"], "input bytes changed")
    return p


def load_controller(root=ROOT):
    path = root / "application/scripts/forecast_transition_control.py"
    spec = importlib.util.spec_from_file_location("gsc_frozen_controller", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def collect(spec, controller):
    require(spec.get("schema_version") == "glofas_same_family_collection_contract_v1" and
            spec.get("allow_ledger_mutation") is False and spec.get("allow_refit") is False and
            spec.get("allow_truth") is False, "read-only exact collection scope")
    require(spec.get("expected_identity") == IDENTITY, "frozen producer source and target")
    require(isinstance(spec.get("master_sha256"), str) and
            re.fullmatch("[0-9a-f]{64}", spec["master_sha256"]) is not None, "frozen cohort master digest")
    budget = spec.get("read_budget", {})
    require(set(budget) == {"max_artifact_bytes", "max_total_artifact_bytes"} and
            all(type(v) is int for v in budget.values()) and
            0 < budget["max_artifact_bytes"] <= 1024**3 and
            0 < budget["max_total_artifact_bytes"] <= 4*1024**3,
            "finite artifact-hash read budget required")
    ledger = pin(spec["ledger_snapshot"])
    # A raw DB digest does not bind uncheckpointed WAL contents. Refuse rather
    # than checkpointing somebody else's live ledger or overlooking its WAL.
    require(not Path(str(ledger)+"-wal").exists() or Path(str(ledger)+"-wal").stat().st_size == 0,
            "seal a SQLite-consistent snapshot separately; nonempty WAL rejected")
    complete_path = pin(spec["complete"], 1024**2)
    complete = json.loads(complete_path.read_text())
    require(complete.get("status") == "COHORT_COMPLETE_NOT_ARTICLE_PROMOTION" and
            complete.get("master_sha256") == spec.get("master_sha256") and
            set(complete.get("accepted", {})) == set(TASKS), "complete sixteen-fit cohort receipt")
    result = []; read_bytes = 0
    with sqlite3.connect(ledger.as_uri()+"?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        require(db.execute("PRAGMA query_only=ON").fetchall() == [], "query-only connection")
        tasks = db.execute("SELECT task_id FROM tasks").fetchall()
        require({row[0] for row in tasks} == set(TASKS), "exact task set, no mixed campaign")
        attempts = db.execute("SELECT * FROM attempts ORDER BY rowid").fetchall()
        require(len(attempts) == 16 and {row["task_id"] for row in attempts} == set(TASKS) and
                all(row["state"] == "accepted" for row in attempts), "all sixteen centrally accepted; no retry/active/failure")
        for row in attempts:
            task = json.loads(db.execute("SELECT spec FROM tasks WHERE task_id=?", (row["task_id"],)).fetchone()[0])
            identity = {key: task[key] for key in controller.IDENTITY_FIELDS}
            identity["routing_id"] = task["routing_id"]
            require(all(identity.get(k) == v for k, v in spec["expected_identity"].items()) and
                    task.get("workflow") == "glofas_family_transition" and
                    identity["rng_namespace"] == row["task_id"], "producer target/source identity")
            terminal = json.loads(row["terminal_receipt"])
            require(terminal.get("exit_code") == 0 and terminal.get("accounting_complete") is True and
                    terminal.get("owner_terminated") is True and terminal.get("worker_terminated") is True and
                    terminal.get("timed_out") is False and terminal.get("claim_nonce") == row["nonce"] and
                    terminal.get("task_id") == row["task_id"] and
                    terminal.get("routing_id") == identity["routing_id"] and
                    terminal.get("identity") == {k: task[k] for k in controller.IDENTITY_FIELDS},
                    "successful terminal accounting required")
            # Inspect only the small authenticated sidecar first. The native
            # verifier below hashes model bytes but never deserializes them.
            output = Path(json.loads(row["ticket"])["output_root"])
            sidecar = Path(str(output)+".output_manifest.json")
            require(sidecar.is_file() and not sidecar.is_symlink() and
                    sidecar.stat().st_size <= 4*1024**2, "bounded output sidecar")
            metadata = json.loads(sidecar.read_text())
            require(sum(key in metadata for key in ("artifacts", "shards")) == 1,
                    "one unambiguous native producer inventory")
            inventory = metadata.get("artifacts", metadata.get("shards", []))
            require(len(inventory) == 6 and {a.get("relative_path") for a in inventory} == ARTIFACTS,
                    "exact six producer artifacts, no mixed payload")
            require(all(type(a.get("bytes")) is int and 0 < a["bytes"] <= budget["max_artifact_bytes"]
                        for a in inventory), "per-artifact read ceiling")
            read_bytes += sum(a["bytes"] for a in inventory)
            require(read_bytes <= budget["max_total_artifact_bytes"], "total artifact-hash read ceiling")
            packet = controller.Ledger.accepted_output_readonly(db, row["task_id"])
            require(packet["output_manifest_sha256"] == complete["accepted"][row["task_id"]] and
                    packet["manifest"].get("numerical_gates_pass") is True, "complete-map and numerical acceptance")
            result.append({"task_id": row["task_id"], "state": "accepted", "identity": identity,
                "claim_nonce": row["nonce"], "output_manifest_sha256": packet["output_manifest_sha256"],
                "numerical_gates_pass": True,
                "terminal": {k: terminal[k] for k in ("exit_code", "accounting_complete", "owner_terminated",
                                                     "worker_terminated", "timed_out")},
                "artifacts": [{"relative_path": a["relative_path"], "path": a["path"],
                    "size_bytes": a["bytes"], "sha256": a["sha256"]} for a in packet["artifacts"]]})
    pin(spec["ledger_snapshot"]); pin(spec["complete"], 1024**2)
    return {"schema_version": "glofas_same_family_accepted_collection_v1",
            "status": "SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED", "ledger_snapshot": spec["ledger_snapshot"],
            "complete": spec["complete"], "producers": result, "ledger_mutations": 0,
            "artifact_hash_read_bytes": read_bytes,
            "fit_objects_loaded": 0, "future_truth_read": False, "article_publication_authorized": False}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--contract", required=True, type=Path)
    p.add_argument("--sha256", required=True)
    args = p.parse_args(argv)
    require(args.contract.stat().st_size <= 1024**2 and sha(args.contract) == args.sha256, "bounded contract digest")
    spec = json.loads(args.contract.read_text())
    pin(spec["controller_source"], 1024**2)
    require(spec["controller_source"]["path"] == str(ROOT/"application/scripts/forecast_transition_control.py"),
            "exact reviewed read-only controller implementation")
    print(json.dumps(collect(spec, load_controller()), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, ValueError, RuntimeError, sqlite3.Error) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
