#!/usr/bin/env python3
"""Read-only health monitor for the Stage-R70 CRAN 1.1.1 independent VB campaign."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
from typing import Any

import pandas as pd

from pricefm_common import write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
TAG = "pricefm_stage_r69b_bounded_cran111_independent_vb_20260831"
MANIFEST = DATA / "experiment_grids" / TAG / "case_manifest.csv"
METHODS = {
    "qdesn_al_rhs_ns_cran111_r69b",
    "qdesn_exal_rhs_ns_cran111_r69b",
}
BINARY_SUFFIXES = {".rds", ".rda", ".RData", ".rdata"}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=MANIFEST)
    p.add_argument("--write-json", type=Path, default=None)
    return p


def boolish(value: Any) -> bool:
    try:
        if pd.isna(value):
            return False
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def active_processes() -> list[dict[str, Any]]:
    result = subprocess.run(
        ["pgrep", "-af", "238_run_pricefm_stage_r70|239_launch_pricefm_stage_r70"],
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
            "240_monitor_pricefm_stage_r70" not in command
            and "pgrep -af" not in command
        ):
            rows.append({"pid": int(pid), "command": command})
    return rows


def status_counts(status: pd.DataFrame) -> dict[str, int]:
    if status.empty or "status" not in status:
        return {}
    return {
        str(key): int(value)
        for key, value in status["status"].value_counts().sort_index().items()
    }


def case_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def run(args: argparse.Namespace) -> dict[str, Any]:
    manifest = pd.read_csv(args.manifest)
    status_path = args.manifest.parent / "launch_status.csv"
    status = pd.read_csv(status_path) if status_path.is_file() else pd.DataFrame()
    status_by_case = status.set_index("case_id").status.to_dict() if not status.empty else {}
    preflight_path = args.manifest.parent / "launch_preflight.json"
    summary_path = args.manifest.parent / "launch_summary.json"
    preflight = json.loads(preflight_path.read_text()) if preflight_path.is_file() else {}
    launch_summary = json.loads(summary_path.read_text()) if summary_path.is_file() else {}

    terminal_components = 0
    eligible_components = 0
    metric_complete = 0
    beta_complete = 0
    binary_artifact_count = 0
    failed_logs = 0
    bytes_used = 0
    case_states = []

    for row in manifest.itertuples(index=False):
        output = Path(row.output_dir)
        case_root = output.parent
        bytes_used += case_bytes(case_root)
        component_path = output / "r70_component_status.csv"
        terminal = 0
        eligible = 0
        if component_path.is_file():
            component = pd.read_csv(component_path)
            terminal = len(component)
            terminal_components += terminal
            if "selection_eligible" in component:
                eligible = int(component.selection_eligible.map(boolish).sum())
                eligible_components += eligible
        if (output / "metric_summary.csv").is_file():
            metric_complete += 1
        if (output / "model_beta_mean.csv").is_file():
            beta_complete += 1
        if output.exists():
            binary_artifact_count += sum(
                1 for path in output.rglob("*") if path.is_file() and path.suffix in BINARY_SUFFIXES
            )
        log = case_root / "worker.log"
        log_text = log.read_text(errors="replace") if log.is_file() else ""
        if log_text and "END returncode=0" not in log_text and ("Error" in log_text or "Traceback" in log_text):
            failed_logs += 1
        case_states.append({
            "case_id": row.case_id,
            "region": row.region,
            "fold": int(row.fold),
            "launcher_status": status_by_case.get(row.case_id, "pending_or_running"),
            "terminal_components": terminal,
            "eligible_components": eligible,
            "metric_complete": (output / "metric_summary.csv").is_file(),
            "beta_complete": (output / "model_beta_mean.csv").is_file(),
        })

    active = active_processes()
    complete_statuses = {
        "completed",
        "completed_with_quarantine",
        "skipped_completed",
        "skipped_completed_with_quarantine",
    }
    failed_statuses = {"failed", "launcher_exception"}
    completed_status = int(status.status.isin(complete_statuses).sum()) if not status.empty else 0
    failed_status = int(status.status.isin(failed_statuses).sum()) if not status.empty else 0
    if metric_complete == len(manifest) and failed_status == 0 and not active:
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
        "expected_cases": int(len(manifest)),
        "metric_complete_cases": int(metric_complete),
        "remaining_cases": int(len(manifest) - metric_complete),
        "status_completed_cases": int(completed_status),
        "status_failed_cases": int(failed_status),
        "status_counts": status_counts(status),
        "expected_components": int(len(manifest) * 7),
        "terminal_components": int(terminal_components),
        "eligible_components": int(eligible_components),
        "beta_complete_cases": int(beta_complete),
        "binary_model_artifact_count": int(binary_artifact_count),
        "active_r70_processes": int(len(active)),
        "active_processes": active,
        "runtime_bytes": int(bytes_used),
        "runtime_gib": round(bytes_used / 1024**3, 3),
        "free_disk_gib": round(disk.free / 1024**3, 3),
        "preflight": preflight,
        "launch_summary": launch_summary,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
        "joint_model_authorized": False,
        "mcmc_authorized": False,
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
