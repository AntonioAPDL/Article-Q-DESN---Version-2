#!/usr/bin/env python3
"""Read-only health checker for the post-Search-II GloFAS DAG."""

import argparse
import csv
import hashlib
import json
import subprocess
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


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


def contract_health(runtime):
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
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    runtime = resolve(args.runtime_root)
    jobs = read(runtime / "tables" / "post_search2_job_manifest.csv")
    active_sessions = sessions()
    completed = {row["job_id"] for row in jobs if (runtime / "status" / f"{row['job_id']}.completed").exists()}
    detail = []
    for row in jobs:
        job = row["job_id"]
        marker = runtime / "status"
        matching = any(job[:42] in name for name in active_sessions if name.startswith("glofas_post_search2"))
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
    contracts = contract_health(runtime)
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
