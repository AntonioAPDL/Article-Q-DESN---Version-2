#!/usr/bin/env python3
"""Muscat-only, finite, no-retry execution of the sixteen frozen GloFAS tasks.

``plan`` is read-only. ``run --execute`` additionally needs an externally pinned
master grant explicitly authorizing deterministic ready-task authorizations.
The master is not a substitute for source activation or measured qualification.
No scientific setting is optimized here; nonconvergence stops further admission.
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("transition_control", ROOT / "application/scripts/forecast_transition_control.py")
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)
TAUS = ("005", "020", "035", "050", "065", "080", "095")
TASK_IDS = tuple("gft-" + family + "-p" + tau for family in ("al", "exal") for tau in TAUS) + ("gft-mq-al", "gft-mq-exal")


def dependencies(task_id):
    if task_id.startswith("gft-mq-"):
        return ["gft-" + task_id[7:] + "-p" + tau for tau in TAUS]
    family, tau = task_id[4:].split("-p")
    if family == "exal":
        return ["gft-al-p" + tau]
    parent = {"005": "020", "020": "035", "035": "050", "065": "050", "080": "065", "095": "080"}
    return [] if tau == "050" else ["gft-al-p" + parent[tau]]


def private(path, create=False):
    path = Path(path).absolute()
    C.require(not any(p.is_symlink() for p in (path, *path.parents)), "nonsymlink private path")
    C.require(not path.is_relative_to(ROOT) and len(path.parts) >= 4, "external task-scope state directory")
    if create and not path.exists():
        path.mkdir(mode=0o700)
    C.require(path.is_dir() and path.stat().st_uid == os.getuid() and path.stat().st_mode & 0o077 == 0,
              "existing owner-only external state directory")
    return path


def pinned(path, digest):
    path = Path(path)
    C.require(path.is_file() and not any(p.is_symlink() for p in (path, *path.parents)) and
              path.stat().st_size <= 1024 ** 2 and C.valid_hash(digest) and
              C.file_sha256(path) == digest, "bounded pinned regular input: " + str(path))
    return C.read_json(path)


def validate(master, prepared, now=None):
    now = now or C.utc_now()
    if "master_grant_path" in master:
        pinned(master["master_grant_path"], master["master_sha256"])
    C.require(master.get("schema_version") == "glofas_transition_campaign_master_v1" and
              master.get("authorize_derived_ready_wave_authorizations") is True and
              master.get("authorize_live_resource_observation") is True and
              master.get("allow_launch") is True and master.get("approved_by"), "explicit external cohort authority")
    C.require(C.parse_utc(master["expires_utc"]) > now, "master expired; no auto-renewal")
    for field in ("max_workers", "poll_seconds", "max_driver_wall_seconds", "resource_ttl_seconds"):
        C.positive_int(master[field], field)
    C.require(master["host"] == "muscat" and master["logical_cpus"] == [24, 25] and
              1 <= master["max_workers"] <= 2, "Muscat-only two-core cohort")
    C.require(isinstance(master["campaign_id"], str) and 1 <= len(master["campaign_id"]) <= 128 and
              all(c.isalnum() or c in "_-" for c in master["campaign_id"]), "bounded cohort identity")
    C.require(set(master["templates"]) == set(TASK_IDS) == set(master["task_budgets"]), "exact sixteen-task cohort")
    C.require(C.git_identity(ROOT) == (master["source_commit"], master["source_tree"], True), "clean pinned source")
    receipt = pinned(prepared / "PREPARED_NO_LAUNCH.json", master["preparation_sha256"])
    for name in ("source_commit", "source_tree", *C.HASH_FIELDS):
        C.require(receipt[name] == master[name], "prepared/master identity: " + name)
    C.require(master["qualified_host"]["output_root"] == str(prepared / "results"), "qualified prepared results root")
    C.require(0 < master["poll_seconds"] <= 60 and 0 < master["max_driver_wall_seconds"] and
              0 < master["resource_ttl_seconds"] <= 300, "finite monitoring/observation limits")
    C.require(0 < master["max_cpu_busy_fraction"] <= .25, "conservative live CPU health threshold")
    C.positive_int(master["measured_peak_worker_rss_bytes"], "qualified measured worker RSS")
    templates = {}
    for tid in TASK_IDS:
        pins = master["templates"][tid]
        request = pinned(prepared / "requests" / (tid + ".template.json"), pins["request_sha256"])
        task = pinned(prepared / "control_tasks" / (tid + ".template.json"), pins["control_sha256"])
        C.require(request["allow_launch"] is False and task["task_id"] == request["task_id"] == tid,
                  "immutable no-launch template identity")
        C.require([p["task_id"] for p in task["prerequisites"]] == dependencies(tid), "frozen median-outward DAG")
        for name in ("source_commit", "source_tree", *C.HASH_FIELDS):
            C.require(task[name] == request[name] == master[name], "template/source target drift")
        budget = master["task_budgets"][tid]
        for field in ("memory_bytes", "wall_seconds", "cpu_seconds", "output_bytes", "metadata_bytes"):
            C.positive_int(budget[field], field)
        C.require(budget["workers"] == budget["cpus"] == 1 and budget["cpu_seconds"] >= budget["wall_seconds"],
                  "one-thread finite full-worker reservation")
        C.require(budget["memory_bytes"] % 1024 ** 2 == 0 and budget["metadata_bytes"] >= 1024 ** 2,
                  "exact MiB worker bound and administrative headroom")
        C.require(budget["log_bytes"] == budget["output_bytes"] and
                  budget["total_output_bytes"] == 2 * budget["output_bytes"] + budget["metadata_bytes"], "complete output reservation")
        templates[tid] = (request, task)
    for field in C.BUDGET_FIELDS:
        total = (16 if field == "submissions" else sum((2 * b[field] if field == "output_bytes" else b[field])
                 for b in master["task_budgets"].values()))
        C.require(total <= master["budget"]["max_" + field], "whole-cohort price: " + field)
    C.require(sum(b["metadata_bytes"] for b in master["task_budgets"].values()) >= 1024 ** 2,
              "cohort includes bounded administrative storage")
    return templates


def ready(templates, accepted, attempted):
    return [tid for tid in TASK_IDS if tid not in attempted and all(dep in accepted for dep in dependencies(tid))]


def observe(master, prepared, cpu):
    def ticks():
        return {int(p[0][3:]): list(map(int, p[1:9])) for line in Path("/proc/stat").read_text().splitlines()
                if (p := line.split()) and p[0] == "cpu" + str(cpu)}
    first = ticks(); time.sleep(.25); second = ticks()
    delta = [b - a for a, b in zip(first[cpu], second[cpu])]
    load = 1 - (delta[3] + delta[4]) / max(1, sum(delta))
    C.require(load <= master["max_cpu_busy_fraction"], "admitted core busy; stop, not retune/reassign")
    topology = []
    for path in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/topology/core_id"):
        topology.append({"cpu": int(path.parent.parent.name[3:]), "core": int(path.read_text()),
                         "socket": int((path.parent / "physical_package_id").read_text())})
    mem = {line.split(":")[0]: int(line.split()[1]) * 1024 for line in Path("/proc/meminfo").read_text().splitlines()}
    disk = os.statvfs(prepared / "results")
    return {"host": "muscat", "observed_utc": C.timestamp(C.utc_now()),
            "expires_utc": C.timestamp(C.utc_now() + dt.timedelta(seconds=master["resource_ttl_seconds"])),
            "cpu_topology": topology, "reserved_logical_cpus": master["reserved_logical_cpus"],
            "available_memory_bytes": mem["MemAvailable"], "free_disk_bytes": disk.f_bavail * disk.f_frsize,
            "measured_peak_worker_rss_bytes": master["measured_peak_worker_rss_bytes"],
            "observed_cpu": cpu, "observed_busy_fraction": load,
            "ownership_basis": "external exact core grant; utilization is only a health observation"}


def freeze(tid, templates, accepted, master, state, cpu, resource, grant):
    request, task = copy.deepcopy(templates[tid])
    task.pop("status", None)  # the launchable derivative is not a preparation-only status marker
    prereqs = []
    for parent in dependencies(tid):
        packet = accepted[parent]
        fits = [a for a in packet["artifacts"] if a["relative_path"] == "fit.rds"]
        C.require(len(fits) == 1 and packet["manifest"]["numerical_gates_pass"] is True, "accepted finite/converged parent")
        prereqs.append({"task_id": parent, "fit_path": fits[0]["path"], "fit_sha256": fits[0]["sha256"]})
    budget = dict(master["task_budgets"][tid], logical_cpus=[cpu])
    route = master["campaign_id"] + "." + tid
    request.update(prerequisites=prereqs, routing_id=route, host="muscat", ledger_path=str(state / "ledger.sqlite"),
                   controller_python=master["qualified_host"]["python_bin"], resource_budget={"max_threads": 1,
                   "max_memory_mb": budget["memory_bytes"] // 1024 ** 2, "max_wall_seconds": budget["wall_seconds"],
                   "max_output_bytes": budget["output_bytes"]})
    task.update(routing_id=route, routing_revision=1, request_spec_sha256=C.request_spec_sha256(request))
    paths = {name: state / (tid + "." + name + ".json") for name in ("request", "task", "authorization", "ticket", "resource", "budget")}
    argv = C.worker_argv(master["config"], "muscat", task, request, paths["request"], paths["ticket"],
        paths["authorization"], state / "ledger.sqlite", Path(request["source_manifest_path"]), ROOT, "0" * 64)
    task["dispatch_argv_sha256"] = C.argv_spec_sha256(argv)
    C.validate_task(task)
    auth = {"schema_version": "forecast_transition_authorization_v1", "allow_launch": True,
        "approved_by": "coordinator under master " + master["campaign_id"] + "; " + master["approved_by"],
        "master_grant_path": master["master_grant_path"], "master_grant_sha256": master["master_sha256"],
        "expires_utc": master["expires_utc"],
        "allowed_task_ids": [tid], "allowed_hosts": ["muscat"],
        "allowed_operations": ["claim", "dispatch", "record_terminal", "accept"],
        "allowed_task_sha256": {tid: C.object_sha256(task)}, "config_sha256": master["config_sha256"],
        "qualified_hosts": {"muscat": master["qualified_host"]}, "budget": master["budget"],
        "resource_receipt_sha256": {"muscat": C.object_sha256(resource)},
        "resource_grants": {grant["grant_id"]: C.object_sha256(grant)},
        **{name: task[name] for name in ("source_commit", "source_tree", *C.HASH_FIELDS)}}
    for key, value in (("request", request), ("task", task), ("authorization", auth), ("resource", resource), ("budget", budget)):
        C.durable_json(paths[key], value, max_bytes=1024 ** 2)
    return paths, auth


def independent_proof(terminal, row):
    C.require(terminal["host"] == "muscat" and terminal["job_id"] == row["job_id"], "exact locally dispatched supervisor")
    own, child = terminal["supervisor_identity"], terminal["child_identity"]
    boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    C.require(own["boot_id"] == child["boot_id"] == boot and terminal["job_id"] ==
              "pid:%s:%s:%s" % (own["pid"], boot, own["start_ticks"]), "boot/start identity versus ledger")
    observed = []
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            text = path.read_text(); fields = text[text.rfind(")") + 2:].split(); pid = int(path.parent.name)
        except FileNotFoundError:
            continue
        # A reaped/zombie process cannot execute; any live old session/group or exact owner blocks acceptance.
        relevant = pid in (own["pid"], child["pid"]) or int(fields[2]) in (own["pid"], child["pid"]) or int(fields[3]) in (own["pid"], child["pid"])
        if relevant:
            observed.append({"pid": pid, "state": fields[0], "start_ticks": int(fields[19]), "pgrp": int(fields[2]), "session": int(fields[3])})
    C.require(not any(x["state"] != "Z" for x in observed), "live supervisor/worker/session remains; wait")
    evidence = {"boot_id": boot, "observed_utc": C.timestamp(C.utc_now()), "processes": observed,
                "terminal_receipt_sha256": C.object_sha256(terminal)}
    return {"claim_nonce": row["nonce"], "host": "muscat", "job_id": row["job_id"], "owner_terminated": True,
            "accounting_complete": terminal.get("accounting_complete") is True, "no_orphans": True,
            "supervisor_receipt_sha256": C.object_sha256(terminal), "evidence_sha256": C.object_sha256(evidence),
            "independent_observation": evidence}


def ledger_for(master, state, tid):
    auth_path = state / (tid + ".authorization.json")
    auth, sha = C.load_authorization(auth_path, C.file_sha256(auth_path), ROOT)
    authority = C.Authority(master["config"], master["config_sha256"], auth, sha, C.git_identity(ROOT))
    return C.Ledger(state / "ledger.sqlite", authority)


def administrative_bytes(state, master):
    paths = list(state.rglob("*"))
    C.require(not any(path.is_symlink() for path in paths), "no state namespace symlinks")
    used = sum(path.stat().st_size for path in paths if path.is_file() and not path.name.endswith(".stdout.log"))
    C.require(used <= sum(b["metadata_bytes"] for b in master["task_budgets"].values()), "whole-cohort metadata byte ceiling")


def admission_time(master, entry, tid, now=None):
    end = C.parse_utc(entry["created_utc"]) + dt.timedelta(seconds=master["max_driver_wall_seconds"])
    C.require((now or C.utc_now()) + dt.timedelta(seconds=master["task_budgets"][tid]["wall_seconds"] + 240) <= end,
              "late admission exceeds authority/lifetime including dispatch/cleanup/poll reserve")


def run(master, prepared, templates, state, grant_path):
    C.require(socket.gethostname().split(".")[0].lower() == "muscat", "actual Muscat coordinator only")
    C.require(master["config"]["launch_authorized"] is True, "source launch switch remains false")
    for field in C.BUDGET_FIELDS:
        C.require(master["budget"]["max_" + field] <= master["config"]["production_budget"]["max_" + field],
                  "whole-cohort authority exceeds source price ceiling: " + field)
    C.require(str(grant_path.absolute()) == master["resource_grant_path"], "exact master-pinned resource grant path")
    grant = pinned(grant_path, master["resource_grant_sha256"])
    C.require(grant["logical_cpus"] == [24, 25] and grant["max_workers"] <= 2, "exact separately granted cohort cores")
    metadata = private(master["qualified_host"]["metadata_root"])
    C.require(metadata == state / "metadata", "dedicated qualified cohort metadata")
    source_manifest = Path(master["source_manifest_path"])
    rows = C.verify_file_manifest(ROOT, source_manifest, master["source_manifest_sha256"], source=True)
    C.verify_production_config(Path(master["config_path"]), ROOT, rows, master["config_sha256"])
    C.verify_file_manifest(prepared, prepared / "manifests/input_manifest.csv", master["input_manifest_sha256"])
    entry_path = state / "CAMPAIGN.json"
    if not entry_path.exists():
        C.durable_json(entry_path, {"master_sha256": master["master_sha256"], "created_utc": C.timestamp(C.utc_now())})
    entry = C.read_json(entry_path)
    C.require(entry["master_sha256"] == master["master_sha256"], "no master replacement/auto-renewal on resume")
    end = C.parse_utc(entry["created_utc"]) + dt.timedelta(seconds=master["max_driver_wall_seconds"])
    C.require(all(C.parse_utc(record["expires_utc"]) >= end for record in
              (master, grant, master["qualified_host"])), "master/grant/qualification must cover the finite cohort lifetime")
    accepted_cache = {}
    stopped = (state / "STOP_ADMISSION.json").exists()
    while True:
        elapsed = (C.utc_now() - C.parse_utc(entry["created_utc"])).total_seconds()
        C.require(0 <= elapsed < master["max_driver_wall_seconds"], "driver wall budget exhausted; workers retain finite supervisors")
        validate(master, prepared)  # recheck expiry, source, and immutable templates before every admission wave
        administrative_bytes(state, master)
        accepted, attempted, active = {}, set(), []
        for tid in TASK_IDS:
            if not (state / (tid + ".authorization.json")).exists():
                continue
            ledger = ledger_for(master, state, tid)
            try:
                attempts = ledger.attempts(tid)
                C.require(len(attempts) <= 1, "no retries or multiple owners in cohort")
                if not attempts:
                    C.require(False, "frozen predispatch packet without owner; manual reconciliation required")
                row = attempts[0]; attempted.add(tid)
                if row["state"] in ("submitted", "submission_ambiguous"):
                    terminal_path = metadata / (row["nonce"] + ".terminal.json")
                    if terminal_path.exists():
                        terminal = C.read_json(terminal_path)
                        C.require(terminal.get("schema_version") == "forecast_transition_supervisor_receipt_v1" and
                            terminal.get("claim_nonce") == row["nonce"] and terminal.get("job_id") == row["job_id"] and
                            terminal.get("identity") == {key: ledger.task(tid)[key] for key in C.IDENTITY_FIELDS} and
                            C.file_sha256(row["intent_path"]) == row["intent_sha"] and terminal.get("worker_argv_sha256") ==
                            C.object_sha256(C.read_json(row["intent_path"])["argv"]), "authenticated terminal before admission decision")
                        if terminal.get("exit_code") != 0:
                            stopped = True
                        try:
                            proof = independent_proof(terminal, row)
                        except C.GateError as error:
                            if "live supervisor/worker/session" not in str(error):
                                raise
                        else:
                            proof_path = state / (row["nonce"] + ".proof.json")
                            if proof_path.exists():
                                retained = C.read_json(proof_path)
                                C.require(retained["supervisor_receipt_sha256"] == proof["supervisor_receipt_sha256"] and
                                          retained["claim_nonce"] == proof["claim_nonce"], "retained independent proof identity")
                                proof = retained
                            else:
                                C.durable_json(proof_path, proof)
                            ledger.close_supervised(row["nonce"], terminal, proof)
                            row["state"] = ledger.row(row["nonce"])["state"]
                if row["state"] == "succeeded":
                    root = Path(row["ticket"]["output_root"])
                    ledger.accept(row["nonce"], C.read_json(str(root) + ".output_manifest.json"), root)
                    row["state"] = "accepted"
                if row["state"] == "accepted":
                    if tid not in accepted_cache:
                        accepted_cache[tid] = ledger.accepted_output(tid)
                    accepted[tid] = accepted_cache[tid]
                else:
                    if row["state"] == "failed":
                        stopped = True
                    else:
                        C.require(row["state"] == "submitted", "ambiguous/unsubmitted owner needs manual reconciliation; no retry")
                        active.append(row)
            finally:
                ledger.close()
        if len(accepted) == 16:
            for tid in TASK_IDS:
                ledger = ledger_for(master, state, tid)
                try:
                    accepted[tid] = ledger.accepted_output(tid)
                finally:
                    ledger.close()
            complete = {"status": "COHORT_COMPLETE_NOT_ARTICLE_PROMOTION", "master_sha256": master["master_sha256"],
                        "accepted": {k: v["output_manifest_sha256"] for k, v in accepted.items()}}
            if (state / "COMPLETE.json").exists():
                C.require(C.read_json(state / "COMPLETE.json") == complete, "retained completion identity")
            else:
                C.durable_json(state / "COMPLETE.json", complete)
            return
        if stopped:
            if not (state / "STOP_ADMISSION.json").exists():
                C.durable_json(state / "STOP_ADMISSION.json", {"master_sha256": master["master_sha256"], "reason": "worker failure; no retuning or retry"})
            C.require(active, "admission stopped after failure; workers now terminal; manual review required")
            time.sleep(master["poll_seconds"])
            continue
        used = {cpu for row in active for cpu in row["budget"]["logical_cpus"]}
        available = [cpu for cpu in (24, 25) if cpu not in used]
        for tid, cpu in zip(ready(templates, accepted, attempted)[:max(0, master["max_workers"] - len(active))], available):
            admission_time(master, entry, tid)
            for parent in dependencies(tid):
                ledger = ledger_for(master, state, parent)
                try:
                    accepted[parent] = ledger.accepted_output(parent)  # fresh parent bytes immediately before derivation
                finally:
                    ledger.close()
            resource = observe(master, prepared, cpu)
            paths, auth = freeze(tid, templates, accepted, master, state, cpu, resource, grant)
            argv = [master["qualified_host"]["python_bin"], str(ROOT / "application/scripts/forecast_transition_control.py"),
                "dispatch", "--execute", "--config", master["config_path"], "--host", "muscat", "--source-root", str(ROOT),
                "--source-manifest", str(source_manifest), "--ledger", str(state / "ledger.sqlite"), "--owner", master["campaign_id"],
                "--intent-directory", str(metadata), "--grant", str(grant_path)]
            for key, flag in (("task", "task"), ("request", "request"), ("ticket", "ticket"),
                              ("authorization", "authorization"), ("resource", "resource-receipt"), ("budget", "budget")):
                argv += ["--" + flag, str(paths[key])]
            subprocess.run(argv + ["--authorization-sha256", C.file_sha256(paths["authorization"])], check=True,
                           timeout=120, env=C.clean_process_environment(), cwd=ROOT)
        time.sleep(master["poll_seconds"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("plan", "run"))
    parser.add_argument("--master-grant", required=True, type=Path)
    parser.add_argument("--master-sha256", required=True)
    parser.add_argument("--prepared-root", required=True, type=Path)
    parser.add_argument("--state-root", required=True, type=Path)
    parser.add_argument("--resource-grant", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args(argv)
    master = pinned(args.master_grant, args.master_sha256)
    C.require(not args.master_grant.resolve().is_relative_to(ROOT), "external master grant only")
    prepared = args.prepared_root.resolve(strict=True)
    master["master_sha256"] = args.master_sha256
    master["master_grant_path"] = str(args.master_grant.resolve())
    master["config"] = pinned(master["config_path"], master["config_sha256"])
    templates = validate(master, prepared)
    C.require(master["state_root"] == str(args.state_root.absolute()), "master binds exact external state root")
    if args.mode == "plan":
        C.require(not args.execute, "plan cannot execute")
        print(json.dumps({"status": "PLAN_ONLY_NO_WRITES_NO_JOBS", "tasks": 16,
              "initial_ready": ready(templates, {}, set()), "max_workers": master["max_workers"]}, sort_keys=True))
        return 0
    C.require(args.execute, "run requires explicit --execute")
    state = private(args.state_root, create=True)
    run(master, prepared, templates, state, args.resource_grant)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (C.GateError, OSError, subprocess.SubprocessError, KeyError, ValueError) as error:
        print("GLOFAS_CAMPAIGN_STOPPED: " + str(error), file=sys.stderr)
        raise SystemExit(2)
