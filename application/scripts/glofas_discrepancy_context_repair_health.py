#!/usr/bin/env python3
"""Health report for the staged GloFAS discrepancy-context repair campaign."""

import argparse
import csv
import datetime as dt
from pathlib import Path
import sys


RUNNING = {"running", "running_external"}
COMPLETE = {"completed", "completed_existing"}
FAILED_PREFIX = "failed"


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--details", action="store_true")
    return parser.parse_args()


def read_csv(path):
    path = Path(path)
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_last_csv(path):
    rows = read_csv(path)
    return rows[-1] if rows else {}


def atomic_csv(path, rows, fields):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    tmp.replace(path)


def classify(manifest_row, state, root):
    candidate_id = manifest_row["candidate_id"]
    run_dir = Path(manifest_row["run_dir"])
    worker = read_last_csv(root / "status" / f"{candidate_id}.csv")
    state_status = state.get("status", "")
    marker = run_dir / ".fit_recovery_complete"
    if marker.exists():
        status = "completed"
    elif worker.get("status") == "failed" or state_status.startswith(FAILED_PREFIX):
        status = "failed"
    elif worker.get("status") == "running" or state_status in RUNNING:
        status = "running"
    elif state_status == "stopped_before_launch":
        status = "stopped"
    else:
        status = "pending"
    log_path = Path(manifest_row["log_path"])
    log_age_minutes = ""
    log_size_bytes = ""
    if log_path.exists():
        now = dt.datetime.now().timestamp()
        log_age_minutes = f"{max(0, (now - log_path.stat().st_mtime) / 60):.1f}"
        log_size_bytes = str(log_path.stat().st_size)
    return {
        "candidate_id": candidate_id,
        "base_candidate_id": manifest_row.get("base_candidate_id", ""),
        "cutoff_id": manifest_row.get("cutoff_id", ""),
        "selection_role": manifest_row.get("selection_role", ""),
        "execution_stage": manifest_row.get("execution_stage", ""),
        "status": status,
        "stage": worker.get("stage", state_status),
        "pid": worker.get("pid", state.get("pid", "")),
        "cpu_set": state.get("cpu_set", state.get("core", "")),
        "started_at": state.get("started_at", ""),
        "finished_at": state.get("finished_at", ""),
        "return_code": worker.get("exit_code", state.get("return_code", "")),
        "log_age_minutes": log_age_minutes,
        "log_size_bytes": log_size_bytes,
    }


def main():
    args = parse_args()
    root = Path(args.output_root).resolve()
    manifest = read_csv(root / "runtime_manifest.csv")
    if not manifest:
        raise SystemExit(f"Missing or empty runtime manifest: {root}")
    state_rows = []
    for name in ("scheduler_state_stage0.csv", "scheduler_state_stage1.csv"):
        state_rows.extend(read_csv(root / name))
    states = {row["candidate_id"]: row for row in state_rows}
    rows = [
        classify(row, states.get(row["candidate_id"], {}), root)
        for row in manifest
    ]
    fields = list(rows[0])
    atomic_csv(root / "status" / "health_latest.csv", rows, fields)
    counts = {
        label: sum(row["status"] == label for row in rows)
        for label in ("completed", "running", "pending", "failed", "stopped")
    }
    total = len(rows)
    done = counts["completed"]
    remaining = total - done
    percent = 100.0 * done / total
    print("GloFAS discrepancy-context repair")
    print(
        f"total={total} completed={done} ({percent:.1f}%) "
        f"running={counts['running']} pending={counts['pending']} "
        f"failed={counts['failed']} stopped={counts['stopped']} remaining={remaining}"
    )
    print(f"root={root}")
    for stage in ("stage0", "stage1"):
        block = [row for row in rows if row["execution_stage"] == stage]
        if not block:
            continue
        stage_done = sum(row["status"] == "completed" for row in block)
        stage_running = sum(row["status"] == "running" for row in block)
        stage_failed = sum(row["status"] == "failed" for row in block)
        print(
            f"{stage}: completed={stage_done}/{len(block)} "
            f"running={stage_running} failed={stage_failed}"
        )
    print(
        "stage0_gate="
        + (
            "passed" if (root / ".stage0_passed").exists()
            else "failed" if (root / ".stage0_failed").exists()
            else "pending"
        )
    )
    gate_summary = read_last_csv(root / "tables" / "stage0_gate_summary.csv")
    if gate_summary and "required_passed" in gate_summary:
        print(
            "stage0_policy="
            f"required={gate_summary.get('required_passed', '')}/"
            f"{gate_summary.get('required_fits', '')} "
            f"advisory={gate_summary.get('advisory_passed', '')}/"
            f"{gate_summary.get('advisory_fits', '')} "
            f"semantic_contracts={gate_summary.get('all_semantic_contracts_pass', '')} "
            f"authorized={gate_summary.get('stage1_authorized', '')}"
        )
    ranking = read_csv(root / "tables" / "context_repair_candidate_ranking.csv")
    if ranking:
        leader = ranking[0]
        print(
            "finalized=true "
            f"leader={leader.get('candidate_id', '')} "
            f"primary_check_loss={leader.get('future_p50_check_loss', '')} "
            f"passes_all={leader.get('passes_all_development_gates', '')}"
        )
    else:
        print("finalized=false")
    if args.details:
        print("candidate_id\tcutoff\texecution_stage\tstatus\tworker_stage\tcpu\tlog_age_min")
        for row in rows:
            print(
                f"{row['candidate_id']}\t{row['cutoff_id']}\t{row['execution_stage']}\t"
                f"{row['status']}\t"
                f"{row['stage']}\t{row['cpu_set']}\t{row['log_age_minutes']}"
            )
    return 2 if counts["failed"] or counts["stopped"] else 0


if __name__ == "__main__":
    sys.exit(main())
