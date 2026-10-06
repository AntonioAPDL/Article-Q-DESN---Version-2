"""Execution-only recovery helpers; no model or forecast implementation."""
from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import time


def digest(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")
    temporary.replace(path)


def immutable(path, value):
    if Path(path).exists():
        if read(path) != value:
            raise RuntimeError(f"recovery identity changed: {path}")
    else:
        write(path, value)


def rows(path):
    with Path(path).open(newline="") as handle:
        return list(csv.DictReader(handle))


def audit_ridge(prep, campaign, expected):
    prep, campaign = Path(prep), Path(campaign)
    manifest = rows(prep / "execution_manifest.csv") + rows(campaign / "seed3/manifest.csv")
    if len(manifest) != expected or len({r["fit_id"] for r in manifest}) != expected:
        raise RuntimeError("completed screening manifest is incomplete or duplicated")
    evidence, fitted, rejected = {}, 0, 0
    for row in manifest:
        root = campaign / "ridge/fits" / row["fit_id"]
        terminal, exclusion = root / "terminal.json", root / "rejected_washout.json"
        if terminal.exists() and exclusion.exists():
            raise RuntimeError(f"ambiguous screening result: {root}")
        if terminal.is_file():
            value = read(terminal)
            if (value.get("status") != "completed_r123_ridge_cell"
                    or value.get("fit_sha256") != row["fit_sha256"]
                    or value.get("test_opened") is not False):
                raise RuntimeError(f"screening target/identity differs: {root}")
            if set(value["output_sha256"]) != {"contract.json", "training_statistics.npz", "validation_metrics.csv"}:
                raise RuntimeError(f"unexpected screening artifacts: {root}")
            evidence[str(terminal)] = digest(terminal)
            for name, wanted in value["output_sha256"].items():
                if digest(root / name) != wanted:
                    raise RuntimeError(f"completed screening artifact changed: {root / name}")
                evidence[str(root / name)] = wanted
            fitted += 1
        elif exclusion.is_file():
            if read(exclusion).get("passed") is not False:
                raise RuntimeError(f"invalid washout exclusion: {root}")
            evidence[str(exclusion)] = digest(exclusion); rejected += 1
        else:
            raise RuntimeError(f"unprocessed screening cell: {root}")
    return {"cells": len(manifest), "fitted": fitted, "washout_excluded": rejected,
            "evidence_sha256": evidence, "screening_refits_authorized": False}


def verify_evidence(ledger):
    for name, wanted in ledger["evidence_sha256"].items():
        if digest(name) != wanted:
            raise RuntimeError(f"preserved screening evidence changed: {name}")


def remaining_primary_fits(campaign):
    campaign = Path(campaign)
    normal = sum(len(list((campaign / f"rhs/{label}/fits").glob("*/terminal.json")))
                 for label in ("center", "pilot"))
    al = len(list((campaign / "al_internal").glob("*/split=*/quantiles/al/tau=*/terminal.json")))
    if normal > 150 or al > 63: raise RuntimeError("unexpected primary fit inventory")
    return {"normal_completed": normal, "normal_remaining": 150 - normal,
            "al_completed": al, "al_remaining": 63 - al, "remaining_primary_fits": 213 - normal - al}


def archive_metadata(campaign, attempt, current_log=None):
    campaign, attempt = Path(campaign), Path(attempt)
    sources = set(campaign.glob("*.json")) | set(campaign.glob("controller_attempt*.log"))
    sources.update(p for p in campaign.rglob("*progress.json")
                   if not p.is_relative_to(campaign / "attempts"))
    for name in ("pilot/ranking.csv", "broad/ranking.csv", "seed3/ranking.csv",
                 "seed3/manifest.csv", "operators/terminal.json", "operators/matched_metrics.csv"):
        if (campaign / name).is_file(): sources.add(campaign / name)
    copied = {}
    for source in sorted(sources):
        if current_log is not None and source.resolve() == Path(current_log).resolve(): continue
        if source.stat().st_size > 20 * 2**20:
            raise RuntimeError(f"metadata archive unexpectedly large: {source}")
        relative = source.relative_to(campaign); target = attempt / "previous_metadata" / relative
        wanted = digest(source)
        if target.exists():
            if digest(target) != wanted:
                raise RuntimeError(f"previous-attempt snapshot differs: {target}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        if digest(target) != wanted: raise RuntimeError(f"metadata copy differs: {target}")
        copied[str(relative)] = wanted
    immutable(attempt / "previous_metadata_identity.json", copied)
    return copied


def clear_archived_block(campaign, attempt, archive):
    marker = Path(campaign) / "blocked.json"
    if not marker.exists(): return
    if archive.get("blocked.json") != digest(marker):
        raise RuntimeError("blocked marker changed after the recovery audit")
    backup = Path(attempt) / "previous_metadata/blocked.json"
    if digest(backup) != archive["blocked.json"]:
        raise RuntimeError("blocked marker has no verified archive")
    write(Path(attempt) / "resolved_previous_block.json", {
        "archived_path": str(backup), "sha256": archive["blocked.json"],
        "resolved_at_epoch": time.time(), "scientific_outputs_removed": False})
    marker.unlink()


class FreshPoolPreflight:
    """Reselect from the initial permitted mask, never from a previously pinned pool."""

    def __init__(self, original, permitted, attempt, protocol, campaign, archive):
        self.original = original; self.permitted = set(permitted)
        self.attempt = Path(attempt); self.protocol = protocol
        self.campaign = Path(campaign); self.archive = archive; self.gates = []

    def __call__(self, args, control):
        if not self.permitted: raise RuntimeError("empty permitted CPU mask")
        for number in range(1, self.protocol["resource_attempts"] + 1):
            os.sched_setaffinity(0, self.permitted)
            try:
                cpus = self.original(args, control)
                if (len(cpus) != args.workers or len(set(cpus)) != len(cpus)
                        or not set(cpus).issubset(self.permitted)):
                    raise RuntimeError("resource gate returned an invalid CPU pool")
                os.sched_setaffinity(0, set(cpus))
                gate = {"gate": len(self.gates) + 1, "resource_attempt": number,
                        "cpus": cpus, "permitted_cpus": sorted(self.permitted),
                        "at_epoch": time.time(), "statistical_contract_changed": False}
                self.gates.append(gate); write(self.attempt / "resource_gates.json", self.gates)
                if len(self.gates) == 1: clear_archived_block(self.campaign, self.attempt, self.archive)
                write(self.attempt / "live.json", {"status": "STARTING" if len(self.gates) == 1 else "FITTING",
                      "pid": os.getpid(), "cpus": cpus, "gate": len(self.gates), "updated_at_epoch": time.time()})
                running = self.campaign / "running.json"
                if running.exists() and read(running).get("pid") == os.getpid():
                    value = read(running); value.update(cpus=cpus, recovery_attempt=str(self.attempt))
                    write(running, value)
                return cpus
            except RuntimeError as error:
                if not str(error).startswith("only "): raise
                write(self.attempt / "live.json", {"status": "WAITING_FOR_IDLE_CORES", "pid": os.getpid(),
                      "resource_attempt": number, "error": str(error), "updated_at_epoch": time.time()})
                if number == self.protocol["resource_attempts"]: raise
                time.sleep(self.protocol["resource_backoff_seconds"])


class ResumeQueue:
    """Keep the frozen queue implementation, but prohibit screening refits."""

    def __init__(self, original, attempt):
        self.original = original; self.attempt = Path(attempt); self.events = []

    def __call__(self, tasks, cpus, code, progress_path, expected_total, **kwargs):
        for identifier, command, log in tasks:
            if "--mode" in command and command[command.index("--mode") + 1] == "ridge-cell":
                raise RuntimeError(f"recovery refuses a screening refit: {identifier}")
        self.events.append({"progress_path": str(progress_path), "scheduled": len(tasks),
                            "expected_total": expected_total, "cpus": cpus, "at_epoch": time.time()})
        write(self.attempt / "queue_events.json", self.events)
        return self.original(tasks, cpus, code, progress_path, expected_total, **kwargs)
