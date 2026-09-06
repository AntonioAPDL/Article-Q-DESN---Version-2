#!/usr/bin/env python3
"""Report manifest-backed health for a prepared or running Part 4 DAG."""

import argparse
import csv
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", required=True)
    args = parser.parse_args()
    root = Path(args.runtime_root).resolve()
    manifest = root / "configs" / "part4_model_manifest.csv"
    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    status = root / "status"
    counts = {"completed": 0, "running": 0, "failed": 0, "pending": 0}
    for row in rows:
        job = row["run_id"]
        states = [name for name in ("completed", "running", "failed") if (status / f"{job}.{name}").exists()]
        if len(states) > 1:
            raise SystemExit(f"conflicting status markers for {job}: {states}")
        counts[states[0] if states else "pending"] += 1
    print("phase,total,completed,running,failed,pending,left")
    print(f"part4_latent_family,{len(rows)},{counts['completed']},{counts['running']},"
          f"{counts['failed']},{counts['pending']},{len(rows) - counts['completed']}")
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
