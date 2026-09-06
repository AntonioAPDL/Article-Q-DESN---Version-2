#!/usr/bin/env python3
"""Health check for the Part 2 bridge forecast chain."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else repo_root() / p


def rel(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def read_manifest(root: Path) -> list[dict]:
    path = root / "tables" / "part2_bridge_forecast_job_manifest.csv"
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in fieldnames})


def tmux_sessions() -> set[str]:
    try:
        out = subprocess.check_output(["tmux", "list-sessions", "-F", "#{session_name}"], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return set()
    return {line.strip() for line in out.splitlines() if line.strip()}


def deps(job: dict) -> list[str]:
    raw = job.get("dependencies", "")
    return [x for x in raw.split("|") if x]


def status_rows(root: Path, jobs: list[dict]) -> list[dict]:
    sessions = tmux_sessions()
    done = {j["job_id"] for j in jobs if resolve(j["status_done_path"]).exists()}
    rows = []
    for job in jobs:
        running = resolve(job["status_running_path"]).exists()
        failed = resolve(job["status_failed_path"]).exists()
        completed = resolve(job["status_done_path"]).exists()
        has_session = job["tmux_session"] in sessions
        dependencies = deps(job)
        deps_done = all(d in done for d in dependencies)
        if failed:
            state = "failed"
        elif completed:
            state = "completed"
        elif has_session or running:
            state = "running" if has_session else "stale_running"
        elif deps_done:
            state = "ready"
        else:
            state = "pending"
        rows.append(
            {
                **job,
                "state": state,
                "dependencies_done": str(deps_done),
                "n_dependencies": len(dependencies),
                "missing_dependencies": "|".join(d for d in dependencies if d not in done),
                "tmux_active": str(has_session),
                "checked_utc": datetime.now(timezone.utc).isoformat(),
            }
        )
    return rows


def health_rows(rows: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[row["model_family"]].append(row)
    groups["TOTAL"] = rows
    out = []
    for group in ["ridge", "rhs", "independent_al", "independent_exal", "joint_al", "joint_exal", "TOTAL"]:
        use = [r for r in rows if r["model_family"] == group] if group != "TOTAL" else rows
        if not use:
            continue
        counts = defaultdict(int)
        for r in use:
            counts[r["state"]] += 1
        total = len(use)
        done = counts["completed"]
        out.append(
            {
                "group": group,
                "total": total,
                "completed": done,
                "running": counts["running"],
                "ready": counts["ready"],
                "pending": counts["pending"],
                "stale_running": counts["stale_running"],
                "failed": counts["failed"],
                "left_to_finish": total - done,
                "pct_complete": f"{100.0 * done / total:.1f}",
            }
        )
    return out


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_artifacts(root: Path) -> None:
    rows = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        if path.name in {"artifact_manifest.csv", "artifact_file_list.csv"}:
            continue
        st = path.stat()
        rows.append(
            {
                "relative_path": rel(path, root),
                "repo_relative_path": rel(path, repo_root()),
                "size_bytes": st.st_size,
                "sha256": sha256_file(path),
                "mtime_utc": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(),
            }
        )
    write_csv(root / "tables" / "artifact_file_list.csv", rows, ["relative_path", "repo_relative_path", "size_bytes", "sha256", "mtime_utc"])
    manifest = [
        {
            "artifact_group": Path(r["relative_path"]).parts[0] if Path(r["relative_path"]).parts else ".",
            "path": r["relative_path"],
            "size_bytes": r["size_bytes"],
            "sha256": r["sha256"],
        }
        for r in rows
    ]
    write_csv(root / "tables" / "artifact_manifest.csv", manifest, ["artifact_group", "path", "size_bytes", "sha256"])


def print_table(rows: list[dict]) -> None:
    headers = ["group", "total", "completed", "running", "ready", "pending", "stale_running", "failed", "left_to_finish", "pct_complete"]
    widths = {h: max(len(h), *(len(str(r[h])) for r in rows)) for h in headers}
    print(" | ".join(h.ljust(widths[h]) for h in headers))
    print("-+-".join("-" * widths[h] for h in headers))
    for r in rows:
        print(" | ".join(str(r[h]).ljust(widths[h]) for h in headers))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime_root", required=True)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--fail_on_failed", action="store_true")
    args = parser.parse_args()
    root = resolve(args.runtime_root).resolve()
    jobs = read_manifest(root)
    rows = status_rows(root, jobs)
    health = health_rows(rows)
    if args.write:
      write_csv(root / "tables" / "part2_bridge_forecast_job_status_latest.csv", rows, list(rows[0].keys()) if rows else [])
      write_csv(root / "tables" / "part2_bridge_forecast_health_latest.csv", health, list(health[0].keys()) if health else [])
      write_artifacts(root)
    print(f"Runtime root: {rel(root, repo_root())}")
    print_table(health)
    running = [r["job_id"] for r in rows if r["state"] in {"running", "stale_running"}]
    ready = [r["job_id"] for r in rows if r["state"] == "ready"]
    failed = [r["job_id"] for r in rows if r["state"] == "failed"]
    print(f"Running: {', '.join(running) if running else 'none'}")
    print(f"Ready: {', '.join(ready) if ready else 'none'}")
    print(f"Failed: {', '.join(failed) if failed else 'none'}")
    return 2 if args.fail_on_failed and failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
