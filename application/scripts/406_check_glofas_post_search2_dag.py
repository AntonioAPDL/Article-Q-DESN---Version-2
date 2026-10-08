#!/usr/bin/env python3
"""Read-only health checker for the post-Search-II GloFAS DAG."""

import argparse
import csv
import hashlib
import json
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from glofas_post_search2_resources import validate_worker_resources


def repo_root(): return Path(__file__).resolve().parents[2]
def resolve(path):
    value = Path(path)
    return value.resolve() if value.is_absolute() else (repo_root() / value).resolve()
def read(path):
    with path.open(newline="", encoding="utf-8") as handle: return list(csv.DictReader(handle))
def sessions():
    result = subprocess.run(
        ["tmux", "list-sessions", "-F", "#{session_name}"],
        universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return set(result.stdout.splitlines()) if result.returncode == 0 else set()
def deps(row): return [x for x in row.get("dependencies", "").split("|") if x]
def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
def recorded_path(value):
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo_root() / path).resolve()


def session_name(prefix, job_id):
    digest = hashlib.sha1(job_id.encode()).hexdigest()[:10]
    return f"{prefix}_{job_id[:42]}_{digest}".replace(".", "p")


def descendant_pids(root_pid, parent_rows):
    children = defaultdict(list)
    for pid, parent in parent_rows:
        children[int(parent)].append(int(pid))
    found = []
    frontier = [int(root_pid)]
    while frontier:
        pid = frontier.pop()
        if pid in found:
            continue
        found.append(pid)
        frontier.extend(children.get(pid, []))
    return found


