#!/usr/bin/env python3
"""Monitor R60, run validation-only postfit repair, and close out when complete."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
GRID = DATA / "experiment_grids/pricefm_stage_r60_joint_repair_20260826"
OUTPUT = DATA / "authoritative/pricefm_stage_r60_joint_repair_monitor_20260826"
REPAIR_OUTPUT = DATA / "authoritative/pricefm_stage_r60_joint_repair_postfit_20260826"
CLOSEOUT = DATA / "authoritative/pricefm_stage_r60_joint_repair_closeout_20260826"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=GRID / "launch_manifest.csv")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--repair-output-dir", type=Path, default=REPAIR_OUTPUT)
    p.add_argument("--closeout-output-dir", type=Path, default=CLOSEOUT)
    p.add_argument("--python-bin", type=Path, default=Path(sys.executable))
    p.add_argument("--poll-seconds", type=int, default=60)
    p.add_argument("--expected-runs", type=int, default=4)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--once", type=parse_bool, default=False)
    return p


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text()) if path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        return {}


def health(manifest: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    rows = []
    fit_artifacts = {
        "model_predictions_scaled.csv", "model_trace_summary.csv",
        "model_parameter_summary.csv", "crossing_diagnostics.csv",
        "joint_vb_initialization.rds",
    }
    for row in manifest.itertuples(index=False):
        model = Path(row.output_dir)
        summary = read_json(model / "job_summary.json")
        fit_artifact_complete = all((model / name).is_file() for name in fit_artifacts)
        fit_terminal = summary.get("status") in {"completed", "failed"}
        repairable = fit_artifact_complete and fit_terminal
        postfit_complete = (
            summary.get("status") == "completed" and summary.get("postfit_repaired") is True
            and (model / "raw_contract_metric_summary.csv").is_file()
        )
        rows.append({
            "case_id": row.case_id, "source_case_id": row.source_case_id,
            "region": row.region, "fold": int(row.fold), "arm_id": row.arm_id,
            "status": summary.get("status", "pending"),
            "fit_artifact_complete": fit_artifact_complete, "repairable": repairable,
            "postfit_complete": postfit_complete,
            "converged": bool(summary.get("converged", False)),
            "iterations": summary.get("iterations", ""),
            "final_max_change": summary.get("final_max_change", ""),
            "test_opened": bool(summary.get("test_accessed", False)),
            "output_dir": str(model),
        })
    frame = pd.DataFrame(rows)
    counts = {
        "expected_runs": int(len(frame)),
        "fit_artifact_complete": int(frame.fit_artifact_complete.sum()),
        "repairable": int(frame.repairable.sum()),
        "postfit_complete": int(frame.postfit_complete.sum()),
        "failed_unrepairable": int((frame.status.eq("failed") & ~frame.repairable).sum()),
        "pending_or_running": int((~frame.repairable & ~frame.status.eq("failed")).sum()),
        "test_opened": bool(frame.test_opened.any()),
    }
    return frame, counts


def run_command(command: list[str]) -> dict:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stdout + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    for start in range(len(lines)):
        try:
            return json.loads("\n".join(lines[start:]))
        except json.JSONDecodeError:
            continue
    raise RuntimeError(f"Command returned no JSON: {' '.join(command)}")


def run(args: argparse.Namespace) -> dict:
    manifest = pd.read_csv(args.manifest)
    if len(manifest) != args.expected_runs:
        raise RuntimeError("R60 monitor manifest count changed")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    repair_script = Path(__file__).with_name("205_repair_pricefm_stage_r57_joint_vb_postfit.py")
    closeout_script = Path(__file__).with_name("210_closeout_pricefm_stage_r60_joint_repair.py")
    while True:
        frame, counts = health(manifest)
        frame.to_csv(args.output_dir / "pricefm_stage_r60_joint_repair_health.csv", index=False)
        status = "running"
        repair_summary, closeout_summary = {}, {}
        if counts["test_opened"]:
            status = "blocked_test_firewall_violation"
        elif counts["failed_unrepairable"]:
            status = "blocked_fit_failure"
        elif counts["repairable"] == args.expected_runs:
            repair_summary = run_command([
                str(args.python_bin), str(repair_script), "--manifest", str(args.manifest),
                "--output-dir", str(args.repair_output_dir), "--cleanup-heavy", "true",
                "--workers", str(args.workers), "--force", "false",
            ])
            frame, counts = health(manifest)
            frame.to_csv(args.output_dir / "pricefm_stage_r60_joint_repair_health.csv", index=False)
            if counts["postfit_complete"] == args.expected_runs and not repair_summary.get("repair_failures", 0):
                closeout_summary = run_command([
                    str(args.python_bin), str(closeout_script), "--manifest", str(args.manifest),
                    "--output-dir", str(args.closeout_output_dir), "--expected-runs",
                    str(args.expected_runs), "--force", "true",
                ])
                status = "completed"
            else:
                status = "blocked_postfit_failure"
        result = {
            "status": status, **counts, "repair_summary": repair_summary,
            "closeout_summary": closeout_summary, "models_refit_by_monitor": 0,
            "test_opened": counts["test_opened"], "mcmc_launch_authorized": False,
            "registry_mutation_authorized": False, "article_mutation_authorized": False,
        }
        write_json(args.output_dir / "summary.json", result)
        if status != "running" or args.once:
            return result
        time.sleep(max(1, args.poll_seconds))


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
