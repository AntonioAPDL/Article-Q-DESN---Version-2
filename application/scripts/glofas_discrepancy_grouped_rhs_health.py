#!/usr/bin/env python3

import argparse
import csv
import datetime as dt
import os
import pathlib
import re


def parse_args():
    parser = argparse.ArgumentParser(description="Health report for the grouped-RHS GloFAS campaign.")
    parser.add_argument("--output-root", required=True)
    return parser.parse_args()


def read_rows(path):
    path = pathlib.Path(path)
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def pid_alive(value):
    try:
        os.kill(int(value), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True


def checkpoint_valid(path):
    path = pathlib.Path(path)
    return path.is_file() and pathlib.Path(str(path) + ".sha256").is_file()


def max_iteration(log_path):
    path = pathlib.Path(log_path)
    if not path.exists():
        return 0
    text = path.read_text(encoding="utf-8", errors="replace")
    values = [int(value) for value in re.findall(r"\[latent-path VB\] iter=(\d+)\b", text)]
    return max(values, default=0)


def classify(row, output_root, scheduler_state=None, max_iter=200):
    scheduler_state = scheduler_state or {}
    run_dir = pathlib.Path(row["run_dir"])
    status_rows = read_rows(pathlib.Path(output_root) / "status" / f"{row['candidate_id']}.csv")
    worker = status_rows[-1] if status_rows else {}
    iteration = max_iteration(row["log_path"])
    stage = worker.get("stage", scheduler_state.get("status", "not_started"))
    pid = worker.get("pid", scheduler_state.get("pid", ""))
    if (run_dir / ".fit_recovery_complete").exists():
        state, progress = "completed", 100.0
    elif (run_dir / ".reservoir_preflight_rejected").exists():
        state, progress = "preflight_rejected", 100.0
    elif (worker.get("status") == "running" or scheduler_state.get("status") in {"running", "running_external"}) and pid_alive(pid):
        state = "running"
        progress = min(98.0, 95.0 * iteration / max_iter) if stage == "03_fit_models" else 98.0
    elif worker.get("status") == "failed" or scheduler_state.get("status", "").startswith("failed"):
        state, progress = "failed", min(99.0, 95.0 * iteration / max_iter)
    elif checkpoint_valid(row.get("checkpoint_path", "")):
        state, progress = "interrupted_resumable", min(95.0, 95.0 * iteration / 200.0)
    else:
        state, progress = "pending", 0.0
    log_path = pathlib.Path(row["log_path"])
    age_minutes = ""
    if log_path.exists():
        age_minutes = f"{(dt.datetime.now().timestamp() - log_path.stat().st_mtime) / 60.0:.2f}"
    return {
        "candidate_id": row["candidate_id"],
        "wave": row.get("wave", ""),
        "priority": row["priority"],
        "state": state,
        "stage": stage,
        "iteration": str(iteration),
        "max_iter": str(max_iter),
        "progress_percent": f"{progress:.1f}",
        "pid": pid,
        "log_age_minutes": age_minutes,
        "run_id": row["run_id"],
        "log_path": row["log_path"],
    }


def atomic_csv(path, rows):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = pathlib.Path(str(path) + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp, path)


def main():
    args = parse_args()
    root = pathlib.Path(args.output_root).resolve()
    manifest = read_rows(root / "runtime_manifest_all.csv")
    if not manifest:
        raise RuntimeError("runtime_manifest_all.csv is missing or empty")
    scheduler_rows = []
    for path in (root / "status").glob("scheduler_state_*.csv"):
        scheduler_rows.extend(read_rows(path))
    scheduler_by_id = {row.get("candidate_id", ""): row for row in scheduler_rows}
    contracts = {
        row.get("candidate_id", ""): row
        for row in read_rows(root / "candidate_contracts.csv")
    }
    rows = [
        classify(
            row,
            root,
            scheduler_state=scheduler_by_id.get(row["candidate_id"], {}),
            max_iter=int(float(contracts.get(row["candidate_id"], {}).get("max_iter", 200))),
        )
        for row in manifest
    ]
    atomic_csv(root / "health_summary.csv", rows)
    states = ("completed", "running", "pending", "interrupted_resumable", "preflight_rejected", "failed")
    print("state,count")
    for state in states:
        print(f"{state},{sum(row['state'] == state for row in rows)}")
    print(f"total,{len(rows)}")
    print(f"finished_percent,{100.0 * sum(row['state'] in {'completed', 'preflight_rejected', 'failed'} for row in rows) / len(rows):.1f}")


if __name__ == "__main__":
    main()
