#!/usr/bin/env python3

import argparse
import csv
import datetime as dt
import os
import pathlib
import shutil


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reconcile and report GloFAS fit-recovery batch health."
    )
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-root", required=True)
    return parser.parse_args()


def read_csv(path):
    path = pathlib.Path(path)
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(rows[0]) if rows else ["candidate_id", "status"]
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    os.replace(tmp, path)


def read_one(path):
    rows = read_csv(path)
    return rows[-1] if rows else {}


def pid_alive(pid_text):
    try:
        pid = int(pid_text)
    except (TypeError, ValueError):
        return False
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    return True


def directory_size(path, suffixes=None):
    path = pathlib.Path(path)
    if not path.exists():
        return 0
    total = 0
    for item in path.rglob("*"):
        if not item.is_file():
            continue
        if suffixes is not None and item.suffix.lower() not in suffixes:
            continue
        try:
            total += item.stat().st_size
        except FileNotFoundError:
            pass
    return total


def age_minutes(path):
    path = pathlib.Path(path)
    if not path.exists():
        return ""
    age = dt.datetime.now().timestamp() - path.stat().st_mtime
    return f"{max(age, 0.0) / 60.0:.1f}"


def available_memory_gb():
    values = {}
    with open("/proc/meminfo", encoding="utf-8") as handle:
        for line in handle:
            key, value = line.split(":", 1)
            values[key] = float(value.strip().split()[0])
    return values["MemAvailable"] / 1024.0 / 1024.0


def reconcile_status(row, scheduler, worker):
    run_dir = pathlib.Path(row["run_dir"])
    complete = (run_dir / ".fit_recovery_complete").exists()
    score = pathlib.Path(row["log_path"]).parents[1] / "scores" / (
        row["candidate_id"] + "_observed_fit_scores.csv"
    )
    worker_status = worker.get("status", "")
    worker_pid = worker.get("pid", "")
    scheduler_status = scheduler.get("status", "")
    scheduler_pid = scheduler.get("pid", "")
    live = pid_alive(worker_pid) or pid_alive(scheduler_pid)

    if complete and score.exists():
        return "completed", live
    if worker_status.startswith("failed") or scheduler_status.startswith("failed"):
        return "failed", live
    if live and (
        worker_status == "running"
        or scheduler_status in {"running", "running_external"}
    ):
        return "running", live
    if scheduler_status in {"stopped_before_launch", "completed_existing"}:
        return scheduler_status, live
    if worker_status == "running" or scheduler_status == "running":
        return "stale", live
    return scheduler_status or worker_status or "pending", live


def print_table(rows):
    columns = [
        "candidate_id", "status", "stage", "pid", "core",
        "log_age_min", "run_gb", "score_ready",
    ]
    widths = {
        column: max(len(column), *(len(str(row.get(column, ""))) for row in rows))
        for column in columns
    }
    print("  ".join(column.ljust(widths[column]) for column in columns))
    print("  ".join("-" * widths[column] for column in columns))
    for row in rows:
        print("  ".join(str(row.get(column, "")).ljust(widths[column]) for column in columns))


def main():
    args = parse_args()
    output_root = pathlib.Path(args.output_root).resolve()
    manifest = read_csv(args.manifest)
    scheduler_rows = {
        row["candidate_id"]: row
        for row in read_csv(output_root / "scheduler_state.csv")
    }
    rows = []
    for row in manifest:
        candidate_id = row["candidate_id"]
        scheduler = scheduler_rows.get(candidate_id, {})
        worker = read_one(output_root / "status" / f"{candidate_id}.csv")
        status, live = reconcile_status(row, scheduler, worker)
        run_dir = pathlib.Path(row["run_dir"])
        score_path = output_root / "scores" / f"{candidate_id}_observed_fit_scores.csv"
        log_path = pathlib.Path(row["log_path"])
        rows.append({
            "candidate_id": candidate_id,
            "priority": row["priority"],
            "status": status,
            "stage": worker.get("stage", ""),
            "pid": worker.get("pid", "") or scheduler.get("pid", ""),
            "pid_live": str(live).lower(),
            "core": scheduler.get("core", ""),
            "started_at": scheduler.get("started_at", ""),
            "finished_at": scheduler.get("finished_at", ""),
            "return_code": worker.get("exit_code", "") or scheduler.get("return_code", ""),
            "log_age_min": age_minutes(log_path),
            "run_gb": f"{directory_size(run_dir) / (1024.0 ** 3):.3f}",
            "heavy_gb": f"{directory_size(run_dir, {'.rds', '.rda', '.rdata'}) / (1024.0 ** 3):.3f}",
            "score_ready": str(score_path.exists()).lower(),
            "run_id": row["run_id"],
            "log_path": str(log_path),
        })

    write_csv(output_root / "health_summary.csv", rows)
    counts = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    resource = [{
        "checked_at": dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds"),
        "load_1m": f"{os.getloadavg()[0]:.2f}",
        "memory_available_gb": f"{available_memory_gb():.1f}",
        "disk_available_gb": f"{shutil.disk_usage(output_root).free / (1024.0 ** 3):.1f}",
        "total": str(len(rows)),
        "completed": str(counts.get("completed", 0) + counts.get("completed_existing", 0)),
        "running": str(counts.get("running", 0)),
        "pending": str(counts.get("pending", 0)),
        "failed": str(counts.get("failed", 0)),
        "stale": str(counts.get("stale", 0)),
    }]
    write_csv(output_root / "health_resources.csv", resource)
    print_table(rows)
    print()
    print(
        "summary: "
        + ", ".join(f"{key}={value}" for key, value in resource[0].items())
    )


if __name__ == "__main__":
    main()
