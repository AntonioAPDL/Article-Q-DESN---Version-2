#!/usr/bin/env python3
"""Read-only health monitor for the gated corrected R66 VB campaign."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess

import pandas as pd

from pricefm_common import write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r66_corrected_structured_exal_vb_20260829"
MANIFEST = DATA / "experiment_grids" / TAG / "case_manifest.csv"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--write-json", type=Path, default=None)
    return p


def active_processes() -> list[dict]:
    result = subprocess.run(
        ["pgrep", "-af", "230_run_pricefm_stage_r66|231_launch_pricefm_stage_r66"],
        text=True,
        capture_output=True,
        check=False,
    )
    rows = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        pid, command = line.split(" ", 1)
        if (
            "232_monitor_pricefm_stage_r66" not in command
            and "pgrep -af" not in command
        ):
            rows.append({"pid": int(pid), "command": command})
    return rows


def run(args: argparse.Namespace) -> dict:
    manifest = pd.read_csv(args.manifest)
    status_path = args.manifest.parent / "launch_status.csv"
    status = pd.read_csv(status_path) if status_path.is_file() else pd.DataFrame()
    terminal_components = 0
    eligible_components = 0
    telemetry_pass_components = 0
    reused_al_components = 0
    metric_complete = 0
    failed_logs = 0
    bytes_used = 0
    case_states = []
    status_by_case = status.set_index("case_id").status.to_dict() if not status.empty else {}
    for row in manifest.itertuples(index=False):
        output = Path(row.output_dir)
        case_root = output.parent
        if case_root.exists():
            bytes_used += sum(path.stat().st_size for path in case_root.rglob("*") if path.is_file())
        component_path = output / "r66_component_status.csv"
        if component_path.is_file():
            component = pd.read_csv(component_path)
            terminal_components += len(component)
            if "selection_eligible" in component:
                eligible_components += int(component.selection_eligible.map(lambda value: str(value).lower() == "true").sum())
            if "structured_telemetry_pass" in component:
                telemetry_pass_components += int(component.structured_telemetry_pass.map(lambda value: str(value).lower() == "true").sum())
            if "al_reused_from_r65" in component:
                reused_al_components += int(component.al_reused_from_r65.map(lambda value: str(value).lower() == "true").sum())
        if (output / "metric_summary.csv").is_file():
            metric_complete += 1
        log = case_root / "worker.log"
        if log.is_file() and "END returncode=0" not in log.read_text(errors="replace") and "Traceback" in log.read_text(errors="replace"):
            failed_logs += 1
        case_states.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "launcher_status": status_by_case.get(row.case_id, "pending_or_running"),
            "terminal_components": len(pd.read_csv(component_path)) if component_path.is_file() else 0,
            "metric_complete": (output / "metric_summary.csv").is_file(),
        })
    active = active_processes()
    gate_path = args.manifest.parent / "production_gate.json"
    gate = json.loads(gate_path.read_text()) if gate_path.is_file() else {
        "status": "not_evaluated",
        "passed": False,
        "broad_launch_authorized_by_gate": False,
    }
    complete_statuses = {
        "completed",
        "completed_with_quarantine",
        "skipped_completed",
        "skipped_completed_with_quarantine",
    }
    completed_status = int(status.status.isin(complete_statuses).sum()) if not status.empty else 0
    failed_status = int(status.status.isin(["failed", "launcher_exception"]).sum()) if not status.empty else 0
    if gate.get("status") == "production_gate_blocked" and not active:
        state = "broad_launch_blocked_by_gate"
    elif metric_complete == len(manifest) and failed_status == 0:
        state = "completed"
    elif active:
        state = "running"
    elif failed_status or failed_logs:
        state = "incomplete_with_failures"
    elif terminal_components or not status.empty:
        state = "incomplete_stalled"
    else:
        state = "not_started"
    disk = shutil.disk_usage(DATA)
    result = {
        "state": state,
        "expected_cases": len(manifest),
        "metric_complete_cases": metric_complete,
        "remaining_cases": len(manifest) - metric_complete,
        "status_completed_cases": completed_status,
        "status_failed_cases": failed_status,
        "expected_components": len(manifest) * 7,
        "terminal_components": terminal_components,
        "eligible_components": eligible_components,
        "structured_telemetry_pass_components": telemetry_pass_components,
        "reused_r65_al_components": reused_al_components,
        "production_gate": gate,
        "active_r66_processes": len(active),
        "active_processes": active,
        "runtime_bytes": bytes_used,
        "runtime_gib": round(bytes_used / 1024**3, 3),
        "free_disk_gib": round(disk.free / 1024**3, 3),
        "test_opened": False,
        "case_states": case_states,
    }
    if args.write_json:
        write_json(args.write_json, result)
    return result


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
