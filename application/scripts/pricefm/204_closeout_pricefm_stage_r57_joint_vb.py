#!/usr/bin/env python3
"""Legacy raw-gate closeout retained behind an explicit compatibility guard."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
AUTHORITY = DATA / "authoritative/pricefm_stage_r57_joint_authority_freeze_20260824"
GRID = DATA / "experiment_grids/pricefm_stage_r57_joint_vb_20260824"
OUTPUT = DATA / "authoritative/pricefm_stage_r57_joint_vb_validation_closeout_20260824"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--authority-dir", type=Path, default=AUTHORITY)
    p.add_argument("--grid-dir", type=Path, default=GRID)
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--expected-cases", type=int, default=114)
    p.add_argument(
        "--legacy-raw-gate-authorized", type=parse_bool, default=False,
        help="Explicitly reproduce the superseded zero-raw-crossing gate",
    )
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare_output(path: Path, force: bool) -> None:
    if path.exists() and any(path.iterdir()) and not force:
        raise FileExistsError(f"Output exists: {path}")
    path.mkdir(parents=True, exist_ok=True)


def read_summary(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return {}


def validation_metric(path: Path, method_id: str) -> float:
    frame = pd.read_csv(path)
    rows = frame[
        frame.method_id.astype(str).eq(str(method_id))
        & frame.split.astype(str).eq("val")
        & frame.unit.astype(str).eq("original")
    ]
    if len(rows) != 1:
        raise RuntimeError(f"Expected one original-scale validation metric for {method_id}: {path}")
    value = float(rows.iloc[0].AQL)
    if not math.isfinite(value):
        raise RuntimeError(f"Nonfinite validation AQL: {path}")
    return value


def run(args: argparse.Namespace) -> dict:
    if not args.legacy_raw_gate_authorized:
        raise RuntimeError(
            "Stage-R57 legacy raw-crossing closeout is superseded by the Stage-R58 "
            "dual-role recovery audit; pass --legacy-raw-gate-authorized true only "
            "to reproduce the historical gate."
        )
    output = args.output_dir.resolve()
    prepare_output(output, args.force)
    authority_path = args.authority_dir / "pricefm_stage_r57_joint_case_authority.csv"
    manifest_path = args.grid_dir / "launch_manifest.csv"
    authority = pd.read_csv(authority_path)
    manifest = pd.read_csv(manifest_path)
    if len(authority) != args.expected_cases or len(manifest) != args.expected_cases:
        raise RuntimeError("R57 closeout inputs do not contain the expected full surface")
    if "qdesn_AQL" in authority.columns or "pricefm_AQL" in authority.columns:
        raise RuntimeError("Sealed test outcomes leaked into the validation closeout authority")
    merged = authority.merge(
        manifest[["case_id", "method_id", "output_dir"]], on="case_id", how="inner", validate="one_to_one"
    )
    health_rows, decisions = [], []
    for row in merged.sort_values(["region", "fold"]).itertuples(index=False):
        model_dir = Path(row.output_dir)
        summary_path = model_dir / "job_summary.json"
        metric_path = model_dir / "metric_summary.csv"
        summary = read_summary(summary_path)
        completed = summary.get("status") == "completed" and metric_path.is_file()
        health_rows.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "status": summary.get("status", "missing"), "completed": completed,
            "converged": bool(summary.get("converged", False)),
            "validation_crossing_rows": summary.get("validation_crossing_rows", ""),
            "job_summary": str(summary_path), "metric_summary": str(metric_path),
        })
        if not completed:
            continue
        value = validation_metric(metric_path, row.method_id)
        reference = float(row.current_authoritative_validation_AQL)
        finite = math.isfinite(reference) and math.isfinite(value)
        no_crossing = int(summary.get("validation_crossing_rows", -1)) == 0
        converged = bool(summary.get("converged", False))
        improves = finite and value < reference
        eligible = completed and finite and no_crossing and converged and improves
        decisions.append({
            "case_id": row.case_id, "region": row.region, "fold": int(row.fold),
            "likelihood_family": row.likelihood_family, "method_id": row.method_id,
            "source_method_id": row.source_method_id,
            "source_experiment_id": row.experiment_id,
            "current_authoritative_validation_AQL": reference,
            "joint_vb_validation_AQL": value,
            "validation_delta_joint_minus_authority": value - reference,
            "validation_relative_gain": (reference - value) / reference if reference != 0 else float("nan"),
            "fit_converged": converged,
            "validation_crossing_rows": int(summary.get("validation_crossing_rows", -1)),
            "validation_improves_authority": improves,
            "validation_selected": eligible,
            "mcmc_confirmation_eligible": eligible,
            "selection_role": "validation_only",
            "test_opened": False,
            "checkpoint": summary.get("checkpoint", ""),
            "checkpoint_sha256": summary.get("checkpoint_sha256", ""),
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        })

    health = pd.DataFrame(health_rows)
    health.to_csv(output / "pricefm_stage_r57_joint_vb_health.csv", index=False)
    complete = int(health.completed.sum())
    failed = int(health.status.eq("failed").sum())
    if complete != args.expected_cases:
        summary = {
            "status": "incomplete_waiting_for_joint_vb",
            "expected_cases": args.expected_cases,
            "completed_cases": complete,
            "remaining_cases": args.expected_cases - complete,
            "failed_cases": failed,
            "validation_decisions_frozen": False,
            "test_opened": False,
            "mcmc_launch_authorized": False,
            "registry_mutation_authorized": False,
            "article_mutation_authorized": False,
        }
        write_json(output / "summary.json", summary)
        return summary

    decisions_frame = pd.DataFrame(decisions).sort_values(["region", "fold"]).reset_index(drop=True)
    if len(decisions_frame) != args.expected_cases:
        raise RuntimeError("Completed R57 surface did not yield one validation decision per case")
    queue = decisions_frame[decisions_frame.mcmc_confirmation_eligible].copy()
    decisions_frame.to_csv(output / "pricefm_stage_r57_joint_vb_validation_decision_freeze.csv", index=False)
    queue.to_csv(output / "pricefm_stage_r57_joint_mcmc_confirmation_queue.csv", index=False)
    gates = pd.DataFrame([
        {"gate": "all_cases_completed", "passed": complete == args.expected_cases, "observed": complete},
        {"gate": "all_metrics_original_validation", "passed": len(decisions_frame) == args.expected_cases, "observed": len(decisions_frame)},
        {"gate": "selection_validation_only", "passed": decisions_frame.selection_role.eq("validation_only").all(), "observed": "all"},
        {"gate": "test_not_opened", "passed": ~decisions_frame.test_opened.any(), "observed": False},
        {"gate": "registry_article_blocked", "passed": True, "observed": "blocked"},
    ])
    gates.to_csv(output / "pricefm_stage_r57_joint_vb_closeout_gates.csv", index=False)
    source_paths = [authority_path, manifest_path, Path(__file__).resolve()]
    for row in decisions_frame.itertuples(index=False):
        source_paths.extend([Path(row.checkpoint), Path(next(x.metric_summary for x in health.itertuples() if x.case_id == row.case_id))])
    source_rows = [
        {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}
        for path in source_paths if path.is_file()
    ]
    pd.DataFrame(source_rows).drop_duplicates(["path", "sha256"]).to_csv(output / "source_manifest.csv", index=False)
    summary = {
        "status": "completed_validation_only_closeout",
        "expected_cases": args.expected_cases,
        "completed_cases": complete,
        "failed_cases": failed,
        "validation_improvements": int(decisions_frame.validation_improves_authority.sum()),
        "mcmc_confirmation_candidates": len(queue),
        "validation_decisions_frozen": True,
        "test_opened": False,
        "mcmc_launch_authorized": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)
    (output / "pricefm_stage_r57_joint_vb_validation_closeout_report.md").write_text(
        "# PriceFM Stage-R57 joint VB validation closeout\n\n"
        f"All {complete} joint seven-quantile cases completed. Validation-only selection identified "
        f"{len(queue)} cases that improve on the current authoritative validation AQL, converge, and "
        "have no raw-quantile crossings. These cases form the bounded MCMC confirmation queue.\n\n"
        "The sealed current-Q-DESN and cached-PriceFM test ledger was not opened. MCMC launch, test "
        "audit, registry mutation, and article mutation remain separately gated.\n"
    )
    return summary


if __name__ == "__main__":
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
