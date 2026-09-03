#!/usr/bin/env python3
"""Read-only health monitor for the Stage-R72 atomic AL repair campaign."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
from typing import Any

import pandas as pd


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r72_missing_al_repair_20260901"
MANIFEST = DATA / "experiment_grids" / TAG / "task_manifest.csv"
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--write-json", type=Path, default=None)
    return p


def active_processes() -> list[dict[str, Any]]:
    result = subprocess.run(
        ["pgrep", "-af", "243_run_pricefm_stage_r72_repair_component|246_launch_pricefm_stage_r72"],
        text=True, capture_output=True, check=False,
    )
    rows = []
    for line in result.stdout.splitlines():
        if not line.strip() or "247_monitor" in line or "pgrep -af" in line:
            continue
        pid, command = line.split(" ", 1)
        rows.append({"pid": int(pid), "command": command})
    return rows


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    counts = {"completed": 0, "failed": 0, "running_or_pending": 0}
    spd_relative_max = 0.0
    adaptive_tasks = 0
    binaries = 0
    bytes_used = 0
    case_rows = []
    for row in manifest.itertuples(index=False):
        output = Path(row.output_dir)
        terminal_path = output / "terminal.json"
        state = "running_or_pending"
        terminal = {}
        if terminal_path.is_file():
            terminal = json.loads(terminal_path.read_text())
            state = terminal.get("status", state)
            if state not in counts:
                state = "running_or_pending"
        counts[state] += 1
        spd = output / "spd_factorization_trace.csv"
        if spd.is_file():
            frame = pd.read_csv(spd)
            relative = pd.to_numeric(frame.relative_jitter, errors="coerce")
            if relative.notna().any():
                spd_relative_max = max(spd_relative_max, float(relative.max()))
            if frame.factorization_path.eq("scale_aware_symmetric_relative").any():
                adaptive_tasks += 1
        if output.exists():
            for path in output.rglob("*"):
                if path.is_file():
                    bytes_used += path.stat().st_size
                    binaries += int(path.suffix in BINARY_SUFFIXES)
        case_rows.append({
            "task_id": row.task_id, "case_id": row.case_id, "tau": row.tau,
            "status": state, "converged": terminal.get("converged"),
        })
    active = active_processes()
    if counts["completed"] == len(manifest) and not active:
        state = "completed"
    elif active:
        state = "running"
    elif counts["failed"]:
        state = "incomplete_with_failures"
    elif counts["completed"]:
        state = "incomplete_stalled"
    else:
        state = "not_started"
    result = {
        "state": state, "expected_tasks": int(len(manifest)),
        "completed_tasks": counts["completed"], "failed_tasks": counts["failed"],
        "remaining_tasks": int(len(manifest) - counts["completed"] - counts["failed"]),
        "active_processes": active, "active_process_count": len(active),
        "adaptive_spd_tasks": adaptive_tasks,
        "max_relative_spd_jitter": spd_relative_max,
        "binary_model_artifact_count": binaries,
        "runtime_gib": round(bytes_used / 1024**3, 4),
        "test_opened": False, "registry_mutated": False, "article_mutated": False,
        "task_states": case_rows,
    }
    if args.write_json:
        args.write_json.parent.mkdir(parents=True, exist_ok=True)
        args.write_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
