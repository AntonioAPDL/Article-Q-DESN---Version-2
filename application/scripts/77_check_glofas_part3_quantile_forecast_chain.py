#!/usr/bin/env python3
"""Report and persist Part 3 fit/forecast DAG health."""

import argparse
import csv
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def session_name(prefix: str, job: str) -> str:
    return f"{prefix}_{job}".replace(".", "p")[:78]


def alive(name: str) -> bool:
    return subprocess.run(["tmux", "has-session", "-t", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    parser.add_argument("--session-prefix", default="glofas_p3_20260904")
    args = parser.parse_args()
    runtime = Path(args.runtime_root).resolve()
    manifest = runtime / "configs" / "part3_quantile_forecast_job_manifest.csv"
    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    detail = []
    for row in rows:
        job = row["job_id"]
        state = "completed" if (runtime / "status" / f"{job}.completed").exists() else \
            "failed" if (runtime / "status" / f"{job}.failed").exists() else \
            "running" if alive(session_name(args.session_prefix, job)) else "pending"
        detail.append({"job_id": job, "phase": row["phase"], "state": state, "dependencies": row["dependencies"]})
    counts = {state: sum(row["state"] == state for row in detail) for state in ("completed", "running", "failed", "pending")}
    health_dir = runtime / "tables"
    health_dir.mkdir(parents=True, exist_ok=True)
    detail_path = health_dir / "part3_quantile_forecast_health_latest.csv"
    with detail_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(detail[0]))
        writer.writeheader(); writer.writerows(detail)
    summary = {"checked_at": datetime.now(timezone.utc).isoformat(), "total": len(detail), **counts, "left": len(detail) - counts["completed"]}
    (health_dir / "part3_quantile_forecast_health_latest.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
