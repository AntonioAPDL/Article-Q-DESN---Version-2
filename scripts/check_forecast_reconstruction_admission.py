#!/usr/bin/env python3.11
"""Read-only whole-inventory feasibility gate; never dispatches or authorizes jobs.

Inputs are small source-bound benchmark receipts and a complete stratum registry.
Per-unit numerical qualification, host grants and production source validation
remain separate gates even when this resource calculation passes.
Pinned review artifacts are rehashed, but their scientific/runtime semantics
are NOT authenticated by this arithmetic checker.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path


class AdmissionError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AdmissionError(message)


def finite(value, name, *, positive=False):
    require(type(value) in (int, float) and math.isfinite(value)
            and (value > 0 if positive else value >= 0),
            name + " must be finite and " + ("positive" if positive else "nonnegative"))
    return value


def integer(value, name):
    require(type(value) is int and value > 0, name + " must be a positive integer")
    return value


def regular(path):
    path = Path(path)
    require(path.is_absolute() and path.is_file() and not path.is_symlink()
            and all(not parent.is_symlink() for parent in path.parents),
            "absolute nonsymlink regular input required")
    return path


def pinned(record, *, max_bytes=2*1024**2):
    require(isinstance(record, dict)
            and set(record) == {"path", "bytes", "sha256"}, "exact file pin required")
    path = regular(record["path"])
    require(type(record["bytes"]) is int and 0 <= record["bytes"] <= max_bytes
            and path.stat().st_size == record["bytes"], "input size changed or exceeds metadata cap")
    data = path.read_bytes()
    require(hashlib.sha256(data).hexdigest() == record["sha256"], "input SHA256 mismatch")
    return data


def read_json(data):
    def fail_constant(value):
        raise AdmissionError("nonfinite JSON number: " + value)
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate JSON field: " + key)
            result[key] = value
        return result
    value = json.loads(data, parse_constant=fail_constant, object_pairs_hook=unique_object)
    require(isinstance(value, dict), "JSON object required")
    return value


def identity(value):
    require(isinstance(value, dict), "source identity required")
    for name, size in (("source_commit", 40), ("source_tree", 40),
                       ("source_manifest_sha256", 64), ("target_sha256", 64)):
        item = value.get(name)
        require(isinstance(item, str) and len(item) == size
                and all(c in "0123456789abcdef" for c in item),
                "complete source/target identity required: " + name)
    return {name: value[name] for name in
            ("source_commit", "source_tree", "source_manifest_sha256", "target_sha256")}


def assess(spec, now=None):
    """Validate complete measured coverage, then apply all finite resource caps."""
    require(spec.get("schema_version") == "forecast_reconstruction_cost_gate_v1",
            "unknown feasibility contract")
    require(spec.get("allow_refit") is False and spec.get("allow_launch") is False,
            "this gate cannot permit fitting or launching")
    source = identity(spec.get("identity"))
    expiry = dt.datetime.fromisoformat(spec["expires_utc"].replace("Z", "+00:00"))
    require(expiry.tzinfo is not None
            and expiry > (now or dt.datetime.now(dt.timezone.utc)), "expired or unzoned cost contract")
    require(spec.get("scope") in ("IND", "MQ"), "one explicit study scope required")
    registry_data = pinned(spec["stratum_registry"])
    require(hashlib.sha256(registry_data).hexdigest() == spec["stratum_registry"]["sha256"],
            "registry content changed")
    reader = csv.DictReader(registry_data.decode("utf-8").splitlines())
    rows = list(reader)
    fields = {"stratum", "member_count", "adapter", "empirical_measure"}
    require(rows and len(reader.fieldnames or []) == len(fields)
            and set(reader.fieldnames or []) == fields
            and all(set(row) == fields for row in rows), "exact complete stratum registry required")
    labels = [row["stratum"] for row in rows]
    require(all(labels) and len(labels) == len(set(labels)), "duplicate or empty strata")
    counts = {}
    for row in rows:
        require(row["member_count"].isdigit() and int(row["member_count"]) > 0
                and row["adapter"] and row["empirical_measure"], "invalid native stratum")
        counts[row["stratum"]] = int(row["member_count"])
    require(sum(counts.values()) == integer(spec["expected_members"], "expected native members"),
            "whole-inventory membership does not reconcile")
    benchmarks = spec["benchmarks"]
    require(isinstance(benchmarks, list) and len(benchmarks) == len(rows),
            "every declared stratum needs its own measured benchmark")
    measured = {}
    pins = []
    for pin in benchmarks:
        data = pinned(pin)
        item = read_json(data)
        label = item.get("stratum")
        require(label in counts and label not in measured, "missing, unexpected or duplicate benchmark stratum")
        require(item.get("schema_version") == "forecast_reconstruction_benchmark_v1"
                and identity(item.get("identity")) == source, "benchmark is not from the exact production source/target")
        require(item.get("registry_sha256") == spec["stratum_registry"]["sha256"],
                "benchmark scope does not bind the complete frozen registry")
        require(item.get("measurement_kind") == "bounded_actual_execution"
                and item.get("precision_gate") == "PASS"
                and item.get("native_parity_gate") == "PASS"
                and item.get("source_closure_gate") == "PASS",
                "estimates, unresolved accuracy or unqualified source cannot price production")
        # These references must be authenticated by the separate source/numerical
        # review. Rehash all required local receipts, not a bare PASS boolean.
        evidence = item.get("evidence")
        require(isinstance(evidence, dict)
                and set(evidence) == {"precision", "native_parity", "production_source_smoke"},
                "benchmark requires three independently reviewed evidence bindings")
        for artifact in evidence.values():
            pinned(artifact)
        units = integer(item["measured_members"], "measured members")
        cpu = finite(item["cpu_seconds"], "measured CPU seconds", positive=True)
        wall = finite(item["wall_seconds"], "measured wall seconds", positive=True)
        artifact = finite(item["artifact_bytes"], "measured artifact bytes", positive=True)
        logs = finite(item["log_and_admin_bytes"], "log/admin bytes")
        rss = finite(item["peak_rss_bytes"], "measured peak RSS", positive=True)
        measured[label] = dict(cpu=cpu/units, wall=wall/units,
                               artifact=artifact/units, logs=logs/units, rss=rss)
        pins.append(pin["sha256"])
    require(set(measured) == set(counts), "benchmark coverage is incomplete")
    contingency = finite(spec["contingency_multiplier"], "contingency", positive=True)
    require(contingency >= 1.25, "at least 25% prospective resource contingency required")
    overhead = spec["overhead"]
    cpu = contingency*(sum(counts[k]*measured[k]["cpu"] for k in counts)
                       + finite(overhead["cpu_seconds"], "setup/scoring/transport/controller CPU"))
    wall_work = contingency*sum(counts[k]*measured[k]["wall"] for k in counts)
    output = math.ceil(contingency*(sum(counts[k]*(measured[k]["artifact"]+measured[k]["logs"])
                                           for k in counts)
                       + finite(overhead["retained_bytes"], "setup/scoring/transport retained bytes")))
    peak = max(x["rss"] for x in measured.values())*contingency
    budget = spec["budget"]
    require(cpu <= finite(budget["cpu_seconds"], "total CPU budget", positive=True),
            "complete reconstruction exceeds CPU budget")
    require(output <= finite(budget["retained_bytes"], "total retained-byte budget", positive=True),
            "complete reconstruction exceeds storage budget")
    hosts = spec["hosts"]
    require(isinstance(hosts, list) and hosts, "fresh host allocation scenario required")
    names = []
    cores = 0
    retained_allocation = 0
    for host in hosts:
        name = host.get("host")
        require(name in ("muscat", "jerez", "hummingbird") and name not in names,
                "one unique supported host per allocation")
        names.append(name)
        cores += integer(host["new_scope_physical_cores"], "new-scope cores")
        free = finite(host["free_disk_bytes"], "current host free disk", positive=True)
        reserved = finite(host["other_reserved_bytes"], "other lane disk reservation")
        staging = finite(host["max_staged_and_pending_bytes"], "bounded staging/pending bytes")
        retained = finite(host["final_retained_allocation_bytes"], "declared final retained allocation")
        retained_allocation += retained
        floor = finite(host["disk_floor_bytes"], "host disk floor", positive=True)
        require(free-reserved-staging-retained >= floor,
                "host disk reservation/floor fails: " + name)
        per_core = finite(host["available_ram_after_other_reservations_bytes"], "unreserved RAM") / host["new_scope_physical_cores"]
        require(per_core >= peak, "measured concurrent peak RSS exceeds host reservation: " + name)
        require(host.get("new_scope_grant_verified") is True
                and host.get("method_source_runtime_verified") is True
                and host.get("return_and_accounting_verified") is True,
                "fresh method/source/host/grant prerequisites missing: " + name)
        for role in ("grant_receipt", "runtime_receipt", "return_and_accounting_receipt"):
            pinned(host[role])
    require(retained_allocation >= output,
            "priced retained outputs have no complete physical-storage allocation")
    # This optimistic floor is not a promise: queue time and sequential
    # qualification/closeout dependencies remain outside CPU division.
    optimistic_seconds = max(cpu/cores, wall_work/cores)
    require(optimistic_seconds <= finite(budget["calendar_seconds"], "calendar budget", positive=True),
            "even ideal continuous capacity exceeds the calendar budget")
    return dict(schema_version="forecast_reconstruction_cost_decision_v1",
                status="COST_GATE_PASS_NOT_LAUNCH_AUTHORITY", scope=spec["scope"],
                identity=source, strata=len(counts), members=sum(counts.values()),
                priced_cpu_seconds=cpu, priced_retained_bytes=output,
                measured_peak_rss_with_contingency_bytes=peak,
                optimistic_calendar_floor_seconds=optimistic_seconds,
                calendar_floor_is_not_eta=True, contingency_multiplier=contingency,
                external_receipt_semantics_validated_here=False,
                host_and_numerical_admission_still_required=True,
                benchmark_sha256=pins, allow_refit=False, allow_launch=False,
                publication_authorized=False)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--sha256", required=True)
    args = parser.parse_args(argv)
    try:
        path = regular(args.contract)
        spec = read_json(pinned({"path":str(path), "bytes":path.stat().st_size,
                                "sha256":args.sha256}))
        result = assess(spec)
    except (AdmissionError, KeyError, ValueError, TypeError, OSError) as error:
        print(json.dumps(dict(status="NOT_ADMITTED", reason=str(error),
                              allow_launch=False, allow_refit=False)))
        return 2
    print(json.dumps(result, sort_keys=True, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
