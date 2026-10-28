"""One authoritative Muscat registry for new qualification tasks.

This registry never adopts, migrates or releases existing baseline/EE grants.
Other machines may return artifacts, but only this controller writes claims.
"""
from __future__ import annotations
from contextlib import contextmanager
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import socket
import time
import uuid

SCHEMA = "pricefm-hb-qualification-v1"
KINDS = {"environment", "parity"}
FINAL = {"COLLECTED", "FAILED_RECONCILED"}


def budget_policy(state):
    """Validate the full finite amendment chain and every retained old charge."""
    policy={"max_attempts":3,"max_reserved_CPU_seconds":3300}
    steps={"DEFAULT_CHANNEL_UNACCEPTED_USE_CONDA_FORGE":(3,3300,4,4500),
           "REFERENCE_CPU_PROFILE_SANDYBRIDGE":(4,4500,5,5400)}
    records=state.get("budget_amendments",[])
    if not isinstance(records,list) or len(records)>2:raise ValueError("invalid amendment chain")
    for record in records:
        document=record["document"];step=steps.get(document.get("reason_code"))
        if (step is None or record["sha256"]!=identity(document) or document.get("from")!=policy or
                document.get("controller")!=socket.getfqdn() or
                document.get("to")!={"max_attempts":step[2],"max_reserved_CPU_seconds":step[3]} or
                (policy["max_attempts"],policy["max_reserved_CPU_seconds"])!=step[:2]):
            raise ValueError("invalid finite amendment record")
        ids=document["carried_scope_ids"]
        if not isinstance(ids,list) or ids!=sorted(set(ids)) or not set(ids)<=set(state["scopes"]):
            raise ValueError("invalid carried scope identities")
        carried={key:state["scopes"][key] for key in ids}
        if identity(carried)!=document["carried_scopes_sha256"]:
            raise ValueError("retained scope charges differ")
        if step[2]==5 and (sum(s["attempts"] for s in carried.values())!=4 or sum(s["reserved_CPU_seconds"] for s in carried.values())!=4500):
            raise ValueError("reference amendment must carry the exhausted four-attempt scope")
        for field in (("failure_evidence","reference_profile_evidence") if step[2]==5 else ("failure_evidence",)):
            evidence=document[field]
            if digest(evidence["path"])!=evidence["sha256"]:raise ValueError("amendment evidence changed")
        if step[2]==5 and document.get("numerical_profile")!="Sandybridge_AVX_v1":
            raise ValueError("unsupported numerical profile amendment")
        policy=document["to"]
    if state.get("budget_policy",{"max_attempts":3,"max_reserved_CPU_seconds":3300})!=policy:
        raise ValueError("parent budget needs its exact recorded amendment chain")
    return policy


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def identity(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for data in iter(lambda: f.read(1024*1024), b""):
            h.update(data)
    return h.hexdigest()


def read(path):
    def invalid(value):
        raise ValueError("nonfinite JSON: " + value)
    return json.loads(no_links(path).read_text(), parse_constant=invalid)


def no_links(path):
    p = Path(path).absolute()
    if any(q.is_symlink() for q in (p,) + tuple(p.parents)):
        raise ValueError("symlink path forbidden")
    return p


def write(path, value):
    path = no_links(path)
    tmp = path.with_name(path.name+".tmp-"+uuid.uuid4().hex)
    try:
        with tmp.open("xb") as f:
            f.write(canonical(value)+b"\n"); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, path)
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if tmp.exists(): tmp.unlink()


