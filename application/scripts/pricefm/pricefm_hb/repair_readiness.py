"""Compile PriceFM repair evidence; this module cannot admit or execute a fit.

Only bounded JSON and tracked source bytes are read. No scientific payload,
installed runtime, queue, original certificate, or authority is modified.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import re
import stat
import subprocess
import time

MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_TASKS = 10000
MATRIX_SHA256 = "1918086fabbfa5d37bd1ff889c950ececf69cf0bf77bbc80fbd25744933111ea"
MANIFEST_SHA256 = "aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8"
NATIVE_HEAD = "4541f853e65bf16736e58509775f8c9cbe8b6ed2"
LEAN_NO3_COLLECTOR_SHA256 = "9b6d88237caf9738df2c790098fd16125db5355438172f26cd1cd590e4952df9"
LIMITS = {"beta_posterior_sd_rms": 1e-4, "covariance_whitened_rms": 1e-4,
          "elbo_relative": 1e-8, "predictor_rms": 1e-6,
          "rhs_joint_log_rates": 1e-6, "rhs_start_log_precision": 1e-6,
          "sigma_relative": 1e-6}
NO4_PREFIX = "iq_NO_4_r134_20feba695ede3ad5_t"
NO4_ORIGINAL = tuple(NO4_PREFIX + t + "_s" + str(s) + "_al0.50"
                     for t in ("9.653643731923e-05", "9.653643731923e-06")
                     for s in (1, 2))
NO4_NEW = tuple(NO4_PREFIX + "9.653643731923e-06_s3_al" + t
                for t in ("0.45", "0.55"))
REQUIRED_REGIONS = {"AT", "LT", "NO_3", "NO_4"}
AL_KINDS = {"al", "internal_al"}
CANONICAL_ROOTS = {
    "AT": "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns/pricefm_stage_r146_at_training_fallback_20261022",
    **{region: "/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/campaigns/pricefm_stage_r141_recovery_rollout_20261019__" + region
       for region in ("LT", "NO_3", "NO_4")},
}


class EvidenceError(ValueError):
    """A source binding or metadata invariant could not be proved."""


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def decode_json(raw):
    require(len(raw) <= MAX_JSON_BYTES, "metadata exceeds bounded JSON size")
    def reject(value):
        raise EvidenceError("nonfinite JSON constant: " + value)
    def finite_float(value):
        number = float(value)
        require(math.isfinite(number), "nonfinite JSON float")
        return number
    return json.loads(raw, object_pairs_hook=_pairs, parse_constant=reject, parse_float=finite_float)


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def physical_path(path):
    p = Path(path)
    require(p.is_absolute(), "source/output path must be absolute")
    require(".." not in p.parts, "parent traversal is prohibited")
    for ancestor in (p, *p.parents):
        require(not ancestor.is_symlink(), "symlink in evidence path: " + str(ancestor))
    return p


def _identity(s):
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


class Reader:
    """Own bounded metadata IO and its exact receipts; never follow symlinks."""
    def __init__(self, maximum_cpu=25.0, maximum_wall=300.0):
        self.cpu_start = self.cpu()
        self.started = time.monotonic()
        self.maximum_cpu = maximum_cpu
        self.maximum_wall = maximum_wall
        self.receipts = {}

    @staticmethod
    def cpu():
        own = resource.getrusage(resource.RUSAGE_SELF)
        children = resource.getrusage(resource.RUSAGE_CHILDREN)
        return own.ru_utime + own.ru_stime + children.ru_utime + children.ru_stime

    def check(self):
        require(self.cpu() - self.cpu_start < self.maximum_cpu, "administrative CPU bound reached")
        require(time.monotonic() - self.started < self.maximum_wall, "administrative wall bound reached")

    def read(self, binding, *, parsed=True):
        self.check()
        require(isinstance(binding, dict) and set(binding) >= {"path", "sha256"}, "missing source pin")
        p = physical_path(binding["path"])
        require(not parsed or p.suffix.lower() == ".json", "only JSON metadata may be parsed")
        require(parsed or p.suffix.lower() in {".json", ".py", ".r", ".c", ".md"},
                "scientific/binary payloads cannot be read by this compiler")
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            before = os.fstat(fd)
            require(stat.S_ISREG(before.st_mode), "evidence is not a regular file")
            require(before.st_size <= MAX_JSON_BYTES, "evidence exceeds size ceiling")
            with os.fdopen(os.dup(fd), "rb") as stream:
                raw = stream.read(MAX_JSON_BYTES + 1)
            after = os.fstat(fd)
        finally:
            os.close(fd)
        require(_identity(before) == _identity(after) and _identity(after) == _identity(physical_path(p).stat()),
                "evidence changed while read: " + str(p))
        require(len(raw) == before.st_size, "short/oversize evidence read")
        digest = hashlib.sha256(raw).hexdigest()
        require(digest == binding["sha256"], "source SHA256 mismatch: " + str(p))
        if "bytes" in binding:
            require(type(binding["bytes"]) is int and binding["bytes"] == len(raw), "source byte count mismatch")
        value = decode_json(raw) if parsed else None
        if "value" in binding:
            require(value == binding["value"], "captured parsed metadata differs from pinned bytes")
        receipt = dict(path=str(p), sha256=digest, bytes=len(raw), device=before.st_dev,
                       inode=before.st_ino, mtime_ns=before.st_mtime_ns, ctime_ns=before.st_ctime_ns)
        self.receipts[str(p)] = receipt
        return value if parsed else raw

    def cost(self):
        return dict(combined_administrative_CPU_seconds=self.cpu() - self.cpu_start,
                    wall_seconds=time.monotonic() - self.started,
                    maximum_CPU_seconds=self.maximum_cpu, maximum_wall_seconds=self.maximum_wall)


class SourceBoundRemoteReader:
    """Read parsed metadata captured by the exact reviewed standalone collector.

    This is intentionally labelled differently from local source-file readback.
    The reviewed collector hashes and parses the same remote bytes. Its entire
    output, source, successful run receipt and finite scope are pinned locally.
    """
    source_bound_remote = True

    def __init__(self, parent, capture_pin):
        self.parent, self.capture_pin = parent, capture_pin

    def read(self, binding):
        self.parent.check()
        require(set(binding) == {"path", "sha256", "bytes", "value"} and
                isinstance(binding["path"], str) and Path(binding["path"]).suffix == ".json" and
                re.fullmatch("[0-9a-f]{64}", binding["sha256"]) and
                type(binding["bytes"]) is int and 0 < binding["bytes"] <= 2 * 1024 ** 2 and
                isinstance(binding["value"], dict), "invalid reviewed remote metadata envelope")
        self.parent.receipts[binding["path"]] = dict(path=binding["path"], sha256=binding["sha256"], bytes=binding["bytes"],
            verification_mode="SOURCE_BOUND_REMOTE_COLLECTOR_CAPTURE_NOT_LOCAL_READBACK", capture_pin=self.capture_pin)
        return binding["value"]


def bind_remote_no3(spec, reader):
    require(spec["collector_source"]["sha256"] == LEAN_NO3_COLLECTOR_SHA256, "not the exact reviewed lean NO3 collector")
    reader.read(spec["collector_source"], parsed=False)
    captured, receipt, scope = (reader.read(spec[key]) for key in ("snapshot", "run_receipt", "scope"))
    require(type(receipt.get("returncode")) is int and receipt["returncode"] == 0 and
            receipt.get("source_sha256") == LEAN_NO3_COLLECTOR_SHA256 and receipt.get("payloads_or_new_science") == 0,
            "remote NO3 collector did not complete successfully")
    require(scope.get("source") == spec["collector_source"] and scope.get("max_SSH") == 1 and
            scope.get("remote_CPU_hard") == 20 and scope.get("models_payloads_or_mutations") == 0 and
            scope.get("allpriorfailurescostsandclocksretained") is True, "remote capture prospective scope differs")
    require(scope["issued_epoch"] <= captured["observed_epoch"] <= receipt["completed_epoch"] <= scope["expires_epoch"] and
            0 <= captured["CPU_seconds"] < 20 and 0 <= captured["wall_seconds"] < 60,
            "remote NO3 capture was outside its original finite scope")
    require(captured.get("capture_kind") == "SOURCE_BOUND_REMOTE_COLLECTOR_SNAPSHOT_NOT_LOCAL_READBACK" and
            set(captured["regions"]) == {"NO_3"} and captured.get("mutations") == 0 and captured.get("numerical_payloads_read") == 0,
            "not the exact source-bound NO3 metadata capture")
    return captured, SourceBoundRemoteReader(reader, spec["snapshot"])


def bind_AT_external(spec, tasks, reader):
    """Bind the R146 imported-stats prerequisite to its certified R140/R141 ridge.

    This is a lineage proof for one upstream ridge task, not an AL certificate
    or a claim about unregistered/future downstream branches.
    """
    name = "AT_r134_7a422c0c3473f81f"
    fallback = Path(CANONICAL_ROOTS["AT"])
    r141 = fallback.parent / "pricefm_stage_r141_recovery_rollout_20261019__AT"
    r140 = fallback.parent / "pricefm_stage_r140_frozen_all_region_rollout_20261018__AT"
    paths = {"r146_import": fallback / "prerequisite_import.json", "r141_import": r141 / "recovery_import.json",
             "ridge_task": r141 / "tasks" / (name + ".json"), "ridge_seal": r141 / "tasks_done" / name / "completed_evidence.json",
             "ridge_result": r141 / "tasks_done" / name / "result.json", "r140_ridge_task": r140 / "tasks" / (name + ".json"),
             "r140_ridge_seal": r140 / "tasks_done" / name / "completed_evidence.json",
             "r140_ridge_result": r140 / "tasks_done" / name / "result.json"}
    require(all(spec[k]["path"] == str(p) for k, p in paths.items()), "AT external lineage outside exact source roots")
    values = {k: reader.read(spec[k]) for k in paths}
    imported, origin = values["r146_import"], values["r141_import"]
    task, seal, result = values["ridge_task"], values["ridge_seal"], values["ridge_result"]
    require(imported.get("status") == "R146_CERTIFIED_TRAIN_ONLY_PREREQUISITES_IMPORTED" and
            imported.get("test_opened") is False and imported.get("al_fit_import_count") == 0 and
            imported.get("source_labels_preserved") is True and imported["r141_recovery_import_sha256"] == spec["r141_import"]["sha256"],
            "AT fallback import manifest differs")
    require(origin.get("status") == "R141_R140_PREREQUISITES_IMPORTED" and origin.get("region") == "AT" and
            origin.get("source_tag") == "pricefm_stage_r140_frozen_all_region_rollout_20261018", "AT original import manifest differs")
    original = origin["imported"][name]
    require(task.get("kind") == "ridge" and task.get("name") == name and task.get("region") == "AT" and not task.get("depends", []) and
            task == values["r140_ridge_task"] and seal == values["r140_ridge_seal"] and result == values["r140_ridge_result"],
            "AT external anchor is not the original dependency-free ridge")
    require(original["kind"] == "ridge" and original["source"] == str(r140 / "tasks_done" / name) and
            original["task_sha256"] == spec["ridge_task"]["sha256"] == spec["r140_ridge_task"]["sha256"] and
            original["completed_evidence_sha256"] == spec["ridge_seal"]["sha256"] == spec["r140_ridge_seal"]["sha256"] and
            spec["ridge_result"]["sha256"] == spec["r140_ridge_result"]["sha256"] and
            seal["metadata"]["certified"] is True and seal["metadata"]["source_head"] == origin["source_head"] and
            seal["metadata"]["task_sha256"] == spec["ridge_task"]["sha256"] and
            seal["artifacts"]["result.json"] == spec["ridge_result"]["sha256"], "AT ridge source/seal certification differs")
    require(result.get("candidate_id") == task["candidate_id"] and result.get("region") == "AT" and
            len(result.get("records", [])) == 3 and
            all(x.get("certified") is True and x.get("driver") == "deterministic_Normal_location_broad_proxy" for x in result["records"]),
            "AT external ridge logical role or saved certification differs")
    consumers = sorted(n for n, t in tasks.items() if name in t.get("depends", []))
    expected_consumers = ["stats_" + name + "_s" + str(i) for i in (1, 2, 3)]
    require(consumers == expected_consumers and sorted(x["name"] for x in spec["consumers"]) == consumers,
            "AT external consumer set differs")
    by_name = {x["name"]: x for x in imported["imports"]}
    for entry in spec["consumers"]:
        child = entry["name"]; declaration = tasks[child]
        require(declaration.get("kind") == "stats" and declaration.get("depends") == [name] and
                declaration.get("specification_sha256") == task["specification_sha256"], "AT stats scientific lineage differs")
        child_task = fallback / "tasks" / (child + ".json")
        child_seal = fallback / "tasks_done" / child / "completed_evidence.json"
        require(entry["task"]["path"] == str(child_task) and entry["seal"]["path"] == str(child_seal) and
                entry["source_seal"]["path"] == str(r141 / "tasks_done" / child / "completed_evidence.json"), "AT consumer source layout differs")
        require(reader.read(entry["task"]) == declaration, "AT imported consumer task differs")
        evidence, source_evidence = reader.read(entry["seal"]), reader.read(entry["source_seal"])
        record = by_name[child]
        require(evidence == source_evidence and evidence["metadata"]["certified"] is True and
                evidence["metadata"]["task_sha256"] == entry["task"]["sha256"] and
                record["source"] == str(r141 / "tasks_done" / child) and record["destination"] == str(fallback / "tasks_done" / child) and
                record["source_evidence_sha256"] == entry["seal"]["sha256"] == entry["source_seal"]["sha256"] and
                record["r141_import_record"] == origin["imported"][child] and
                record["r141_import_record"]["task_sha256"] == entry["task"]["sha256"], "AT imported stats source/seal proof differs")
    return dict(name=name, state="CERTIFIED_IMPORTED_UPSTREAM_RIDGE_LINEAGE_BOUND", consumers=consumers,
                logical_role="deterministic_Normal_location_broad_proxy_NOT_AL_FIT", numerical_payloads_read=0,
                source_pins={k: spec[k] for k in paths}, global_future_graph_completeness_claimed=False)


def certificate_state(terminal, certificate, contract):
    """Check saved metadata against the unchanged original acceptance formula.

    The human-readable status is intentionally unused. A failed original is
    never converted to an accepted replacement by this classifier.
    """
    require(contract.get("family") == "al" and terminal.get("family") == "al", "not an AL fit")
    require(contract.get("max_iter") == 300 and type(contract["max_iter"]) is int, "AL cap changed")
    require(contract.get("certificate_limits") == LIMITS and certificate.get("limits") == LIMITS,
            "original certificate limits changed")
    for item in (contract, terminal):
        require(item.get("prior_center_from_initializer") is False and item.get("test_opened") is False,
                "prior/test boundary changed")
    require(terminal.get("rhs_freeze_iters") == 0 and type(terminal["rhs_freeze_iters"]) is int,
            "RHS schedule changed")
    require(certificate.get("initialization_changes_prior") is False, "initialization changes prior")
    for key in ("tau", "tau0", "posterior_target_sha256"):
        require(terminal.get(key) == contract.get(key) and key in contract, "target identity changed: " + key)
    require(type(contract["tau"]) in (float, int) and math.isfinite(contract["tau"]) and 0 < contract["tau"] < 1,
            "invalid quantile identity")
    require(type(contract["tau0"]) in (float, int) and math.isfinite(contract["tau0"]) and contract["tau0"] > 0,
            "invalid prior precision identity")
    require(isinstance(contract["posterior_target_sha256"], str) and
            re.fullmatch(r"[0-9a-f]{64}:tau=[^:]+:tau0=[^:]+", contract["posterior_target_sha256"]),
            "invalid posterior target identity")
    require(type(contract.get("seed")) is int and 0 < contract["seed"] < 2 ** 31, "missing exact seed identity")
    require(all(type(terminal.get(k)) is int and terminal[k] > 0 for k in ("n", "p")), "invalid design dimensions")
    require(type(terminal.get("iterations")) is int and 0 <= terminal["iterations"] <= 300,
            "invalid or over-cap iteration count")
    flags = ("finite_core", "formal_converged", "independent_fixedpoint_certified", "computationally_certified")
    require(all(type(terminal.get(k)) is bool for k in flags), "missing exact terminal booleans")
    require(type(certificate.get("certified")) is bool, "missing exact certificate boolean")
    checks = certificate.get("checks", {})
    measures = certificate.get("measures", {})
    require(set(checks) == set(LIMITS) and set(measures) == set(LIMITS), "certificate gates omitted/added")
    for key, limit in LIMITS.items():
        value = measures[key]
        require(type(value) in (int, float) and math.isfinite(value) and value >= 0, "invalid stationarity metadata")
        require(type(checks[key]) is bool and checks[key] == (value <= limit), "check/measure disagreement: " + key)
    rhs = certificate.get("rhs_reconstruction", {})
    require(all(type(rhs.get(k)) is bool for k in ("unit_converged", "dispersed_converged")),
            "both original RHS starts must be present")
    independent = all(checks.values()) and rhs["unit_converged"] and rhs["dispersed_converged"]
    require(certificate["certified"] == independent == terminal["independent_fixedpoint_certified"],
            "independent certificate booleans disagree")
    accepted = terminal["finite_core"] and (terminal["formal_converged"] or independent)
    require(terminal["computationally_certified"] == accepted, "original acceptance formula disagrees")
    return dict(state="SAVED_ACCEPTED_ORIGINAL" if accepted else "SAVED_FAILED_ORIGINAL",
                finite_core=terminal["finite_core"], formal_converged=terminal["formal_converged"],
                independent_fixedpoint_certified=independent, computationally_certified=accepted,
                failed_checks=sorted(k for k in checks if not checks[k]),
                RHS_both_starts_converged=rhs["unit_converged"] and rhs["dispersed_converged"],
                iterations=terminal["iterations"], termination=terminal.get("termination"),
                exact_optimizer_resumption_supported=terminal.get("exact_optimizer_resumption_supported"),
                full_fit_object_retained=terminal.get("full_fit_object_retained"),
                initialization_only=terminal.get("initialization_only"),
                reported_status_ignored=terminal.get("status"))


def validate_dag(tasks, external_dependencies=()):
    """Validate exact registered membership, dependency identity, and acyclicity."""
    require(isinstance(tasks, dict) and 0 < len(tasks) <= MAX_TASKS, "invalid registered catalogue size")
    external = set(external_dependencies)
    require(not external.intersection(tasks), "external dependency is registered locally")
    children = {name: [] for name in tasks}
    indegree = {name: 0 for name in tasks}
    missing = set()
    for name, task in tasks.items():
        require(isinstance(name, str) and name and "/" not in name and task.get("name") == name,
                "task identity/key mismatch")
        depends = task.get("depends", [])
        require(isinstance(depends, list) and all(isinstance(d, str) and d for d in depends), "invalid dependencies")
        require(len(depends) == len(set(depends)), "duplicate dependency")
        if task.get("kind") in AL_KINDS:
            require(isinstance(task.get("parent_name"), str) and task["parent_name"] in depends,
                    "AL scientific parent is missing from declared dependencies")
            if task.get("kind") == "internal_al":
                require(isinstance(task.get("design_name"), str) and task["design_name"] in depends,
                        "internal AL design is missing from declared dependencies")
        for dependency in depends:
            if dependency not in tasks:
                require(dependency in external, "undeclared missing dependency: " + dependency)
                missing.add(dependency)
            else:
                children[dependency].append(name)
                indegree[name] += 1
    require(missing == external, "external declaration has unused/missing identities")
    queue = collections.deque(sorted(name for name, degree in indegree.items() if degree == 0))
    ordered = []
    while queue:
        name = queue.popleft()
        ordered.append(name)
        for child in sorted(children[name]):
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)
    require(len(ordered) == len(tasks), "registered dependency cycle")
    return children, ordered


def descendant_closure(tasks, anchors, external_dependencies=()):
    children, _ = validate_dag(tasks, external_dependencies)
    require(len(anchors) == len(set(anchors)) and set(anchors) <= set(tasks), "unknown/duplicate repair anchor")
    per_parent = {}
    for anchor in anchors:
        found = set()
        pending = list(children[anchor])
        while pending:
            name = pending.pop()
            if name not in found:
                found.add(name)
                pending.extend(children[name])
        per_parent[anchor] = sorted(found)
    union = set().union(*(set(names) for names in per_parent.values())) if per_parent else set()
    return dict(per_parent=per_parent, union=sorted(union),
                union_count=len(union), per_parent_sum=sum(map(len, per_parent.values())),
                repair_anchors_also_descendants=sorted(union.intersection(anchors)),
                remaining_nonanchor_descendants=sorted(union.difference(anchors)),
                external_prerequisites_unproved=sorted(external_dependencies))


def _listing(directory):
    directory = physical_path(directory)
    rows = []
    with os.scandir(directory) as entries:
        for entry in entries:
            require(entry.name.endswith(".json"), "unexpected entry in task catalogue")
            require(not entry.is_symlink() and entry.is_file(follow_symlinks=False), "nonregular registered task")
            s = entry.stat(follow_symlinks=False)
            rows.append(dict(name=entry.name, device=s.st_dev, inode=s.st_ino, size=s.st_size,
                             mtime_ns=s.st_mtime_ns, ctime_ns=s.st_ctime_ns, is_symlink=False))
            require(len(rows) <= MAX_TASKS, "task catalogue exceeds bound")
    return sorted(rows, key=lambda x: x["name"])


def bind_catalogue(region, capture, reader):
    root = physical_path(capture["root"])
    require(region in CANONICAL_ROOTS and str(root) == CANONICAL_ROOTS[region], "not the canonical current region campaign")
    require(capture.get("registered_tasks_complete") is True and capture.get("listing_stable") is True,
            "unproved complete stable registered catalogue")
    before, after = capture["listing_before"], capture["listing_after"]
    require(before == after and before.get("directory_exists") is True and before.get("no_symlink") is True,
            "captured task listing changed or unsafe")
    expected = sorted(before["rows"], key=lambda x: x["name"])
    require(before["count"] == len(expected) == len(capture["tasks"]), "omitted/extra registered tasks")
    require(before["directory"] == str(root / "tasks"), "catalogue root mismatch")
    require(len({r["name"] for r in expected}) == len(expected), "duplicate captured task name")
    remote = getattr(reader, "source_bound_remote", False)
    if not remote:
        require(_listing(root / "tasks") == expected, "current registered catalogue changed since snapshot")
    tasks = {}
    for name, binding in capture["tasks"].items():
        require(binding["path"] == str(root / "tasks" / (name + ".json")), "task path is outside declared campaign")
        task = reader.read(binding)
        require(task.get("region") == region and task.get("name") == name, "campaign/task region identity mismatch")
        tasks[name] = task
    require({n + ".json" for n in tasks} == {r["name"] for r in expected}, "catalogue membership differs")
    if not remote:
        require(_listing(root / "tasks") == expected, "registered catalogue changed during readback")
    external = sorted({d for t in tasks.values() for d in t.get("depends", []) if d not in tasks})
    validate_dag(tasks, external)
    return tasks, external


def _parent_evidence(region, name, category, metadata, task_pin, reader):
    keys = {"terminal": "fit/terminal.json", "certificate": "fit/fixedpoint_certificate.json",
            "contract": "contract.json", "seal": "completed_evidence.json"}
    require(set(keys.values()) <= set(metadata), "incomplete failed-parent metadata: " + name)
    root = Path(CANONICAL_ROOTS[region])
    for key, filename in keys.items():
        expected = root / "contracts" / (name + ".json") if key == "contract" else root / "tasks_done" / name / filename
        require(metadata[filename]["path"] == str(expected), "parent metadata outside canonical task layout")
    values = {key: reader.read(metadata[filename]) for key, filename in keys.items()}
    terminal, contract, seal = values["terminal"], values["contract"], values["seal"]
    require(terminal["contract_path"] == metadata["contract.json"]["path"] and
            terminal["contract_sha256"] == metadata["contract.json"]["sha256"], "terminal/contract source binding differs")
    require(seal["artifacts"]["fit/terminal.json"] == metadata["fit/terminal.json"]["sha256"] and
            seal["artifacts"]["fit/fixedpoint_certificate.json"] == metadata["fit/fixedpoint_certificate.json"]["sha256"],
            "terminal/certificate completion seal differs")
    require(seal["metadata"]["task_sha256"] == task_pin, "completion seal/task binding differs")
    state = certificate_state(terminal, values["certificate"], contract)
    require(seal["metadata"].get("certified") is state["computationally_certified"], "completion seal certificate flag differs")
    return dict(region=region, name=name, category=category,
                evidence_epoch="CURRENT_SOURCE_BOUND_REMOTE_COLLECTOR_CAPTURE" if getattr(reader, "source_bound_remote", False) else "CURRENT_CAPTURE_READ_BACK",
                classification=state, seed=contract["seed"], n=terminal["n"], p=terminal["p"],
                tau=contract["tau"], tau0=contract["tau0"], posterior_target_sha256=contract["posterior_target_sha256"],
                source_head=seal["metadata"].get("source_head"),
                source_pins={k: {"path": metadata[v]["path"], "sha256": metadata[v]["sha256"]} for k, v in keys.items()},
                repair_admitted=False, automatic_replacement_allowed=False,
                old_state_use="INITIALIZATION_ONLY_NEW_ATTEMPT_REQUIRED")


def audit_native(spec, reader, now):
    freeze = reader.read(spec["source_freeze"])
    worktree = physical_path(spec["worktree"])
    require(freeze["worktree"] == str(worktree), "native source worktree changed")
    def git(*args):
        reader.check()
        completed = subprocess.run(["git", "-C", str(worktree), *args], check=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        require(len(completed.stdout) < MAX_JSON_BYTES, "unbounded Git source readback")
        return completed.stdout.decode().strip()
    head = git("rev-parse", "HEAD")
    require(head == spec["expected_head"] == NATIVE_HEAD, "native current HEAD differs from reviewed R157 source")
    bindings = freeze["source_bindings"]
    require(len(bindings) >= 8, "native source freeze is incomplete")
    require(len({b["path"] for b in bindings}) == len(bindings), "duplicate native source pins")
    relative = []
    for binding in bindings:
        p = physical_path(binding["path"])
        require(p.is_relative_to(worktree) and p.suffix in (".py", ".R", ".c"), "unexpected native source surface")
        reader.read(binding, parsed=False)
        relative.append(str(p.relative_to(worktree)))
    dirty = git("status", "--porcelain", "--", *relative)
    require(not dirty, "native proof source surface is dirty")
    proof = reader.read(freeze["native_proof_pin"])
    require(proof.get("returncode") == 0 and proof.get("CPU_accounting_complete") is True and
            proof.get("drained") is True and proof.get("optimizer_invocations") == 0 and
            proof.get("real_target_inputs") is False and proof.get("numerical_parity_proved") is False,
            "native metadata receipt is not the accepted zero-optimizer proof")
    proof_sources = proof.get("source_file_pins", {})
    require(len(proof_sources) >= 4, "native proof source pins omitted")
    for path, digest in proof_sources.items():
        p = physical_path(path)
        require(p.is_relative_to(worktree) and p.suffix in (".py", ".R", ".c"), "native proof source outside declared worktree")
        reader.read(dict(path=path, sha256=digest), parsed=False)
        relative.append(str(p.relative_to(worktree)))
    attestation = proof.get("scientific_filter_kernel_attestation", {})
    require(attestation.get("flags") == "TSYNC" and attestation.get("kernel_return") == 0 and
            proof.get("postbootstrap_TSYNC_scientific_fork_denial") is True and
            proof.get("all_newborns_kernel_traced_before_execution") is True and
            proof.get("tracer_death_kernel_EXITKILL_enabled") is True,
            "native kernel boundary proof omitted/changed")
    config = reader.read(spec["conditional_config"])
    require(config["caps"] == {"AL": 300, "Normal": 2000}, "original numerical caps changed")
    require(config.get("production_runtime_compatible") is False and config.get("production_pilot_admitted") is False,
            "current conditional config admission state changed; separate review required")
    permit = reader.read(config["global_contract"])
    policy = reader.read(permit["evidence"]["resource_policy"])
    failure = reader.read(spec["last_failed_toy"])
    require(failure.get("status") == "FAILED_COST_RETAINED_NO_RETRY" and failure.get("old_costs_refunded") is False,
            "last failed toy/cost record changed")
    require(git("rev-parse", "HEAD") == head and not git("status", "--porcelain", "--", *relative),
            "native source changed during audit")
    return dict(current_local_head=head, source_surface_clean=True, frozen_source_files_verified=len(bindings),
                native_metadata_proof_sources_verified=len(proof_sources),
                dated_freeze_status_is_not_current_publication_evidence=True,
                remote_publication="UNPROVED_BY_THIS_OFFLINE_COMPILER_REQUIRE_FRESH_GIT_READBACK",
                native_metadata_proof="PASS_ZERO_OPTIMIZER_ONLY",
                numerical_parity_proved=False, production_runtime_compatible=False,
                last_toy_status=failure["status"], last_toy_error=failure.get("error"),
                historical_peer_not_a_current_liveness_claim=True,
                last_toy_paid_CPU_seconds=failure.get("whole_process_CPU_seconds"),
                old_global_permit=dict(pin=config["global_contract"], expires_epoch=permit["expires_epoch"],
                                       expired_at_audit=now >= permit["expires_epoch"]),
                old_resource_policy=dict(pin=permit["evidence"]["resource_policy"], expires_epoch=policy["expires_epoch"],
                                         expired_at_audit=now >= policy["expires_epoch"]),
                new_distinct_authority_required=True, old_policy_expiry_must_not_be_changed=True,
                old_native_entrypoints_enforce_original_pool=True,
                source_adaptation_needed_for_new_policy="REVIEWED_VERSIONED_ENTRYPOINT_AND_ACYCLIC_OWNER_ADMISSION",
                caps=dict(AL=300, Normal=2000), numerical_execution_authorized=False)


GATES = [
    dict(stage="EVIDENCE_RECONCILIATION", prerequisite="Complete current NO3 registered DAG and metadata and bind external AT prerequisite before production/dependent release; synthetic toy preparation is independent", allowed_now="METADATA_ONLY"),
    dict(stage="NEW_DISTINCT_AUTHORITY", prerequisite="Root reviews new finite prospective resource policy, versioned source admission adapter, exact source pins and canonical acyclic owner admission; all historical clocks/costs unchanged", allowed_now="PREPARE_ONLY"),
    dict(stage="PROJECTION_TOY", prerequisite="Fresh source publication readback, EE/LV success and drain proof, exclusive CPU30/SMT62 guard and exact funded one-shot grant; synthetic n128/p32 parity proof does not depend on remote NO3 graph", allowed_now="NOT_ADMITTED"),
    dict(stage="ZERO_UPDATE_BRIDGE", prerequisite="Accepted source-matched toy, current source-bound actual-target metadata and separately paid zero-update actual-target bridge; no optimizer invocation", allowed_now="NOT_ADMITTED"),
    dict(stage="PRICED_NO3_PILOT", prerequisite="Reviewed full-lifecycle price, before/after source/target/caps/seed proof, fresh peer checks, one distinct finite grant; original larger-tau NO3 only", allowed_now="NOT_ADMITTED"),
    dict(stage="AT_PILOT_AND_EXTENSIONS", prerequisite="NO3 acceptance required; AT median separate grant then only separately reviewed original target allowlist", allowed_now="NOT_ADMITTED"),
    dict(stage="LT_OBJECTIVE_DIAGNOSIS", prerequisite="Diagnose original objective-reference failure and independent stationarity gates; own price and pilot grant", allowed_now="METADATA_DIAGNOSIS_ONLY"),
    dict(stage="NO4_TARGETED_REPAIR", prerequisite="Preserve six failures and unknown active fits; source-bound conditioning diagnosis, own pilot/price/target allowlist; no automatic inclusion in old seven-target grant", allowed_now="METADATA_DIAGNOSIS_ONLY"),
    dict(stage="DEPENDENT_RELEASE", prerequisite="Reviewed resolver binds exact accepted replacements to failed originals and refreshed deduplicated DAG; no status-name override", allowed_now="NOT_ADMITTED"),
]


def compile_readiness(request, reader, now=None):
    now = time.time() if now is None else now
    require(request.get("schema") == "r164_repair_readiness_request_v1" and
            request.get("numerical_execution_authorized") is False, "not a metadata-only R164 request")
    require(request["historical_matrix"]["sha256"] == MATRIX_SHA256, "historical seven-target matrix changed")
    matrix = reader.read(request["historical_matrix"])
    require(matrix["source_manifest"]["sha256"] == MANIFEST_SHA256 and
            request["original_manifest"] == matrix["source_manifest"], "historical manifest identity changed")
    manifest = reader.read(request["original_manifest"])
    require(len(matrix["targets"]) == len(manifest["targets"]) == 7, "original seven-target set changed")
    originals = {(t["region"], t["name"]): t for t in manifest["targets"]}
    require(len(originals) == 7 and {(t["region"], t["name"]) for t in matrix["targets"]} == set(originals),
            "historical target membership differs")
    local = reader.read(request["current_local_snapshot"])
    require(local.get("mutations") == 0 and local.get("numerical_payloads_read") == 0, "snapshot is not metadata-only")
    require(set(local["regions"]) <= REQUIRED_REGIONS, "unexpected campaign region")
    captures = dict(local["regions"])
    remote_readers, remote_epoch = {}, None
    if request.get("remote_NO3_capture") is not None:
        remote_capture, remote_reader = bind_remote_no3(request["remote_NO3_capture"], reader)
        require("NO_3" not in captures, "current NO3 capture supplied twice")
        captures.update(remote_capture["regions"])
        remote_readers["NO_3"], remote_epoch = remote_reader, remote_capture["observed_epoch"]
    gates = []
    missing = REQUIRED_REGIONS.difference(captures)
    for region in sorted(missing):
        gates.append("MISSING_CURRENT_" + region + "_DAG_SNAPSHOT")
    registry, dags, tasks_by_region = [], {}, {}
    for region, capture in sorted(captures.items()):
        regional_reader = remote_readers.get(region, reader)
        tasks, external = bind_catalogue(region, capture, regional_reader)
        tasks_by_region[region] = tasks
        resolved_external = []
        if region == "AT" and request.get("AT_external_prerequisite_evidence") is not None:
            resolved_external = [bind_AT_external(request["AT_external_prerequisite_evidence"], tasks, reader)]
        unbound_external = set(external).difference(x["name"] for x in resolved_external)
        if unbound_external:
            gates.append("UNBOUND_EXTERNAL_PREREQUISITES:" + region)
        parents, accepted_originals = [], []
        for name, task in sorted(tasks.items()):
            metadata = capture["completed_metadata"].get(name, {})
            terminal = metadata.get("fit/terminal.json", {}).get("value", {})
            if task.get("kind") not in AL_KINDS or not terminal:
                continue
            category = "HISTORICAL_SEVEN" if (region, name) in originals else (
                "NO4_ORIGINAL_FOUR" if name in NO4_ORIGINAL else "NO4_NEW_TWO" if name in NO4_NEW else "ADDITIONAL_CURRENT_FAILURE")
            row = _parent_evidence(region, name, category, metadata, capture["tasks"][name]["sha256"], regional_reader)
            expected_root = next((Path(b["path"]).parent.parent for b in originals.get((region, name), {}).get("bindings", [])
                                  if b["path"].endswith("/contracts/" + name + ".json")), None)
            if expected_root is not None:
                require(str(expected_root) == capture["root"], "historical target campaign root differs")
            if row["classification"]["state"] == "SAVED_ACCEPTED_ORIGINAL":
                accepted_originals.append(name)
                continue
            registry.append(row)
            parents.append(name)
        closure = descendant_closure(tasks, parents, external)
        closure["external_prerequisites_unproved"] = sorted(unbound_external)
        closure["resolved_external_prerequisites"] = resolved_external
        closure.update(region=region, campaign_root=capture["root"], registered_tasks=len(tasks),
                       registered_membership_complete=True, current_capture_rebound=region not in remote_readers,
                       source_bound_remote_capture=region in remote_readers,
                       accepted_saved_original_AL_tasks=accepted_originals,
                       graph_scope="EXACT_REGISTERED_TASKS_IN_DECLARED_CAMPAIGN_ONLY",
                       missing_outside_campaign_descendants_not_assumed=True,
                       task_kind_counts=dict(collections.Counter(t["kind"] for t in tasks.values())),
                       unresolved_without_saved_terminal=sorted(n for n, t in tasks.items() if t.get("kind") in AL_KINDS and
                           "fit/terminal.json" not in capture["completed_metadata"].get(n, {})))
        dags[region] = closure
    indexed = {(r["region"], r["name"]): r for r in registry}
    for target in matrix["targets"]:
        key = (target["region"], target["name"])
        original = originals[key]
        bindings = {b["path"]: b for b in original["bindings"]}
        root = Path(CANONICAL_ROOTS[target["region"]])
        terminal_pins = [b for b in bindings.values() if b["path"] == str(root / "tasks_done" / target["name"] / "fit/terminal.json")]
        contract_pins = [b for b in bindings.values() if b["path"] == str(root / "contracts" / (target["name"] + ".json"))]
        require(any(b["sha256"] == target["original_terminal_sha256"] for b in terminal_pins) and
                any(b["sha256"] == target["original_contract_sha256"] for b in contract_pins), "matrix/original source pin mismatch")
        require(original["contract"]["seed"] == target["seed"] and original["posterior_target_sha256"] == target["posterior_target_sha256"],
                "historical seed/posterior identity differs")
        if key in indexed:
            row = indexed[key]
            require(row["source_pins"]["terminal"]["sha256"] == target["original_terminal_sha256"] and
                    row["source_pins"]["contract"]["sha256"] == target["original_contract_sha256"] and
                    all(row[k] == target[k] for k in ("seed", "n", "p", "tau", "tau0", "posterior_target_sha256")),
                    "current/historical failed-parent identity differs")
        else:
            require(target["region"] not in captures, "historical failed parent omitted from current catalogue")
            state = certificate_state(original["stored_terminal"], original["stored_certificate"], original["contract"])
            require(state["state"] == "SAVED_FAILED_ORIGINAL", "historical failed parent unexpectedly accepted")
            row = dict(region=target["region"], name=target["name"], category="HISTORICAL_SEVEN",
                       evidence_epoch="HISTORICAL_PINNED_MANIFEST_ONLY_CURRENT_REMOTE_UNPROVED", classification=state,
                       source_pins=dict(terminal=dict(path=terminal_pins[0]["path"], sha256=target["original_terminal_sha256"]),
                                        contract=dict(path=contract_pins[0]["path"], sha256=target["original_contract_sha256"])),
                       n=target["n"], p=target["p"], seed=target["seed"], tau=target["tau"], tau0=target["tau0"],
                       posterior_target_sha256=target["posterior_target_sha256"], current_DAG_closure="UNPROVED",
                       repair_admitted=False, automatic_replacement_allowed=False, old_state_use="INITIALIZATION_ONLY_NEW_ATTEMPT_REQUIRED")
            registry.append(row)
    known_no4 = {r["name"] for r in registry if r["region"] == "NO_4"}
    require(set(NO4_ORIGINAL + NO4_NEW) <= known_no4, "known NO4 original/new failed parent omitted")
    native = audit_native(request["native"], reader, now)
    gates.extend(["NUMERICAL_COMPATIBILITY_NOT_PROVED", "CURRENT_SOURCE_REMOTE_PUBLICATION_READBACK_REQUIRED",
                  "NEW_DISTINCT_RESOURCE_POLICY_AND_VERSIONED_ADMISSION_REQUIRED", "NO_NEW_REPAIR_OR_REPLACEMENT_ADMITTED"])
    if native["old_global_permit"]["expired_at_audit"]:
        gates.append("OLD_GLOBAL_PERMIT_EXPIRED_DO_NOT_RENEW")
    registry.sort(key=lambda r: (r["region"], r["name"]))
    return dict(schema="r164_repair_readiness_packet_v1", status="PREPARED_NOT_ADMITTED",
                observed_epoch=now, source_bound_to_captured_evidence_only=True,
                current_local_capture_epoch=local["observed_epoch"],
                current_remote_NO3_capture_epoch=remote_epoch,
                numerical_execution_authorized=False, production_mutations=0, numerical_payloads_read=0,
                registry=registry, known_failed_parent_count=len(registry),
                known_failure_categories=dict(collections.Counter(r["category"] for r in registry)),
                current_local_failed_parent_count=sum(r["evidence_epoch"] == "CURRENT_CAPTURE_READ_BACK" for r in registry),
                current_remote_failed_parent_count=sum(r["evidence_epoch"] == "CURRENT_SOURCE_BOUND_REMOTE_COLLECTOR_CAPTURE" for r in registry),
                historical_only_failed_parent_count=sum(r["evidence_epoch"] == "HISTORICAL_PINNED_MANIFEST_ONLY_CURRENT_REMOTE_UNPROVED" for r in registry),
                dags=dags, all_four_current_DAGs_complete=not missing,
                historical_29_and_28_are_not_current_full_closure_counts=True,
                deduplicated_registered_descendants=sum(d["union_count"] for d in dags.values()),
                local_deduplicated_registered_descendants=sum(d["union_count"] for region, d in dags.items() if region not in remote_readers),
                native_source_audit=native, blockers=sorted(set(gates)), next_gates=GATES,
                original_failures_certificates_seeds_caps_and_prior_preserved=True,
                automatic_dispatch_allowed=False, replacement_resolution_allowed=False,
                exact_optimizer_resume_claimed=False, paid_history_unchanged=True,
                replay_request=request, evidence_receipts=list(reader.receipts.values()))


def write_new_packet(output, packet):
    output = physical_path(output)
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    raw = json_bytes(packet)
    require(len(raw) <= MAX_JSON_BYTES, "readiness packet exceeds bounded output")
    destination = output / "REPAIR_READINESS.json"
    temporary = output / ".REPAIR_READINESS.pending"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.link(temporary, destination, follow_symlinks=False)
    temporary.unlink()
    directory_fd = os.open(output, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return dict(path=str(destination), sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--request-sha256", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args(argv)
    require(os.sched_getaffinity(0) == {31}, "metadata compiler must run only on administrative CPU31")
    scope_path = physical_path(args.scope)
    require(scope_path.suffix == ".json", "scope must be JSON metadata")
    with scope_path.open("rb") as stream:
        scope = decode_json(stream.read(MAX_JSON_BYTES + 1))
    now = time.time()
    require(scope["issued_epoch"] <= now < scope["expires_epoch"], "child administrative scope expired/not issued")
    require(scope.get("admin_cpu") == 31 and scope.get("new_numerical_calls") == 0 and
            scope.get("production_or_runtime_mutations") == 0, "scope is not zero-numerical administrative work")
    output = physical_path(args.output_dir)
    require(output.parent == physical_path(scope["write_scope"]), "output must be one new child of administrative scope directory")
    reader = Reader(maximum_cpu=min(25, scope["maximum_CPU_seconds"]),
                    maximum_wall=min(300, scope["expires_epoch"] - now))
    request = reader.read(dict(path=args.request, sha256=args.request_sha256))
    packet = compile_readiness(request, reader, now)
    reader.check()
    packet["administrative_accounting"] = reader.cost()
    packet["scope_path"] = str(scope_path)
    packet["compiler_source_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    pin = write_new_packet(output, packet)
    print(json.dumps(dict(status=packet["status"], output=pin,
                         failed_parents=packet["known_failed_parent_count"], blockers=packet["blockers"]), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