def affinities_for_session(name):
    result = subprocess.run(
        ["tmux", "list-panes", "-t", name, "-F", "#{pane_pid}"],
        universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return {}
    pane_pid = int(result.stdout.splitlines()[0].strip())
    processes = subprocess.run(
        ["ps", "-eo", "pid=,ppid="], universal_newlines=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if processes.returncode != 0:
        return {}
    parent_rows = []
    for line in processes.stdout.splitlines():
        fields = line.split()
        if len(fields) == 2:
            parent_rows.append((int(fields[0]), int(fields[1])))
    out = {}
    for pid in descendant_pids(pane_pid, parent_rows):
        affinity = subprocess.run(
            ["taskset", "-pc", str(pid)], universal_newlines=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if affinity.returncode == 0 and ":" in affinity.stdout:
            out[pid] = affinity.stdout.rsplit(":", 1)[1].strip()
    return out


def contract_health(runtime, running_jobs, launch_payload):
    checks = []
    readiness_path = runtime / "configs" / "launch_readiness.json"
    if not readiness_path.is_file():
        return [{"contract": "launch_readiness", "status": "missing", "detail": str(readiness_path)}]
    try:
        readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
        checks.append({
            "contract": "launch_readiness",
            "status": "pass" if readiness.get("status") == "ready" else "fail",
            "detail": readiness.get("status", "unknown"),
        })
        mismatches = []
        for row in readiness.get("artifacts", []):
            path = recorded_path(row["path"])
            if not path.is_file() or path.stat().st_size != int(row["size_bytes"]) or sha256(path) != row["sha256"]:
                mismatches.append(str(path))
        checks.append({
            "contract": "frozen_artifacts",
            "status": "pass" if not mismatches else "fail",
            "detail": "all_match" if not mismatches else "|".join(mismatches),
        })
    except Exception as exc:
        checks.append({"contract": "launch_readiness", "status": "fail", "detail": str(exc)})
    recovery = runtime / "configs" / "recovery_contract.json"
    checks.append({
        "contract": "recovery",
        "status": "pass" if recovery.is_file() else "not_used",
        "detail": str(recovery) if recovery.is_file() else "no recovery contract",
    })
    launch = runtime / "configs" / "post_search2_launch_contract.json"
    checks.append({
        "contract": "production_launch",
        "status": "pass" if launch.is_file() else "not_launched",
        "detail": str(launch) if launch.is_file() else "no launch contract",
    })
    execution_path = runtime / "configs" / "post_search2_execution_contract.json"
    try:
        execution = json.loads(execution_path.read_text(encoding="utf-8"))
        expected = execution.get("resource_contract")
        if not expected:
            raise ValueError("execution contract lacks resource_contract")
        live = validate_worker_resources(
            expected["worker_capacity"], expected["cpu_pool_spec"]
        )
        resource_ok = live == expected
        if launch_payload is not None:
            resource_ok = resource_ok and launch_payload.get("resource_contract") == expected
        checks.append({
            "contract": "physical_core_resources",
            "status": "pass" if resource_ok else "fail",
            "detail": (
                f"workers={expected['worker_capacity']};"
                f"cpus={expected['cpu_pool_spec']};"
                f"sockets={expected['socket_distribution']}"
            ),
        })
        assigned = {}
        assignment_errors = []
        prefix = (launch_payload or {}).get("session_prefix", "")
        launch_hash = sha256(launch) if launch.is_file() else None
        for job_id in sorted(running_jobs):
            path = runtime / "scripts" / f"{job_id}.resource.json"
            if not path.is_file():
                assignment_errors.append(f"{job_id}:missing")
                continue
            payload = json.loads(path.read_text(encoding="utf-8"))
            cpu = int(payload.get("cpu", -1))
            if cpu not in expected["active_cpu_pool"]:
                assignment_errors.append(f"{job_id}:cpu={cpu}")
            elif cpu in assigned:
                assignment_errors.append(f"{job_id}:shared_cpu={cpu}")
            else:
                assigned[cpu] = job_id
            if launch_hash and payload.get("launch_contract_sha256") != launch_hash:
                assignment_errors.append(f"{job_id}:launch_hash")
            if prefix:
                actual = affinities_for_session(session_name(prefix, job_id))
                if str(cpu) not in set(actual.values()):
                    assignment_errors.append(
                        f"{job_id}:affinities={sorted(set(actual.values()))},expected={cpu}"
                    )
        checks.append({
            "contract": "active_cpu_assignments",
            "status": "pass" if not assignment_errors else "fail",
            "detail": (
                f"active={len(running_jobs)};unique={len(assigned)}"
                if not assignment_errors else "|".join(assignment_errors)
            ),
        })
    except Exception as exc:
        checks.append({
            "contract": "physical_core_resources",
            "status": "fail",
            "detail": str(exc),
        })
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    runtime = resolve(args.runtime_root)
    jobs = read(runtime / "tables" / "post_search2_job_manifest.csv")
    active_sessions = sessions()
    launch_path = runtime / "configs" / "post_search2_launch_contract.json"
    launch_payload = (
        json.loads(launch_path.read_text(encoding="utf-8"))
        if launch_path.is_file() else None
    )
    session_prefix = (launch_payload or {}).get("session_prefix")
    completed = {row["job_id"] for row in jobs if (runtime / "status" / f"{row['job_id']}.completed").exists()}
    detail = []
    for row in jobs:
        job = row["job_id"]
        marker = runtime / "status"
        matching = (
            session_name(session_prefix, job) in active_sessions
            if session_prefix else
            any(job[:42] in name for name in active_sessions if name.startswith("glofas_post_search2"))
        )
        marker_states = [suffix for suffix in ("completed", "failed", "running")
                         if (marker / f"{job}.{suffix}").exists()]
        if len(marker_states) > 1: state = "marker_conflict"
        elif (marker / f"{job}.failed").exists(): state = "failed"
        elif job in completed: state = "completed"
        elif matching: state = "running"
        elif (marker / f"{job}.running").exists(): state = "stale_running"
        elif all(dep in completed for dep in deps(row)): state = "ready"
        else: state = "pending"
        detail.append({**row, "state": state, "missing_dependencies": "|".join(x for x in deps(row) if x not in completed)})
    grouped = defaultdict(Counter)
    for row in detail: grouped[(row["part"], row["stage"])][row["state"]] += 1
    summary = []
    for (part, stage), count in sorted(grouped.items()):
        total = sum(count.values()); done = count["completed"]
        summary.append({"part": part, "stage": stage, "total": total, "completed": done,
                        "running": count["running"], "ready": count["ready"], "pending": count["pending"],
                        "failed": count["failed"], "stale_running": count["stale_running"],
                        "marker_conflict": count["marker_conflict"],
                        "left": total-done, "pct_complete": round(100*done/total, 1)})
    totals = Counter(row["state"] for row in detail)
    summary.append({"part": "TOTAL", "stage": "TOTAL", "total": len(detail), "completed": totals["completed"],
                    "running": totals["running"], "ready": totals["ready"], "pending": totals["pending"],
                    "failed": totals["failed"], "stale_running": totals["stale_running"],
                    "marker_conflict": totals["marker_conflict"],
                    "left": len(detail)-totals["completed"], "pct_complete": round(100*totals["completed"]/len(detail), 1)})
    fields = list(summary[0])
    print(" | ".join(fields))
    for row in summary: print(" | ".join(str(row[key]) for key in fields))
    running_jobs = {row["job_id"] for row in detail if row["state"] == "running"}
    contracts = contract_health(runtime, running_jobs, launch_payload)
    print("contract | status | detail")
    for row in contracts:
        print(f"{row['contract']} | {row['status']} | {row['detail']}")
    if args.write:
        checked = datetime.now(timezone.utc).isoformat()
        for row in detail: row["checked_utc"] = checked
        with (runtime / "tables" / "post_search2_status_latest.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(detail[0])); writer.writeheader(); writer.writerows(detail)
        (runtime / "tables" / "post_search2_health_latest.json").write_text(json.dumps({"checked_utc": checked, **summary[-1]}, indent=2) + "\n")
        with (runtime / "tables" / "post_search2_contract_health_latest.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(contracts[0])); writer.writeheader(); writer.writerows(contracts)
    contract_failed = any(row["status"] in {"missing", "fail"} for row in contracts)
    return 2 if totals["failed"] or totals["stale_running"] or totals["marker_conflict"] or contract_failed else 0


if __name__ == "__main__": raise SystemExit(main())
