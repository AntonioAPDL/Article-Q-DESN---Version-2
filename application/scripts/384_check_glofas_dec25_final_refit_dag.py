#!/usr/bin/env python3
"""Health check for the Dec25 Part 2/3 final-refit DAG."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(path: str) -> Path:
    p = Path(path)
    return p.resolve() if p.is_absolute() else (repo_root() / p).resolve()


def session_name(prefix: str, job_id: str) -> str:
    return f"{prefix}_{job_id}".replace(".", "p")[:78]


def tmux_sessions() -> set[str]:
    try:
        out = subprocess.check_output(["tmux", "list-sessions", "-F", "#{session_name}"], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0]) if rows else ["empty"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def deps(row: dict) -> list[str]:
    return [dep for dep in row.get("dependencies", "").split("|") if dep]


def state_for(row: dict, runtime: Path, sessions: set[str], prefix: str, completed: set[str]) -> str:
    job = row["job_id"]
    if (runtime / "status" / f"{job}.failed").exists():
        return "failed"
    if (runtime / "status" / f"{job}.completed").exists():
        return "completed"
    active = session_name(prefix, job) in sessions
    running_marker = (runtime / "status" / f"{job}.running").exists()
    if active:
        return "running"
    if running_marker:
        return "stale_running"
    if all(dep in completed for dep in deps(row)):
        return "ready"
    return "pending"


def summarize(rows: list[dict], keys: tuple[str, ...]) -> list[dict]:
    groups = defaultdict(list)
    for row in rows:
        groups[tuple(row[key] for key in keys)].append(row)
    out = []
    for key, items in sorted(groups.items()):
        counts = defaultdict(int)
        for item in items:
            counts[item["state"]] += 1
        total = len(items)
        completed = counts["completed"]
        out.append({
            **{keys[ii]: key[ii] for ii in range(len(keys))},
            "total": total,
            "completed": completed,
            "running": counts["running"],
            "ready": counts["ready"],
            "pending": counts["pending"],
            "stale_running": counts["stale_running"],
            "failed": counts["failed"],
            "left_to_finish": total - completed,
            "pct_complete": f"{100.0 * completed / total:.1f}",
        })
    return out


def print_table(rows: list[dict], columns: list[str]) -> None:
    widths = {col: max(len(col), *(len(str(row.get(col, ""))) for row in rows)) for col in columns}
    print(" | ".join(col.ljust(widths[col]) for col in columns))
    print("-+-".join("-" * widths[col] for col in columns))
    for row in rows:
        print(" | ".join(str(row.get(col, "")).ljust(widths[col]) for col in columns))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--session-prefix", default="glofas_dec25_final_jerez_20260905")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--fail-on-not-ready", action="store_true")
    args = parser.parse_args()

    runtime = resolve(args.runtime_root)
    manifest = runtime / "tables" / "final_dec25_job_manifest.csv"
    if not manifest.exists():
        raise SystemExit(f"missing Dec25 manifest: {manifest}")
    rows = read_csv(manifest)
    sessions = tmux_sessions()
    completed = {row["job_id"] for row in rows if (runtime / "status" / f"{row['job_id']}.completed").exists()}
    detail = []
    for row in rows:
        state = state_for(row, runtime, sessions, args.session_prefix, completed)
        dependencies = deps(row)
        detail.append({
            **row,
            "state": state,
            "dependencies_done": str(all(dep in completed for dep in dependencies)),
            "missing_dependencies": "|".join(dep for dep in dependencies if dep not in completed),
            "tmux_session_active": str(session_name(args.session_prefix, row["job_id"]) in sessions),
            "checked_utc": datetime.now(timezone.utc).isoformat(),
        })
    by_part_stage = summarize(detail, ("part", "stage"))
    total_counts = summarize([{**row, "part": "TOTAL", "stage": "TOTAL"} for row in detail], ("part", "stage"))
    all_summary = by_part_stage + total_counts
    if args.write:
        write_csv(runtime / "tables" / "final_dec25_job_status_latest.csv", detail)
        write_csv(runtime / "tables" / "final_dec25_health_latest.csv", all_summary)
        counts = total_counts[0]
        (runtime / "tables" / "final_dec25_health_latest.json").write_text(json.dumps({
            "checked_utc": datetime.now(timezone.utc).isoformat(),
            **counts,
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"Runtime root: {runtime}")
    print_table(all_summary, ["part", "stage", "total", "completed", "running", "ready", "pending", "stale_running", "failed", "left_to_finish", "pct_complete"])
    failed = [row["job_id"] for row in detail if row["state"] == "failed"]
    stale = [row["job_id"] for row in detail if row["state"] == "stale_running"]
    ready = [row["job_id"] for row in detail if row["state"] == "ready"]
    print(f"Ready jobs: {', '.join(ready) if ready else 'none'}")
    print(f"Failed jobs: {', '.join(failed) if failed else 'none'}")
    print(f"Stale running markers: {', '.join(stale) if stale else 'none'}")
    if args.fail_on_not_ready and (failed or stale or total_counts[0]["left_to_finish"] != 0):
        return 1
    return 2 if failed or stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