@contextmanager
def lock(path):
    path = no_links(path)
    with path.open("a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def validate_authority(a, now=None, hostname=None):
    if a.get("schema") != SCHEMA or a.get("purpose") != "QUALIFICATION_ONLY":
        raise ValueError("a separate qualification authority is required")
    if a.get("controller") != (hostname or socket.getfqdn()):
        raise ValueError("only the canonical controller may reserve tasks")
    if a.get("scientific_screening_authorized") is not False or type(a.get("official_origins")) is not int or a["official_origins"] != 0 or type(a.get("fits")) is not int or a["fits"] != 0:
        raise ValueError("this execution layer admits no screening or fitting")
    if type(a.get("max_attempts")) is not int or not 1 <= a["max_attempts"] <= 3 or type(a.get("max_concurrent")) is not int or a["max_concurrent"] != 1:
        raise ValueError("invalid qualification attempt/concurrency budget")
    ceiling = a.get("max_reserved_CPU_seconds")
    if type(ceiling) not in (int, float) or not math.isfinite(ceiling) or not 0 < ceiling <= 3600:
        raise ValueError("invalid finite CPU scope")
    expiry_dt = dt.datetime.fromisoformat(a["expires_utc"].replace("Z", "+00:00"))
    if expiry_dt.tzinfo is None:
        raise ValueError("timezone-aware expiry required")
    expiry = expiry_dt.timestamp()
    if expiry <= (time.time() if now is None else now):
        raise ValueError("qualification authority expired")
    if not isinstance(a.get("jobs"), dict) or not a["jobs"]:
        raise ValueError("nonempty admitted job list required")
    for kind, limits in a["jobs"].items():
        if kind not in KINDS or type(limits.get("cpus")) is not int or limits["cpus"] != 1 or type(limits.get("wall_seconds")) is not int or not 1 <= limits["wall_seconds"] <= 1800:
            raise ValueError("unsupported job/resources")
        if type(limits.get("memory_MiB")) is not int or not 1024 <= limits["memory_MiB"] <= 8192:
            raise ValueError("unreviewed memory request")
        for key in ("release_sha256", "task_sha256"):
            if not isinstance(limits.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", limits[key]):
                raise ValueError("admitted release/task pins required")
    return a


class Registry:
    def __init__(self, root):
        self.root = no_links(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.path = self.root / "registry.json"

    def snapshot(self):
        with lock(self.root/"registry.lock"):
            return read(self.path) if self.path.exists() else {"schema": SCHEMA, "scopes": {}, "claims": {}}

    def reserve(self, authority, task, release_sha256):
        validate_authority(authority)
        if task.get("kind") not in authority["jobs"] or task.get("namespace") != "TEST":
            raise ValueError("only the admitted TEST job classes may run")
        admitted = authority["jobs"][task["kind"]]
        if admitted["release_sha256"] != release_sha256 or admitted["task_sha256"] != identity(task):
            raise ValueError("release/task differs from its admitted immutable pins")
        expiry = dt.datetime.fromisoformat(authority["expires_utc"].replace("Z", "+00:00")).timestamp()
        if expiry-time.time() < admitted["wall_seconds"]+60:
            raise ValueError("whole job and cleanup no longer fit admitted calendar")
        key = identity(task)
        with lock(self.root/"registry.lock"):
            state = read(self.path) if self.path.exists() else {"schema": SCHEMA, "scopes": {}, "claims": {}}
            # This preparation has at most two intended jobs plus one explicitly
            # admitted replacement. Distinct scopes never erase earlier charges.
            policy=budget_policy(state)
            if sum(s["attempts"] for s in state["scopes"].values()) >= policy["max_attempts"] or sum(s["reserved_CPU_seconds"] for s in state["scopes"].values())+authority["jobs"][task["kind"]]["wall_seconds"] > policy["max_reserved_CPU_seconds"]:
                raise ValueError("whole-preparation budget exhausted")
            if key in state["claims"]:
                raise ValueError("task already claimed/spent; no automatic retry")
            if any(c["state"] not in FINAL for c in state["claims"].values()):
                raise ValueError("canonical qualification controller already has unresolved work")
            scope = state["scopes"].setdefault(authority["scope_id"], {
                "authority_sha256": identity(authority), "attempts": 0, "reserved_CPU_seconds": 0})
            if scope["authority_sha256"] != identity(authority):
                raise ValueError("authority changed; retain the previous scope and admit a distinct one")
            reserve = authority["jobs"][task["kind"]]["wall_seconds"]
            if scope["attempts"]+1 > authority["max_attempts"] or scope["reserved_CPU_seconds"]+reserve > authority["max_reserved_CPU_seconds"]:
                raise ValueError("qualification budget exhausted")
            claim = {"task_key": key, "task": task, "release_sha256": release_sha256,
                     "scope_id": authority["scope_id"], "authority_sha256": identity(authority),
                     "state": "RESERVED", "reserved_CPU_seconds": reserve,
                     "attempt_id": uuid.uuid4().hex, "created": time.time(), "events": []}
            scope["attempts"] += 1; scope["reserved_CPU_seconds"] += reserve
            state["claims"][key] = claim
            write(self.path, state)
            return claim

    def transition(self, key, expected, target, **fields):
        allowed = {"RESERVED": {"STAGED", "AMBIGUOUS"}, "STAGED": {"SUBMISSION_INTENT", "AMBIGUOUS"},
                   "SUBMISSION_INTENT": {"SUBMITTED", "AMBIGUOUS"}, "SUBMITTED": {"COLLECTED", "FAILED_RECONCILED"}}
        if target not in allowed.get(expected, set()):
            raise ValueError("unreviewed state transition")
        if set(fields) & {"task_key", "task", "scope_id", "authority_sha256", "release_sha256", "reserved_CPU_seconds", "attempt_id", "created", "events", "state"}:
            raise ValueError("immutable claim fields")
        with lock(self.root/"registry.lock"):
            state = read(self.path); claim = state["claims"][key]
            if claim["state"] != expected:
                raise ValueError("claim state changed; no repeated mutation")
            claim["events"].append({"from": expected, "to": target, "time": time.time()})
            claim.update(fields, state=target); write(self.path, state)
            return claim

    def poll(self, key):
        with lock(self.root/"registry.lock"):
            state = read(self.path); claim = state["claims"][key]
            if claim["state"] != "SUBMITTED" or time.time()-claim.get("last_poll", 0) < 300:
                raise ValueError("no submitted task or poll interval has not elapsed")
            claim["last_poll"] = time.time(); write(self.path, state)
            return claim

    def amend_channel_recovery_budget(self, document):
        """One explicit finite amendment; spent scopes/claims remain unchanged."""
        if (document.get("schema")!="r156-budget-amendment-v1" or document.get("controller")!=socket.getfqdn() or
                document.get("from")!={"max_attempts":3,"max_reserved_CPU_seconds":3300} or
                document.get("to")!={"max_attempts":4,"max_reserved_CPU_seconds":4500} or
                document.get("reason_code")!="DEFAULT_CHANNEL_UNACCEPTED_USE_CONDA_FORGE"):
            raise ValueError("unsupported finite budget amendment")
        evidence=document["failure_evidence"]
        if digest(evidence["path"])!=evidence["sha256"]:
            raise ValueError("failure evidence pin differs")
        with lock(self.root/"registry.lock"):
            state=read(self.path)
            if state.get("budget_policy",document["from"])!=document["from"] or state.get("budget_amendments"):
                raise ValueError("amendment already spent or parent policy differs")
            if any(c["state"] not in FINAL for c in state["claims"].values()):
                raise ValueError("unresolved work must retain its claim before amendment")
            if identity(state["scopes"])!=document["carried_scopes_sha256"]:
                raise ValueError("amendment must carry every exact prior scope and charge")
            if sorted(state["scopes"])!=document["carried_scope_ids"]:
                raise ValueError("amendment must retain every prior scope identity")
            state["budget_policy"]=document["to"]
            state["budget_amendments"]=[{"sha256":identity(document),"document":document,"time":time.time()}]
            write(self.path,state)
            return state["budget_policy"]

    def amend_reference_profile_budget(self, document):
        """One evidence-derived profile replay; original tolerances stay fixed."""
        if (document.get("schema")!="r156-budget-amendment-v1" or document.get("controller")!=socket.getfqdn() or
                document.get("from")!={"max_attempts":4,"max_reserved_CPU_seconds":4500} or
                document.get("to")!={"max_attempts":5,"max_reserved_CPU_seconds":5400} or
                document.get("reason_code")!="REFERENCE_CPU_PROFILE_SANDYBRIDGE" or
                document.get("numerical_profile")!="Sandybridge_AVX_v1"):
            raise ValueError("unsupported reference-profile amendment")
        for field in ("failure_evidence","reference_profile_evidence"):
            if digest(document[field]["path"])!=document[field]["sha256"]:raise ValueError("profile evidence differs")
        with lock(self.root/"registry.lock"):
            state=read(self.path)
            if budget_policy(state)!=document["from"] or len(state.get("budget_amendments",[]))!=1:
                raise ValueError("profile amendment already spent or parent differs")
            if any(c["state"] not in FINAL for c in state["claims"].values()):raise ValueError("unresolved work remains claimed")
            if sum(s["attempts"] for s in state["scopes"].values())!=4 or sum(s["reserved_CPU_seconds"] for s in state["scopes"].values())!=4500:
                raise ValueError("reference replay amendment requires the exact exhausted prior scope")
            if sorted(state["scopes"])!=document["carried_scope_ids"] or identity(state["scopes"])!=document["carried_scopes_sha256"]:
                raise ValueError("profile amendment must carry every prior scope")
            state["budget_policy"]=document["to"]
            state["budget_amendments"].append({"sha256":identity(document),"document":document,"time":time.time()})
            budget_policy(state);write(self.path,state)
            return state["budget_policy"]
